import AppKit
import Security

/// The Anthropic API key. Lives in the login Keychain (generic password, service "Ideator",
/// account "anthropic-api-key"): never in code, in the card folder, or in user defaults.
/// Read once at launch and cached; `set` is the only writer.
///
/// A scratch run gets `inKeychain: false`: the key lives in memory for that run only, starts empty,
/// and no Keychain call is ever made, so a verify run can't trigger macOS's access prompt for the
/// owner's key or touch it.
class KeyStore {
    private static let service = "Ideator"
    private static let account = "anthropic-api-key"

    /// nil = no key: the app works fully, it just never requests summaries.
    private(set) var apiKey: String?

    let inKeychain: Bool

    init(inKeychain: Bool) {
        self.inKeychain = inKeychain
        guard inKeychain else { return }
        var query = Self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            apiKey = String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Trims whitespace; an empty string deletes the key. Updates the Keychain, then the cache.
    /// Returns false if the Keychain refused the change.
    @discardableResult
    func set(_ key: String?) -> Bool {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard inKeychain else {
            apiKey = trimmed.isEmpty ? nil : trimmed
            return true
        }
        let status: OSStatus
        if trimmed.isEmpty {
            status = SecItemDelete(Self.baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { return false }
            apiKey = nil
            return true
        }
        let data = Data(trimmed.utf8)
        let update = SecItemUpdate(Self.baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = Self.baseQuery
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        } else {
            status = update
        }
        guard status == errSecSuccess else { return false }
        apiKey = trimmed
        return true
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

final class SettingsWindow: NSWindow {
    private static let width: CGFloat = 440
    private static let inner: CGFloat = 400

    static let privacy = "With a key saved, Ideator sends a card's text to Anthropic, using your own key, to "
        + "write its summary, whenever the card has no summary for its text as it is now. It does so, for "
        + "example, after you change a card, when you save a key, at launch after a failed try, and after an "
        + "update that changes how Ideator asks for summaries. The key stays in your login Keychain. Once a "
        + "day, and whenever you click Check Now, Ideator asks GitHub whether a newer version exists. GitHub "
        + "sees your IP address and which version you have. Nothing else leaves your Mac: no analytics, no "
        + "crash reports."

    private let keys: KeyStore
    private let hotKey: HotKey
    private let updates: Updates
    private let onChange: () -> Void
    private let shortcutField = ShortcutField()
    private let defaultButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let shortcutNote = NSTextField(wrappingLabelWithString: "")
    private let field = NSSecureTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let autoCheck = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
    private let checkNowButton = NSButton(title: "Check Now", target: nil, action: nil)
    private let stack = NSStackView()
    private var rejected: String?
    private var releasedForRecording = false

    init(keys: KeyStore, hotKey: HotKey, updates: Updates, onChange: @escaping () -> Void) {
        self.keys = keys
        self.hotKey = hotKey
        self.updates = updates
        self.onChange = onChange
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Ideator Settings"
        isReleasedWhenClosed = false

        func heading(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            return label
        }
        func caption(_ label: NSTextField) -> NSTextField {
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.preferredMaxLayoutWidth = Self.inner
            label.widthAnchor.constraint(equalToConstant: Self.inner).isActive = true
            return label
        }

        shortcutField.onPick = { [unowned self] picked in pick(picked) }
        shortcutField.onReject = { [unowned self] refusal in
            rejected = refusal
            refresh()
        }
        shortcutField.onRecordingChange = { [unowned self] recording in
            // Retake only what this recording released: a scratch run never registered one.
            if recording {
                releasedForRecording = hotKey.unregister()
                rejected = nil
            } else if releasedForRecording {
                releasedForRecording = false
                hotKey.register()
            }
            refresh()
        }
        defaultButton.target = self
        defaultButton.action = #selector(useDefaultShortcut)
        let shortcutRow = NSStackView(views: [shortcutField, defaultButton])
        shortcutRow.spacing = 8

        field.placeholderString = "sk-ant-…"
        field.target = self
        field.action = #selector(save)
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        let remove = NSButton(title: "Remove Key", target: self, action: #selector(remove))
        let buttons = NSStackView(views: [remove, save])

        autoCheck.target = self
        autoCheck.action = #selector(toggleAutomaticChecks)
        checkNowButton.target = self
        checkNowButton.action = #selector(checkNow)
        let updatesRow = NSStackView(views: [autoCheck, checkNowButton])
        updatesRow.distribution = .equalSpacing
        let updatesNote = NSTextField(wrappingLabelWithString: Self.updatesCaption(build: updates.build, plan: updates.plan))

        for view in [heading("Shortcut"), shortcutRow, caption(shortcutNote), heading("Anthropic API key"), field,
                     caption(status), buttons, heading("Updates"), updatesRow, caption(updatesNote),
                     heading("Privacy"), caption(NSTextField(wrappingLabelWithString: Self.privacy))] {
            stack.addArrangedSubview(view)
        }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: shortcutNote)
        stack.setCustomSpacing(18, after: buttons)
        stack.setCustomSpacing(18, after: updatesNote)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: Self.width),
            field.widthAnchor.constraint(equalToConstant: Self.inner),
            buttons.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            updatesRow.widthAnchor.constraint(equalToConstant: Self.inner),
        ])
        contentView = stack
        refresh()
    }

    /// The window is kept between openings, and the macOS shortcuts, the saved key and whether the
    /// updater can check change meanwhile, so what it says is read again each time it comes forward.
    override func becomeKey() {
        super.becomeKey()
        refresh()
    }

    /// ⌘-Tab or closing the window ends a recording, so the shortcut never stays released.
    override func resignKey() {
        super.resignKey()
        shortcutField.cancelRecording()
    }

    private func refresh() {
        shortcutField.shortcut = hotKey.shortcut
        defaultButton.isEnabled = hotKey.shortcut != .standard
        shortcutNote.stringValue = Self.shortcutCaption(shortcut: hotKey.shortcut, problem: hotKey.problem,
                                                        usedByMacOS: hotKey.shortcut.isUsedByMacOS(),
                                                        rejected: rejected)
        status.stringValue = keys.apiKey == nil
            ? "No key saved. Ideator works without one; collapsed cards show “Summary unavailable”."
            : keys.inKeychain
            ? "A key is saved in your Keychain. Paste a new one to replace it."
            : "A key is held for this run only. Paste a new one to replace it."
        autoCheck.state = updates.checksAutomatically ? .on : .off
        autoCheck.isEnabled = updates.plan.checks
        checkNowButton.isEnabled = updates.canCheck
        contentView?.layoutSubtreeIfNeeded()
        let top = frame.maxY
        setContentSize(NSSize(width: Self.width, height: stack.fittingSize.height))
        setFrameTopLeftPoint(NSPoint(x: frame.minX, y: top))
    }

    static func shortcutCaption(shortcut: Shortcut, problem: HotKey.Problem?, usedByMacOS: Bool,
                                rejected: String?) -> String {
        if let rejected { return rejected }
        if let problem { return problem.text(for: shortcut) + " There is no shortcut until you pick another." }
        if usedByMacOS {
            return "macOS also has a shortcut on \(shortcut.display) (System Settings › Keyboard › Keyboard "
                + "Shortcuts). If it fires instead of Ideator, pick another here."
        }
        return "Hides or shows every card, from any app. Click it, then press the new keys."
    }

    static func updatesCaption(build: BuildInfo, plan: UpdatePlan) -> String {
        switch plan {
        case .check: "\(build.versionLine). Ideator asks before it installs an update."
        case .off(.scratchRun): "\(build.versionLine). A scratch run (-CardsFolder) doesn't check for updates."
        case .off(.notPackaged): "\(build.versionLine). Only builds made by scripts/package.sh check for updates."
        }
    }

    @objc private func toggleAutomaticChecks() {
        updates.checksAutomatically = autoCheck.state == .on
        refresh()
    }

    @objc private func checkNow() {
        updates.checkNow()
        refresh()
    }

    @objc private func useDefaultShortcut() {
        pick(.standard)
        refresh()
    }

    private func pick(_ shortcut: Shortcut) {
        let problem = hotKey.choose(shortcut)
        rejected = problem.map { "\($0.text(for: shortcut)) Still using \(hotKey.shortcut.display)." }
    }

    @objc private func save() {
        guard !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if keys.set(field.stringValue) {
            field.stringValue = ""
            onChange()
        } else {
            NSSound.beep()
        }
        refresh()
    }

    @objc private func remove() {
        if keys.set(nil) { onChange() } else { NSSound.beep() }
        refresh()
    }
}

/// While it records, the live hotkey is released (`onRecordingChange(true)`), so pressing the
/// current combination reaches the recorder instead of hiding every card. A local monitor sees
/// every key first, so ⌘, ⌘Q and Return never reach the menu or the default button.
final class ShortcutField: NSButton {
    private static let prompt = "Type shortcut…"

    var shortcut: Shortcut = .standard { didSet { if monitor == nil { title = shortcut.display } } }
    var onPick: (Shortcut) -> Void = { _ in }
    var onReject: (String) -> Void = { _ in }
    var onRecordingChange: (Bool) -> Void = { _ in }
    private var monitor: Any?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        title = shortcut.display
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func beginRecording() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDown:
                finish(nil)
                return event
            case .flagsChanged:
                let held = Shortcut.describe(event)
                title = held.isEmpty ? Self.prompt : held + "…"
                return event
            default:
                let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
                if bare, event.charactersIgnoringModifiers == "\u{1B}" {
                    finish(nil)
                } else if let picked = Shortcut(event: event) {
                    finish(picked)
                } else if !event.isARepeat {
                    onReject(Shortcut.refusal(of: event))
                }
                return nil
            }
        }
        title = Self.prompt
        onRecordingChange(true)
    }

    func cancelRecording() {
        if monitor != nil { finish(nil) }
    }

    /// `onPick` runs while the old shortcut is still released, so `choose` claims the new one
    /// before `onRecordingChange(false)` would retake the old.
    private func finish(_ picked: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        title = shortcut.display
        if let picked { onPick(picked) }
        onRecordingChange(false)
    }
}
