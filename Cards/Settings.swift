import AppKit
import Security

/// The API key, an Anthropic key or an OpenAI key. Lives in the login Keychain (generic password,
/// service "Ideator", account "api-key"): never in code, in the card folder, or in user defaults.
/// One item holds the last key pasted; the "anthropic-api-key" item that earlier builds wrote is
/// not read. Read once at launch and cached; `set` is the only writer.
///
/// A scratch run gets `inKeychain: false`: the key lives in memory for that run only, starts empty,
/// and no Keychain call is ever made, so a verify run can't trigger macOS's access prompt for the
/// owner's key or touch it.
class KeyStore {
    private static let service = "Ideator"
    private static let account = "api-key"

    /// nil = no key: the app works fully, it just never requests summaries.
    private(set) var apiKey: String?

    var provider: Provider? { apiKey.map { Provider(key: $0) } }

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

final class SettingsWindow: NSWindow, NSTextViewDelegate {
    private static let width: CGFloat = 440
    private static let inner: CGFloat = 400
    private static let editorHeight: CGFloat = 112

    private static let connectCaption = "Each button copies a tool's setup, for you to paste. Ideator never edits another app's config files."
    private static let limitName = "\(Instruction.byteLimit / 1_000) KB"
    private static let instructionCaption = "Ideator gives an AI tool this text when a session starts, so an edit reaches it at its next "
        + "session. It holds up to \(limitName)."
    private static let connectMoveFirst = "Ideator is running from a disk image, another volume or a quarantined download, so a "
        + "setup copied now would point at a path that goes away. Move Ideator to Applications, open it from there, then copy a setup."
    private static let instructionRefusal = "That change would pass the \(limitName) limit, so Ideator did not make it."

    /// Names the company of the saved key, or both while no key is saved.
    static func privacy(for provider: Provider?) -> String {
        let recipient = provider?.name ?? "Anthropic or OpenAI, whichever your key is for"
        return "With a key saved, Ideator sends a card's text to \(recipient), using your own key, to "
            + "write its summary, whenever the card has no summary for its text as it is now. It does so, for "
            + "example, after you change a card, when you save a key, at launch after a failed try, and after an "
            + "update that changes how Ideator asks for summaries. The key stays in your login Keychain. Once a "
            + "day, and whenever you click Check Now, Ideator asks GitHub whether a newer version exists. GitHub "
            + "sees your IP address and which version you have. Nothing else leaves your Mac: no analytics, no "
            + "crash reports."
    }

    static func keyStatus(provider: Provider?, inKeychain: Bool) -> String {
        guard let provider else {
            return "No key saved. Ideator works without one; collapsed cards show “Summary unavailable”."
        }
        let place = inKeychain ? "is saved in your Keychain" : "is held for this run only"
        return "An \(provider.name) key \(place). Paste a new one to replace it."
    }

