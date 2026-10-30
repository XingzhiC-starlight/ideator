import AppKit

/// One section's page (§3.13).
///
/// A pane is the only view that reads or writes its model, and the only holder of its passing state
/// (a refused combination, a refused Keychain write, which setup was copied). `refresh()` sets every
/// control from those two and nothing else, so it can run any number of times. A click writes the
/// model, then calls `refreshAll`, because one change can show on two panes (Save moves the Privacy
/// card's company). A keystroke calls the pane's own `refresh()`: no other pane shows what is typed.
class SettingsPane: NSView {
    /// What a group holds, top to bottom. The kinds decide the gaps between them (§2.3).
    enum Item {
        case label(NSView), control(NSView), caption(NSView)
    }

    let section: SettingsSection
    let refreshAll: () -> Void
    let announce: (String) -> Void
    private let column = NSStackView()

    init(section: SettingsSection, refreshAll: @escaping () -> Void, announce: @escaping (String) -> Void) {
        self.section = section
        self.refreshAll = refreshAll
        self.announce = announce
        super.init(frame: .zero)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = SettingsStyle.s5
        column.edgeInsets = NSEdgeInsets(top: SettingsStyle.contentTop, left: SettingsStyle.s6,
                                         bottom: SettingsStyle.s6, right: SettingsStyle.s6)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        let title = SettingsControl.text(section.title, as: .title)
        column.addArrangedSubview(title)
        if let lead = section.lead {
            column.addArrangedSubview(SettingsControl.text(lead, as: .lead))
            column.setCustomSpacing(SettingsStyle.s2, after: title)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(section.title)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func refresh() {}

    func windowDidResignKey() {}

    final func statusLine(resting: String? = nil) -> StatusLine { StatusLine(resting: resting, announce: announce) }

    final func addGroup(_ items: [Item]) {
        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        var previous: Item?
        for item in items {
            let view: NSView
            switch item {
            case .label(let v), .control(let v), .caption(let v): view = v
            }
            if let previous, let last = group.arrangedSubviews.last {
                group.setCustomSpacing(Self.gap(previous, item), after: last)
            }
            group.addArrangedSubview(view)
            previous = item
        }
        column.addArrangedSubview(group)
    }

    private static func gap(_ previous: Item, _ next: Item) -> CGFloat {
        switch (previous, next) {
        case (.label, .caption): SettingsStyle.s1
        case (.control, .control): SettingsStyle.s3
        default: SettingsStyle.s2
        }
    }
}

final class ShortcutPane: SettingsPane {
    private let hotKey: HotKey
    private let recorder = ShortcutField()
    private lazy var useDefault = SettingsControl.button(SettingsCopy.Shortcut.useDefault, target: self,
                                                         action: #selector(useDefaultShortcut))
    private lazy var status = statusLine()
    private var refusal: String?
    private var releasedForRecording = false

    init(hotKey: HotKey, refreshAll: @escaping () -> Void, announce: @escaping (String) -> Void) {
        self.hotKey = hotKey
        super.init(section: .shortcut, refreshAll: refreshAll, announce: announce)
        recorder.onReject = { [unowned self] refused in
            refusal = refused
            refresh()
        }
        recorder.onRecordingStart = { [unowned self] in
            releasedForRecording = hotKey.unregister()
            refusal = nil
            announce(SettingsCopy.Shortcut.recording)
            refresh()
        }
        recorder.onRecordingEnd = { [unowned self] picked in
            if let picked { pick(picked) }
            if releasedForRecording {
                releasedForRecording = false
                hotKey.register()
            }
            refresh()
        }
        addGroup([.control(SettingsControl.row([recorder, useDefault])),
                  .caption(SettingsControl.text(SettingsCopy.Shortcut.caption, as: .caption)),
                  .caption(status)])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        recorder.shortcut = hotKey.shortcut
        useDefault.isEnabled = hotKey.shortcut != .standard
        status.show(SettingsCopy.Shortcut.status(shortcut: hotKey.shortcut, problem: hotKey.problem,
                                                 usedByMacOS: hotKey.shortcut.isUsedByMacOS(), refusal: refusal))
    }

    override func windowDidResignKey() { recorder.cancelRecording() }

    @objc private func useDefaultShortcut() {
        pick(.standard)
        refreshAll()
    }

    private func pick(_ shortcut: Shortcut) {
        refusal = hotKey.choose(shortcut).map { SettingsCopy.Shortcut.rejection($0, wanted: shortcut, kept: hotKey.shortcut) }
    }
}

final class SpreadPane: SettingsPane {
    private let spread: SpreadChoice
    private let stackCell: () -> Slot
    private let picker = SpreadCellPicker()
    private lazy var status = statusLine()

    init(spread: SpreadChoice, stackCell: @escaping () -> Slot, refreshAll: @escaping () -> Void,
         announce: @escaping (String) -> Void) {
        self.spread = spread
        self.stackCell = stackCell
        super.init(section: .spread, refreshAll: refreshAll, announce: announce)
        picker.onToggle = { [unowned self] slot in
            self.spread.cells = self.spread.cells.toggling(slot)
            self.refreshAll()
        }
        addGroup([.control(picker), .caption(SettingsControl.text(SettingsCopy.Spread.caption, as: .caption)), .caption(status)])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        picker.show(spread.cells, stackCell: stackCell())
        status.show(SettingsCopy.Spread.status(cells: spread.cells))
    }
}

final class AISummaryPane: SettingsPane, NSTextFieldDelegate {
    private let keys: KeyStore
    private let keyChanged: () -> Void
    private let field = SettingsControl.secureField(placeholder: SettingsCopy.AISummary.placeholder)
    private lazy var status = statusLine()
    private lazy var remove = SettingsControl.button(SettingsCopy.AISummary.remove, target: self, action: #selector(removeKey))
    private lazy var save = SettingsControl.primaryButton(SettingsCopy.AISummary.save, target: self, action: #selector(saveKey))
    private var keychainRefused = false

    init(keys: KeyStore, keyChanged: @escaping () -> Void, refreshAll: @escaping () -> Void,
         announce: @escaping (String) -> Void) {
        self.keys = keys
        self.keyChanged = keyChanged
        super.init(section: .aiSummary, refreshAll: refreshAll, announce: announce)
        field.target = self
        field.action = #selector(saveKey)
        field.delegate = self
        addGroup([.label(SettingsControl.text(SettingsCopy.AISummary.label, as: .label)), .control(field),
                  .caption(status), .control(SettingsControl.row([remove, save], .trailing))])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        save.isEnabled = !typedKey.isEmpty
        remove.isEnabled = keys.provider != nil
        status.show(SettingsCopy.AISummary.status(provider: keys.provider, inKeychain: keys.inKeychain,
                                                  keychainRefused: keychainRefused))
    }

    func controlTextDidChange(_ notification: Notification) { refresh() }

    private var typedKey: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    @objc private func saveKey() {
        guard !typedKey.isEmpty else { return }
        let saved = keys.set(field.stringValue)
        if saved { field.stringValue = "" }
        finish(saved)
    }

    @objc private func removeKey() { finish(keys.set(nil)) }

    private func finish(_ stored: Bool) {
        keychainRefused = !stored
        if stored { keyChanged() } else { NSSound.beep() }
        refreshAll()
    }
}

final class MCPPane: SettingsPane, NSTextViewDelegate {
    private let aiTools: AIToolsChoice
    private let connect: HelperCommand
    private let pasteboard: NSPasteboard
    private var connectButtons: [(tool: AITool, button: NSButton)] = []
    private lazy var connectStatus = statusLine(resting: SettingsCopy.MCP.connectCaption)
    private lazy var allow = SettingsControl.checkbox(SettingsCopy.MCP.allow, target: self, action: #selector(toggleAITools))
    private lazy var landing = SettingsControl.segments([SettingsCopy.MCP.top, SettingsCopy.MCP.bottom], target: self,
                                                        action: #selector(chooseLanding))
    private let editor = SettingsControl.editor()
    private lazy var instructionStatus = statusLine(resting: SettingsCopy.MCP.instructionCaption)
    private lazy var reset = SettingsControl.button(SettingsCopy.MCP.reset, target: self, action: #selector(resetInstruction))
    private var copied: AITool?
    private var instructionRefused = false

    init(aiTools: AIToolsChoice, connect: HelperCommand, pasteboard: NSPasteboard, refreshAll: @escaping () -> Void,
         announce: @escaping (String) -> Void) {
        self.aiTools = aiTools
        self.connect = connect
        self.pasteboard = pasteboard
        super.init(section: .mcp, refreshAll: refreshAll, announce: announce)
        connectButtons = AITool.allCases.map { tool in
            let button = SettingsControl.button(tool.name, symbol: "doc.on.doc", widestOf: [tool.name, SettingsCopy.MCP.copied],
                                                target: self, action: #selector(copySetup))
            button.setAccessibilityLabel(SettingsCopy.MCP.copyLabel(for: tool))
            return (tool, button)
        }
        editor.textView.delegate = self
        editor.textView.setAccessibilityLabel(SettingsCopy.MCP.instructionLabel)
        addGroup([.label(SettingsControl.text(SettingsCopy.MCP.connectLabel, as: .label)),
                  .control(SettingsControl.row(connectButtons.map(\.button))), .caption(connectStatus)])
        addGroup([.control(allow),
                  .control(SettingsControl.row([SettingsControl.text(SettingsCopy.MCP.landingLabel, as: .label), landing.row]))])
        addGroup([.label(SettingsControl.text(SettingsCopy.MCP.instructionLabel, as: .label)), .caption(instructionStatus),
                  .control(editor.scroll), .control(reset)])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        for (tool, button) in connectButtons {
            button.title = copied == tool ? SettingsCopy.MCP.copied : tool.name
            button.image = NSImage(systemSymbolName: copied == tool ? "checkmark" : "doc.on.doc", accessibilityDescription: nil)
            button.isEnabled = !connect.isTemporary
        }
        connectStatus.show(SettingsCopy.MCP.connectStatus(isTemporary: connect.isTemporary, copied: copied))
        let settings = aiTools.value
        allow.state = settings.enabled ? .on : .off
        for (radio, place) in zip(landing.buttons, [Landing.top, .bottom]) {
            radio.state = settings.landing == place ? .on : .off
            radio.isEnabled = settings.enabled
        }
        if editor.textView.string != settings.instruction.text { editor.textView.string = settings.instruction.text }
        reset.isEnabled = !settings.instruction.isStandard
        instructionStatus.show(SettingsCopy.MCP.instructionStatus(refused: instructionRefused))
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

    @objc private func toggleAITools() {
        aiTools.value.enabled = allow.state == .on
        refreshAll()
    }

    @objc private func chooseLanding(_ sender: NSButton) {
        aiTools.value.landing = sender === landing.buttons.last ? .bottom : .top
        refreshAll()
    }

    /// Replaces the text through the editor, so Undo brings the edit back.
    @objc private func resetInstruction() {
        let textView = editor.textView
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        guard textView.shouldChangeText(in: all, replacementString: Instruction.standard) else { return }
        textView.replaceCharacters(in: all, with: Instruction.standard)
        textView.didChangeText()
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard let replacement = replacementString else { return true }
        let removed = (textView.string as NSString).substring(with: range).utf8.count
        guard textView.string.utf8.count - removed + replacement.utf8.count > Instruction.byteLimit else { return true }
        instructionRefused = true
        refresh()
        return false
    }

    func textDidChange(_ notification: Notification) {
        aiTools.value.instruction.edit(to: editor.textView.string)
        instructionRefused = false
        refresh()
    }
}

final class UpdatesPane: SettingsPane {
    private let updates: Updates
    private lazy var autoCheck = SettingsControl.checkbox(SettingsCopy.Updates.autoCheck, target: self,
                                                          action: #selector(toggleAutomaticChecks))
    private lazy var checkNow = SettingsControl.button(SettingsCopy.Updates.checkNow, target: self, action: #selector(checkNowPressed))
    private lazy var runStatus = statusLine(resting: SettingsCopy.Updates.asksBeforeInstalling)

    init(updates: Updates, refreshAll: @escaping () -> Void, announce: @escaping (String) -> Void) {
        self.updates = updates
        super.init(section: .updates, refreshAll: refreshAll, announce: announce)
        let version = SettingsControl.text(updates.build.versionLine, as: .mono)
        version.isSelectable = true
        addGroup([.control(SettingsControl.row([autoCheck, checkNow], .apart)), .caption(version), .caption(runStatus)])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() {
        autoCheck.state = updates.checksAutomatically ? .on : .off
        autoCheck.isEnabled = updates.plan.checks
        checkNow.isEnabled = updates.canCheck
        runStatus.show(SettingsCopy.Updates.status(plan: updates.plan))
    }

    @objc private func toggleAutomaticChecks() {
        updates.checksAutomatically = autoCheck.state == .on
        refreshAll()
    }

    @objc private func checkNowPressed() {
        updates.checkNow()
        refreshAll()
    }
}

final class PrivacyPane: SettingsPane {
    private let keys: KeyStore
    private let card = PrivacyCardView()

    init(keys: KeyStore, refreshAll: @escaping () -> Void, announce: @escaping (String) -> Void) {
        self.keys = keys
        super.init(section: .privacy, refreshAll: refreshAll, announce: announce)
        addGroup([.control(card)])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func refresh() { card.show(SettingsCopy.Privacy.card(for: keys.provider)) }
}
