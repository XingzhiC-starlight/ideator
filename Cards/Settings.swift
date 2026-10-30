import AppKit

/// Settings: a sidebar of the six sections and one pane per section, 640 × 640 and not resizable.
/// The window holds no control and no model of its own. It picks which pane shows, keeps the panes
/// fresh and owns the window's lifecycle; each pane owns its controls (SettingsPanes.swift).
///
/// - Every pane stays in the view tree for the window's life and only the selected one is unhidden,
///   so the accessibility tree and the key view loop see one pane while tests can reach every control.
/// - It opens on Shortcut every time: `close()` goes back to it. `becomeKey` fires on every app
///   switch, so it never touches the selection, and the chosen section stays while the window is open.
/// - `refresh()` refreshes every pane, shown or not: `Updates` has no change callback.
final class SettingsWindow: NSWindow {
    private let sidebar = SettingsSidebar()
    private let host = PaneHost()
    private var panes: [SettingsPane] = []
    private let maxContentHeight: CGFloat?
    private(set) var selected = SettingsSection.opening

    /// `maxContentHeight` replaces the screen's room, for a test. `announce` replaces the VoiceOver
    /// announcement, for a test.
    init(keys: KeyStore, hotKey: HotKey, updates: Updates,
         aiTools: AIToolsChoice = AIToolsChoice(preferences: Preferences(defaults: nil)),
         connect: HelperCommand = HelperCommand(app: Bundle.main.bundleURL, scratchFolder: nil),
         spread: SpreadChoice = SpreadChoice(preferences: Preferences(defaults: nil)),
         stackCell: @escaping () -> Slot = { Slot.stackHome },
         pasteboard: NSPasteboard = .general, maxContentHeight: CGFloat? = nil,
         announce: ((String) -> Void)? = nil, onChange: @escaping () -> Void) {
        self.maxContentHeight = maxContentHeight
        super.init(contentRect: NSRect(origin: .zero, size: SettingsStyle.windowSize),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        title = SettingsCopy.windowTitle
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false

        let speak = announce ?? { [unowned self] text in
            NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
                .announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
        let refreshAll = { [unowned self] in refresh() }
        panes = SettingsSection.allCases.map { section in
            switch section {
            case .shortcut: ShortcutPane(hotKey: hotKey, refreshAll: refreshAll, announce: speak)
            case .spread: SpreadPane(spread: spread, stackCell: stackCell, refreshAll: refreshAll, announce: speak)
            case .aiSummary: AISummaryPane(keys: keys, keyChanged: onChange, refreshAll: refreshAll, announce: speak)
            case .mcp: MCPPane(aiTools: aiTools, connect: connect, pasteboard: pasteboard, refreshAll: refreshAll, announce: speak)
            case .updates: UpdatesPane(updates: updates, refreshAll: refreshAll, announce: speak)
            case .privacy: PrivacyPane(keys: keys, refreshAll: refreshAll, announce: speak)
            }
        }
        host.install(panes)
        sidebar.onSelect = { [unowned self] section in select(section) }

        let content = NSView(frame: NSRect(origin: .zero, size: SettingsStyle.windowSize))
        for view in [sidebar, host] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SettingsStyle.sidebarWidth),
            host.topAnchor.constraint(equalTo: content.topAnchor),
            host.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        contentView = content
        initialFirstResponder = sidebar.table
        select(.opening)
        refresh()
        fitScreen()
        makeFirstResponder(sidebar.table)
    }

    /// Shows `section`'s pane from its top, selects its row and links Tab through it. Focus stays where
    /// it is (A3): an arrow key in the sidebar changes the pane and leaves the sidebar focused.
    func select(_ section: SettingsSection) {
        selected = section
        sidebar.select(section)
        host.show(section)
        linkKeyViews()
    }

    /// The pane for a section, shown or not.
    func pane(_ section: SettingsSection) -> SettingsPane { panes[section.rawValue] }

    /// Every pane reads its model again. Idempotent.
    func refresh() {
        for pane in panes { pane.refresh() }
    }

    /// The window is kept between openings, and the macOS shortcuts, the saved key and whether the
    /// updater can check change meanwhile, so what it says is read again each time it comes forward.
    override func becomeKey() {
        super.becomeKey()
        fitScreen()
        refresh()
    }

    /// ⌘-Tab or closing the window ends a recording, so the shortcut never stays released.
    override func resignKey() {
        super.resignKey()
        for pane in panes { pane.windowDidResignKey() }
    }

    override func close() {
        super.close()
        select(.opening)
        makeFirstResponder(sidebar.table)
    }

    /// The main menu has no Close item, so ⌘W is this window's alone and never reaches a card. While
    /// the recorder records, its monitor takes ⌘W first and refuses it as a shortcut.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Tab goes from the sidebar through the shown pane's controls in reading order, then back. AppKit's
    /// own loop is by position and would weave the sidebar in. Disabled and hidden controls stay in the
    /// chain and Tab skips them, so a control that becomes enabled needs no relink.
    private func linkKeyViews() {
        var previous: NSView = sidebar.table
        for view in Self.keyViews(in: pane(selected)) {
            previous.nextKeyView = view
            previous = view
        }
        previous.nextKeyView = sidebar.table
    }

    private static func keyViews(in view: NSView) -> [NSView] {
        view.subviews.flatMap { subview -> [NSView] in
            switch subview {
            case let button as NSButton: button.refusesFirstResponder ? [] : [button]
            case let field as NSTextField: field.isEditable ? [field] : []
            case let text as NSTextView: text.isEditable ? [text] : []
            case is SpreadCellPicker: [subview]
            default: keyViews(in: subview)
            }
        }
    }

    /// 640 tall, or what the screen has left below the title bar with a margin; the pane scrolls then.
    private func fitScreen() {
        let room: CGFloat
        if let maxContentHeight {
            room = maxContentHeight
        } else if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            room = visible.height - (frame.height - contentRect(forFrameRect: frame).height) - 24
        } else {
            room = SettingsStyle.windowSize.height
        }
        let size = NSSize(width: SettingsStyle.windowSize.width, height: min(SettingsStyle.windowSize.height, room))
        guard contentRect(forFrameRect: frame).size != size else { return }
        let top = frame.maxY
        setContentSize(size)
        setFrameTopLeftPoint(NSPoint(x: frame.minX, y: top))
    }
}