    private let keys: KeyStore
    private let hotKey: HotKey
    private let updates: Updates
    private let onChange: () -> Void
    private let shortcutField = ShortcutField()
    private let defaultButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let shortcutNote = NSTextField(wrappingLabelWithString: "")
    private let field = NSSecureTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let privacyNote = NSTextField(wrappingLabelWithString: "")
    private let autoCheck = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
    private let checkNowButton = NSButton(title: "Check Now", target: nil, action: nil)
    private let aiTools: AIToolsChoice
    private let allowAITools = NSButton(checkboxWithTitle: "Let AI tools add cards", target: nil, action: nil)
    private let landsOnTop = NSButton(radioButtonWithTitle: "Top", target: nil, action: nil)
    private let landsAtBottom = NSButton(radioButtonWithTitle: "Bottom", target: nil, action: nil)
    private let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: SettingsWindow.inner, height: SettingsWindow.editorHeight))
    private let instructionNote = NSTextField(wrappingLabelWithString: "")
    private let resetInstruction = NSButton(title: "Reset to Default", target: nil, action: nil)
    private let connectNote = NSTextField(wrappingLabelWithString: "")
    private let connect: HelperCommand
    private let pasteboard: NSPasteboard
    private var connectButtons: [(tool: AITool, button: NSButton)] = []
    private var copied: AITool?
    private let stack = NSStackView()
    private let document = FlippedView()
    private let maxContentHeight: CGFloat?
    private var rejected: String?
    private var instructionRefused = false
    private var releasedForRecording = false

    /// The window is as tall as its rows, and scrolls where the screen has less room. `maxContentHeight`
    /// replaces the screen's room, for a test.
    init(keys: KeyStore, hotKey: HotKey, updates: Updates,
         aiTools: AIToolsChoice = AIToolsChoice(preferences: Preferences(defaults: nil)),
         connect: HelperCommand = HelperCommand(app: Bundle.main.bundleURL, scratchFolder: nil),
         pasteboard: NSPasteboard = .general, maxContentHeight: CGFloat? = nil, onChange: @escaping () -> Void) {
        self.keys = keys
        self.hotKey = hotKey
        self.updates = updates
        self.aiTools = aiTools
        self.connect = connect
        self.pasteboard = pasteboard
        self.maxContentHeight = maxContentHeight
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

        field.placeholderString = "sk-ant-… or sk-…"
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

        allowAITools.target = self
        allowAITools.action = #selector(toggleAITools)
        for radio in [landsOnTop, landsAtBottom] {
            radio.target = self
            radio.action = #selector(chooseLanding)
        }
        let landingRow = NSStackView(views: [NSTextField(labelWithString: "Cards from AI tools go to:"), landsOnTop, landsAtBottom])
        landingRow.spacing = 8

        let editorScroll = NSScrollView()
        editorScroll.borderType = .bezelBorder
        editorScroll.hasVerticalScroller = true
        editorScroll.drawsBackground = false
        editorScroll.documentView = editor
        editor.minSize = NSSize(width: 0, height: Self.editorHeight)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = .width
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 2, height: 4)
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.delegate = self
        editor.setAccessibilityLabel("Instruction for AI tools")
        resetInstruction.target = self
        resetInstruction.action = #selector(resetInstructionText)

        let connectRow = NSStackView()
        connectRow.spacing = 8
        for tool in AITool.allCases {
            let copy = NSButton(title: tool.name, image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) ?? NSImage(),
                                target: self, action: #selector(copySetup))
            copy.imagePosition = .imageLeading
            copy.setAccessibilityLabel("Copy setup for \(tool.name)")
            connectButtons.append((tool, copy))
            connectRow.addArrangedSubview(copy)
        }

        for view in [heading("Shortcut"), shortcutRow, caption(shortcutNote), heading("API key (Anthropic or OpenAI)"), field,
                     caption(status), buttons, heading("Updates"), updatesRow, caption(updatesNote),
                     heading("AI tools"), allowAITools, landingRow,
                     NSTextField(labelWithString: "Instruction for AI tools"),
                     caption(instructionNote), editorScroll, resetInstruction,
                     heading("Connect AI tools"), caption(connectNote), connectRow,
                     heading("Privacy"), caption(privacyNote)] {
            stack.addArrangedSubview(view)
        }
        stack.setCustomSpacing(18, after: landingRow)
        stack.setCustomSpacing(18, after: resetInstruction)
        stack.setCustomSpacing(18, after: connectRow)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: shortcutNote)
        stack.setCustomSpacing(18, after: buttons)
        stack.setCustomSpacing(18, after: updatesNote)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.width),
            field.widthAnchor.constraint(equalToConstant: Self.inner),
            buttons.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            updatesRow.widthAnchor.constraint(equalToConstant: Self.inner),
            editorScroll.widthAnchor.constraint(equalToConstant: Self.inner),
            editorScroll.heightAnchor.constraint(equalToConstant: Self.editorHeight),
        ])
        let scroll = NSScrollView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        contentView = scroll
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
        status.stringValue = Self.keyStatus(provider: keys.provider, inKeychain: keys.inKeychain)
        privacyNote.stringValue = Self.privacy(for: keys.provider)
        autoCheck.state = updates.checksAutomatically ? .on : .off
        autoCheck.isEnabled = updates.plan.checks
        checkNowButton.isEnabled = updates.canCheck
        allowAITools.state = aiTools.value.enabled ? .on : .off
        landsOnTop.state = aiTools.value.landing == .top ? .on : .off
        landsAtBottom.state = aiTools.value.landing == .bottom ? .on : .off
        landsOnTop.isEnabled = aiTools.value.enabled
        landsAtBottom.isEnabled = aiTools.value.enabled
        if editor.string != aiTools.value.instruction.text { editor.string = aiTools.value.instruction.text }
        resetInstruction.isEnabled = !aiTools.value.instruction.isStandard
        instructionNote.stringValue = instructionRefused ? Self.instructionRefusal : Self.instructionCaption
        for (tool, button) in connectButtons {
            button.title = copied == tool ? "Copied" : tool.name
            button.isEnabled = !connect.isTemporary
        }
        connectNote.stringValue = connect.isTemporary ? Self.connectMoveFirst
            : copied.map { "Copied for \($0.name). \($0.pasteNote)" } ?? Self.connectCaption
        stack.layoutSubtreeIfNeeded()
        let rows = stack.fittingSize.height
        document.setFrameSize(NSSize(width: Self.width, height: rows))
        let top = frame.maxY
        setContentSize(NSSize(width: Self.width, height: min(rows, roomForContent)))
        setFrameTopLeftPoint(NSPoint(x: frame.minX, y: top))
    }

    /// What the screen the window is on has left below its title bar, with a margin.
    private var roomForContent: CGFloat {
        if let maxContentHeight { return maxContentHeight }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return .greatestFiniteMagnitude }
        return visible.height - (frame.height - contentRect(forFrameRect: frame).height) - 24
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

    @objc private func toggleAITools() {
        aiTools.value.enabled = allowAITools.state == .on
        refresh()
    }

    @objc private func chooseLanding(_ sender: NSButton) {
        aiTools.value.landing = sender === landsAtBottom ? .bottom : .top
        refresh()
    }

    /// A change that would pass the instruction's limit is not made, and the note above the box says so.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard textView === editor, let replacement = replacementString else { return true }
        let removed = (editor.string as NSString).substring(with: range).utf8.count
        guard editor.string.utf8.count - removed + replacement.utf8.count > Instruction.byteLimit else { return true }
        instructionRefused = true
        instructionNote.stringValue = Self.instructionRefusal
        return false
    }

    func textDidChange(_ notification: Notification) {
        aiTools.value.instruction.edit(to: editor.string)
        resetInstruction.isEnabled = !aiTools.value.instruction.isStandard
        instructionRefused = false
        instructionNote.stringValue = Self.instructionCaption
    }

    /// Replaces the text through the editor, so Undo brings the edit back.
    @objc private func resetInstructionText() {
        let all = NSRange(location: 0, length: (editor.string as NSString).length)
        guard editor.shouldChangeText(in: all, replacementString: Instruction.standard) else { return }
        editor.replaceCharacters(in: all, with: Instruction.standard)
        editor.didChangeText()
    }

    @objc private func copySetup(_ sender: NSButton) {
        guard let tool = connectButtons.first(where: { $0.button === sender })?.tool else { return }
        pasteboard.clearContents()
        pasteboard.setString(tool.setup(for: connect), forType: .string)
        copied = tool
        refresh()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, copied == tool else { return }
            copied = nil
            refresh()
        }
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

/// A view whose origin is its top left, so a scroll view opens on its first row.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
