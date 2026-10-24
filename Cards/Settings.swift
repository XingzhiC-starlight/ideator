import AppKit
import Security

/// The Anthropic API key. Lives in the login Keychain (generic password, service "Ideator",
/// account "anthropic-api-key"): never in code, in the card folder, or in user defaults.
/// Read once at launch and cached; `set` is the only writer.
final class KeyStore {
    private static let service = "Ideator"
    private static let account = "anthropic-api-key"

    /// nil = no key: the app works fully, it just never requests summaries.
    private(set) var apiKey: String?

    init() {
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

/// "Settings…": the global shortcut, then the API key with a plain statement of what summaries
/// send. Calls `onChange` after the key store changes so the controller can start (or stop)
/// summaries. The shortcut needs no callback: `HotKey` is its one owner and the window only
/// reads it. The window is as tall as its rows need (the captions wrap and change), never a
/// fixed height.
final class SettingsWindow: NSWindow {
    private static let width: CGFloat = 440
    private static let inner: CGFloat = 400

    /// What Settings says under the key field, and what PRIVACY.md says in full.
    static let privacy = "Summaries are optional. With a key saved, Ideator sends a card's text to Anthropic, "
        + "using your own key, to write its summary. Nothing else leaves your Mac: no analytics, no crash "
        + "reports. The key stays in your login Keychain."

    private let keys: KeyStore
    private let hotKey: HotKey
    private let onChange: () -> Void
    private let shortcutField = ShortcutField()
    private let defaultButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let shortcutNote = NSTextField(wrappingLabelWithString: "")
    private let field = NSSecureTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    /// The verdict on the last pick ("… Still using ⌃⌥Space."), shown until the next one.
    private var rejected: String?

    init(keys: KeyStore, hotKey: HotKey, onChange: @escaping () -> Void) {
        self.keys = keys
        self.hotKey = hotKey
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

        shortcutField.onPick = { [unowned self] picked in
            let problem = hotKey.choose(picked)
            rejected = problem.map { "\($0.text(for: picked)) Still using \(hotKey.shortcut.display)." }
        }
        shortcutField.onReject = { [unowned self] refusal in
            rejected = refusal
            refresh()
        }
        shortcutField.onRecordingChange = { [unowned self] recording in
            // Released while recording, so the live combination reaches the field; retaken after,
            // unless `choose` already registered the new one.
            if recording { hotKey.unregister(); rejected = nil } else { hotKey.register() }
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

        for view in [heading("Shortcut"), shortcutRow, caption(shortcutNote), heading("Anthropic API key"), field,
                     caption(NSTextField(wrappingLabelWithString: Self.privacy)), caption(status), buttons] {
            stack.addArrangedSubview(view)
        }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: shortcutNote)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: Self.width),
            field.widthAnchor.constraint(equalToConstant: Self.inner),
            buttons.trailingAnchor.constraint(equalTo: field.trailingAnchor),
        ])
        contentView = stack
        refresh()
    }

    /// A recording left open (⌘-Tab, closing the window) ends here, so the hotkey never stays
    /// released.
    override func resignKey() {
        super.resignKey()
        shortcutField.cancelRecording()
    }

    /// Everything the window shows, derived from `HotKey` and the key store. Runs after each change.
    private func refresh() {
        shortcutField.shortcut = hotKey.shortcut
        defaultButton.isEnabled = hotKey.shortcut != .standard
        shortcutNote.stringValue = Self.shortcutCaption(shortcut: hotKey.shortcut, problem: hotKey.problem,
                                                        usedByMacOS: hotKey.shortcut.isUsedByMacOS(),
                                                        rejected: rejected)
        status.stringValue = keys.apiKey == nil
            ? "No key saved. Ideator works without one; collapsed cards show “Summary unavailable”."
            : "A key is saved in your Keychain. Paste a new one to replace it."
        contentView?.layoutSubtreeIfNeeded()
        let top = frame.maxY
        setContentSize(NSSize(width: Self.width, height: stack.fittingSize.height))
        setFrameTopLeftPoint(NSPoint(x: frame.minX, y: top))
    }

    /// The line under the shortcut, first match wins. Pure, so the wording is tested without a window.
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

    @objc private func useDefaultShortcut() {
        let problem = hotKey.choose(.standard)
        rejected = problem.map { "\($0.text(for: .standard)) Still using \(hotKey.shortcut.display)." }
        refresh()
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
        keys.set(nil)
        onChange()
        refresh()
    }
}

/// The Settings row's control: a button that shows the shortcut and, once clicked, records a new
/// one. While it records, the live hotkey is released (`onRecordingChange(true)`), so pressing the
/// current combination reaches the recorder instead of hiding every card. A local monitor sees
/// every key first, so ⌘, ⌘Q and Return never reach the menu or the default button; it also sees
/// the modifiers held, and any click, which ends the recording.
final class ShortcutField: NSButton {
    private static let prompt = "Type shortcut…"

    var shortcut: Shortcut = .standard { didSet { if monitor == nil { title = shortcut.display } } }
    /// A legal combination was pressed. The window asks `HotKey.choose` and shows the verdict.
    var onPick: (Shortcut) -> Void = { _ in }
    /// An illegal one was pressed, with the sentence that says so. The field keeps recording.
    var onReject: (String) -> Void = { _ in }
    /// Recording began (true) or ended for any reason (false).
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
        title = Self.prompt
        onRecordingChange(true)
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
                return nil   // swallowed
            }
        }
    }

    /// Esc, a click, the window losing key status: the same as pressing nothing. Idempotent.
    func cancelRecording() {
        if monitor != nil { finish(nil) }
    }

    /// Order matters: end the monitor, then `onPick` (the hotkey is still released, so `choose`
    /// claims the new combination first), then `onRecordingChange(false)` (`register()` retakes
    /// the old one only if `choose` did not).
    private func finish(_ picked: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        title = shortcut.display
        if let picked { onPick(picked) }
        onRecordingChange(false)
    }
}
