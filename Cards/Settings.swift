import AppKit

/// Settings: a sidebar of the six sections and one pane per section.
/// The window holds no control and no model of its own. It picks which pane shows, keeps the panes
/// fresh and owns the window's lifecycle; each pane owns its controls (SettingsPanes.swift).
///
/// - Every pane stays in the view tree for the window's life and only the selected one is unhidden,
///   so the accessibility tree and the key view loop see one pane while tests can reach every control.
/// - It opens on Shortcut every time: `close()` goes back to it. `becomeKey` fires on every app
///   switch, so it never touches the selection, and the chosen section stays while the window is open.
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
        appearance = NSAppearance(named: .aqua)
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil)
    }

    /// Shows `section`'s pane from its top, selects its row and links Tab through it. Focus stays where
    /// it is (A3): an arrow key in the sidebar changes the pane and leaves the sidebar focused. A
    /// VoiceOver press on a row changes the section without moving focus, and when the pane that had it
    /// hides, AppKit gives focus to the window itself; it goes to the sidebar instead, so Tab carries on.
    func select(_ section: SettingsSection) {
        selected = section
        sidebar.select(section)
        host.show(section)
        linkKeyViews()
        let focused = firstResponder as? NSView
        if focused.map({ $0.isDescendant(of: sidebar) || $0.isDescendant(of: pane(section)) }) != true {
            makeFirstResponder(sidebar.table)
        }
    }

    func pane(_ section: SettingsSection) -> SettingsPane { panes[section.rawValue] }

    func refresh() {
        for pane in panes { pane.refresh() }
    }

    /// The window is kept between openings, and the macOS shortcuts, the saved key and whether the
    /// updater can check change meanwhile, so what it says is read again each time it comes forward.
    override func becomeKey() {
        super.becomeKey()
        fitScreen()
        refresh()
        if let owner = SettingsFocusRing.owner(of: firstResponder) { Self.redrawFocus(owner) }
    }

    /// ⌘-Tab or closing the window ends a recording, so the shortcut never stays released.
    override func resignKey() {
        super.resignKey()
        for pane in panes { pane.windowDidResignKey() }
        if let owner = SettingsFocusRing.owner(of: firstResponder) { Self.redrawFocus(owner) }
    }

    /// Every focus change comes through here, so this is where the controls that gain and lose focus
    /// redraw their ring, and where a control focused below the fold scrolls fully into view (A4).
    @discardableResult
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let before = SettingsFocusRing.owner(of: firstResponder)
        let made = super.makeFirstResponder(responder)
        let after = SettingsFocusRing.owner(of: firstResponder)
        if before !== after {
            if let before { Self.redrawFocus(before) }
            if let after {
                Self.redrawFocus(after)
                let reach = SettingsFocusRing.reach()
                after.scrollToVisible(after.bounds.insetBy(dx: -reach, dy: -reach))
            }
        }
        return made
    }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: object)
        if let editor = editor as? NSTextView { SettingsStyle.styleEditing(editor) }
        return editor
    }

    /// A segment's ring crosses onto its partner and a Spread cell draws its picker's, so the view's
    /// neighbors redraw with it.
    private static func redrawFocus(_ view: NSView) {
        func mark(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(mark)
        }
        mark(view.superview ?? view)
    }

    /// Increase Contrast changes `border`, `inkMuted` and `inkInverseMuted`, which labels hold in
    /// their text and everything else reads when it draws.
    @objc private func displayOptionsChanged() {
        func restyle(_ view: NSView) {
            (view as? SettingsText)?.restyle()
            (view as? SettingsKeyField)?.restyle()
            view.needsDisplay = true
            view.subviews.forEach(restyle)
        }
        contentView.map(restyle)
    }

    override func close() {
        super.close()
        select(.opening)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Disabled and hidden controls stay in the chain and Tab skips them, so a control that becomes
    /// enabled needs no relink.
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

/// Each row is an accessibility cell named exactly the section's title, with a press, so VoiceOver
/// says "Spread, 2 of 6".
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

    /// Slate, with no line at its edge: the ivory ↔ slate edge alone parts it from the pane (§2.4).
    override func draw(_ dirtyRect: NSRect) {
        Palette.Settings.inverse.setFill()
        bounds.fill()
    }

    /// Selects the row without calling `onSelect`.
    func select(_ section: SettingsSection) {
        selected = section
        table.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { SettingsSection.allCases.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SidebarRowView() }

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
    private let name: SettingsText
    private var hover: NSTrackingArea?
    private var isHovered = false { didSet { restyle() } }
    var onPress: () -> Void = {}

    init(_ section: SettingsSection) {
        self.section = section
        name = SettingsControl.text(section.title, as: .label, tone: .inverseMuted,
                                    width: SettingsStyle.sidebarWidth - 2 * SettingsStyle.s4)
        super.init(frame: .zero)
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

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { restyle() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hover { removeTrackingArea(hover) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        hover = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    private func restyle() {
        let selected = backgroundStyle == .emphasized
        name.role = selected ? .term : .label
        name.tone = selected ? .ink : isHovered ? .inverse : .inverseMuted
        name.underline = isHovered && !selected
    }

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
    private let document = PaneDocument()
    private var panes: [SettingsPane] = []
    private var fit: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        backgroundColor = Palette.Settings.canvas
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

/// The panes' ivory, drawn like the sidebar's slate. The scroll view's own background only shows past
/// the ends while it bounces. Its origin is its top left, so a pane opens on its first row.
private final class PaneDocument: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Palette.Settings.canvas.setFill()
        dirtyRect.fill()
    }
}