/// The six sections, one 32-point row each, from 52 down. ↑ and ↓ change the section at once.
///
/// Each row is an accessibility cell named exactly the section's title, with a press, so VoiceOver
/// says "Spread, 2 of 6" and the harness's `section Spread` can never hit the ribbon's Spread button
/// or "Spread cell 1", as matching by prefix would.
final class SettingsSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    var onSelect: (SettingsSection) -> Void = { _ in }
    private var selected: SettingsSection?

    init() {
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        column.width = SettingsStyle.sidebarWidth
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = SettingsStyle.sidebarRowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.allowsEmptySelection = false
        table.allowsTypeSelect = false
        table.setAccessibilityLabel(SettingsCopy.sections)
        table.dataSource = self
        table.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: SettingsStyle.contentTop),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: CGFloat(SettingsSection.allCases.count) * SettingsStyle.sidebarRowHeight),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The edge it shares with the pane. Drawn, not a view: a separator view has a height of its own,
    /// and the window would shrink to it.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }

    /// Selects the row without calling `onSelect`.
    func select(_ section: SettingsSection) {
        selected = section
        table.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { SettingsSection.allCases.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let section = SettingsSection(rawValue: row) else { return nil }
        let cell = SidebarCell(section)
        cell.onPress = { [unowned self] in table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let section = SettingsSection(rawValue: table.selectedRow), section != selected else { return }
        selected = section
        onSelect(section)
    }
}

/// A sidebar row's content. NSTableView wraps every cell in its own accessibility cell and forwards
/// this view's label and press to it, so the view must not be an element too (see `ArrangerCell`).
final class SidebarCell: NSTableCellView {
    private let section: SettingsSection
    var onPress: () -> Void = {}

    init(_ section: SettingsSection) {
        self.section = section
        super.init(frame: .zero)
        let name = SettingsControl.text(section.title, as: .label, width: SettingsStyle.sidebarWidth - 2 * SettingsStyle.s4)
        name.setAccessibilityElement(false)
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)
        textField = name
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsStyle.s4),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .cell }
    override func accessibilityLabel() -> String? { section.title }
    override func accessibilityChildren() -> [Any]? { [] }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}

/// The pane area: one scroll view whose document holds all six panes at the same origin, one unhidden.
/// The document is as tall as the shown pane or the window, whichever is taller, so a pane taller
/// than the window scrolls here and the sidebar never does.
final class PaneHost: NSScrollView {
    private let document = FlippedView()
    private var panes: [SettingsPane] = []
    private var fit: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        document.translatesAutoresizingMaskIntoConstraints = false
        documentView = document
        let snug = document.heightAnchor.constraint(equalTo: contentView.heightAnchor)
        snug.priority = .defaultLow
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: contentView.heightAnchor),
            snug,
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func install(_ panes: [SettingsPane]) {
        self.panes = panes
        for pane in panes {
            pane.translatesAutoresizingMaskIntoConstraints = false
            pane.isHidden = true
            document.addSubview(pane)
            NSLayoutConstraint.activate([
                pane.topAnchor.constraint(equalTo: document.topAnchor),
                pane.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            ])
        }
    }

    /// Idempotent.
    func show(_ section: SettingsSection) {
        for pane in panes { pane.isHidden = pane.section != section }
        fit?.isActive = false
        fit = document.bottomAnchor.constraint(greaterThanOrEqualTo: panes[section.rawValue].bottomAnchor)
        fit?.isActive = true
        layoutSubtreeIfNeeded()
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }
}

/// A view whose origin is its top left, so a scroll view opens on its first row.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
