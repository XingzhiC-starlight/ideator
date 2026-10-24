import AppKit

/// What the arranger lists, as one value derived from the desk: the stacked cards top first, and
/// the one the stack shows (nil on the blank page, which has no row). The arranger compares it
/// with `==` and diffs it by id, and never keeps a copy it edits: the order lives in `Desk.stack`.
struct Arrangement: Equatable {
    let rows: [StackRow]
    let current: CardID?

    static let empty = Arrangement(rows: [], current: nil)

    /// `.up` is toward the top of the stack. There is no wrap.
    enum Step { case up, down }

    enum Nudge: Equatable {
        case move(to: Int)
        case alreadyAtTop, alreadyAtBottom
        /// The card left the stack while the arranger was open.
        case gone
    }

    func position(of id: CardID) -> Int? { rows.firstIndex { row in row.id == id } }

    /// The row the keyboard starts on: the shown card's, or the top row on the blank page.
    var opening: CardID? { current ?? rows.first?.id }

    func nudge(_ id: CardID, _ step: Step) -> Nudge {
        guard let i = position(of: id) else { return .gone }
        switch step {
        case .up: return i == 0 ? .alreadyAtTop : .move(to: i - 1)
        case .down: return i == rows.count - 1 ? .alreadyAtBottom : .move(to: i + 1)
        }
    }

    /// "3 of 7", for the move announcement.
    func spokenPlace(of id: CardID) -> String? {
        position(of: id).map { "\($0 + 1) of \(rows.count)" }
    }

    /// What VoiceOver reads for the row at `index`.
    func spokenRow(at index: Int) -> String {
        let row = rows[index]
        return "\(row.title), \(index + 1) of \(rows.count)" + (row.id == current ? ", current card" : "")
    }
}

extension StackFace {
    var arrangement: Arrangement { Arrangement(rows: stacked, current: selected?.id) }
}

/// The keys the arranger takes over. Plain ↑ and ↓ are not here: the table already moves its selection.
enum ArrangerKey: Equatable {
    case moveUp, moveDown, show, close

    /// `otherModifiers`: shift, control or command is down. The caller masks arrow keys' numeric-pad
    /// and function flags away before asking.
    init?(keyCode: UInt16, option: Bool, otherModifiers: Bool) {
        guard !otherModifiers else { return nil }
        switch (keyCode, option) {
        case (126, true): self = .moveUp
        case (125, true): self = .moveDown
        case (36, false), (76, false), (49, false): self = .show   // Return, keypad Enter, Space
        case (53, false): self = .close
        default: return nil
        }
    }
}

/// The stack arranger: a transient popover off the count badge listing the stacked cards, top
/// first, to reorder them (grip drag, ⌥↑ and ⌥↓, VoiceOver actions) and to turn the stack to one
/// (click, Return, Space, VoiceOver press).
///
/// It owns no desk state. Every change leaves as a `Command` keyed by `CardID`, and the list is
/// whatever the last `apply(_:)` gave it. `send` is synchronous: the desk, the render and this
/// object's own `apply` have all run when it returns, so a move announces the card's real new place.
final class StackArranger: NSObject {
    private let send: (Command) -> Void
    private let spoken: ((String) -> Void)?
    private let popover = NSPopover()
    private let scroll = NSScrollView()
    let table = ArrangerTable()
    private(set) var arrangement = Arrangement.empty
    /// The keyboard's row, by id, so it follows its card through moves and live updates. The
    /// table's selection mirrors it; user changes write it, `apply` rederives the table from it.
    private(set) var selectedID: CardID?
    /// The card whose grip is being dragged.
    private var dragging: CardID?
    /// The gap the last `validateDrop` chose, so a move into the other half of a row asks again.
    private var dropGap: Int?
    /// A table update is running, so selection callbacks index a half-updated table.
    private var patching = false
    private weak var anchorView: NSView?
    private var anchorRect = NSRect.zero

    static let rowHeight: CGFloat = 24
    static let visibleRows = 10
    static let width: CGFloat = 260
    private static let verticalInset: CGFloat = 6
    /// Private to Ideator, so a row dropped on a card's text view inserts nothing.
    static let rowType = NSPasteboard.PasteboardType("com.systemlabs.Ideator.stack-row")

    /// `spoken` replaces the VoiceOver announcement, for tests.
    init(send: @escaping (Command) -> Void, spoken: ((String) -> Void)? = nil) {
        self.send = send
        self.spoken = spoken
        super.init()
        configure()
    }

    var isOpen: Bool { popover.isShown }

    /// Opens under `rect` (in `view`'s coordinates) with the shown card's row selected, or closes
    /// when open: a press on the badge toggles. Nothing with no rows.
    func toggle(relativeTo rect: NSRect, of view: NSView) {
        if popover.isShown { close(); return }
        guard !arrangement.rows.isEmpty else { return }
        // The first click can arrive while Ideator is inactive, and an inactive app's popover gets no keys.
        NSApp.activate()
        anchorView = view
        anchorRect = rect
        selectedID = arrangement.opening
        table.reloadData()
        select(selectedID)
        resize()
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func close() {
        if popover.isShown { popover.close() }
    }

    /// The badge moved or went; `rect` is its frame in the anchor view, nil when it is hidden or
    /// disabled. The popover hangs from the stack view, not from the badge, so that a badge that
    /// jumps between the card's corner and the ribbon changes the rect and the popover follows.
    func follow(_ rect: NSRect?) {
        guard popover.isShown else { return }
        guard let rect else { close(); return }
        anchorRect = rect
        if popover.positioningRect != rect { popover.positioningRect = rect }
    }

    /// The desk changed. Closed, it only remembers. Open, rows are matched by id and patched in
    /// place, never reloaded, so a drag in flight and the VoiceOver cursor survive.
    func apply(_ new: Arrangement) {
        guard new != arrangement else { return }
        let old = arrangement
        arrangement = new
        guard popover.isShown else { return }
        guard !new.rows.isEmpty else { close(); return }
        let batch = Self.rowBatch(from: old.rows, to: new.rows)
        patching = true
        if let from = batch.removals.first, let to = batch.insertions.first, batch.removals.count == 1,
           batch.insertions.count == 1, old.rows[from].id == new.rows[to].id {
            table.moveRow(at: from, to: to)
        } else if !batch.removals.isEmpty || !batch.insertions.isEmpty {
            table.beginUpdates()
            table.removeRows(at: batch.removals, withAnimation: [])
            table.insertRows(at: batch.insertions, withAnimation: [])
            table.endUpdates()
        }
        patching = false
        table.enumerateAvailableRowViews { view, row in
            if let view = view as? ArrangerRow { configure(view, row: row) }
            if let cell = view.view(atColumn: 0) as? ArrangerCell { configure(cell, row: row) }
        }
        if let id = selectedID, new.position(of: id) == nil { selectedID = new.opening }
        select(selectedID)
        resize()
    }

    // MARK: Moves

    /// Every move comes through here: a drop, ⌥↑ and ⌥↓, a VoiceOver action.
    private func move(_ id: CardID, to index: Int) {
        send(.arrange(id, at: index))
        if let place = arrangement.spokenPlace(of: id) { announce("Moved to \(place)") }
    }

    private func nudge(_ step: Arrangement.Step) {
        guard let id = selectedID else { return }
        switch arrangement.nudge(id, step) {
        case .move(let to): move(id, to: to)
        case .alreadyAtTop: announce("Already at the top")
        case .alreadyAtBottom: announce("Already at the bottom")
        case .gone: break
        }
    }

    private func handle(_ key: ArrangerKey) {
        switch key {
        case .moveUp: nudge(.up)
        case .moveDown: nudge(.down)
        case .show: if let id = selectedID { send(.showStacked(id)) }
        case .close: close()
        }
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard arrangement.rows.indices.contains(row) else { return }
        let rect = table.rect(ofRow: row)
        guard !ArrangerCell.isGrip(x: table.lastMouseDown.x - rect.minX, rowWidth: rect.width) else { return }
        send(.showStacked(arrangement.rows[row].id))
    }

    // MARK: Table

    private func select(_ id: CardID?) {
        let row = id.flatMap(arrangement.position(of:))
        let wanted = row.map { IndexSet(integer: $0) } ?? IndexSet()
        if table.selectedRowIndexes != wanted { table.selectRowIndexes(wanted, byExtendingSelection: false) }
        if let row { table.scrollRowToVisible(row) }
    }

    private func configure(_ view: ArrangerRow, row: Int) {
        view.isCurrent = arrangement.rows[row].id == arrangement.current
    }

    private func configure(_ cell: ArrangerCell, row: Int) {
        let card = arrangement.rows[row]
        cell.show(card, spoken: arrangement.spokenRow(at: row), isCurrent: card.id == arrangement.current)
    }

    private func resize() {
        popover.contentSize = NSSize(width: Self.width, height: Self.contentHeight(rowCount: arrangement.rows.count))
    }

    /// Up to `visibleRows` rows tall, then the list scrolls.
    static func contentHeight(rowCount: Int) -> CGFloat {
        CGFloat(min(rowCount, visibleRows)) * rowHeight + 2 * verticalInset
    }

    private func configure() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("stack-row"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.allowsTypeSelect = false   // Space shows a card
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.registerForDraggedTypes([Self.rowType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.draggingDestinationFeedbackStyle = .regular   // the standard insertion line
        table.setAccessibilityLabel("Stack order")
        table.onKey = { [unowned self] key in handle(key) }
        table.dropIsStale = { [unowned self] info in dropGap != nil && pointerGap(info) != dropGap }

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.contentHeight(rowCount: 1)))
        scroll.frame = content.bounds.insetBy(dx: 0, dy: Self.verticalInset)
        content.addSubview(scroll)
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient   // Esc or a click outside closes it
        popover.appearance = NSAppearance(named: .aqua)   // cards keep the light look in Dark Mode
        popover.delegate = self
    }

    private func announce(_ text: String) {
        if let spoken { spoken(text); return }
        NSAccessibility.post(element: table, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    // MARK: Pure helpers

    /// The gap a drop at `y` (in the flipped table, from its top) goes into: above a row from its
    /// upper half, below it from its lower half, counted with the dragged row still in the list.
    static func gap(atY y: CGFloat, rowCount: Int) -> Int {
        min(max(Int((y / rowHeight + 0.5).rounded(.down)), 0), rowCount)
    }

    /// NSTableView proposes "drop above row `gap`", counted with the dragged row still in the
    /// list, so the card's final index is one less when it came from above the gap. Nil: it
    /// would not move, so the drop shows no insertion line.
    static func landing(from: Int, gap: Int) -> Int? {
        let to = gap > from ? gap - 1 : gap
        return to == from ? nil : to
    }

    /// What turns `old` into `new` by id, as a table update wants it: removals in old indexes,
    /// insertions in new indexes. A move is one of each.
    static func rowBatch(from old: [StackRow], to new: [StackRow]) -> (removals: IndexSet, insertions: IndexSet) {
        var removals = IndexSet(), insertions = IndexSet()
        for change in new.map(\.id).difference(from: old.map(\.id)) {
            switch change {
            case .remove(let offset, _, _): removals.insert(offset)
            case .insert(let offset, _, _): insertions.insert(offset)
            }
        }
        return (removals, insertions)
    }
}

extension StackArranger: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { arrangement.rows.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = (tableView.makeView(withIdentifier: ArrangerRow.reuse, owner: nil) as? ArrangerRow) ?? ArrangerRow()
        configure(view, row: row)
        return view
    }

    /// Cells are reused, so each action looks up the card its cell shows at the moment it runs.
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell: ArrangerCell
        if let reused = tableView.makeView(withIdentifier: ArrangerCell.reuse, owner: nil) as? ArrangerCell {
            cell = reused
        } else {
            cell = ArrangerCell()
            cell.onStep = { [unowned self, unowned cell] step in
                select(cell.cardID)
                nudge(step)
            }
            cell.onPress = { [unowned self, unowned cell] in
                guard let id = cell.cardID else { return }
                select(id)
                send(.showStacked(id))
            }
        }
        configure(cell, row: row)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !patching else { return }
        let row = table.selectedRow
        selectedID = arrangement.rows.indices.contains(row) ? arrangement.rows[row].id : nil
    }

    // Drag source: only reached when `ArrangerTable.canDragRows` found the press on a grip.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard arrangement.rows.indices.contains(row) else { return nil }
        let id = arrangement.rows[row].id
        dragging = id
        dropGap = nil
        let item = NSPasteboardItem()
        item.setString(id.rawValue, forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        session.animatesToStartingPositionsOnCancelOrFail = true   // Esc or a drop outside slides back
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = nil
    }

    // Drop target. The proposal is ignored: the gap comes from the pointer. A card that left the
    // stack mid-drag is refused here: AppKit has no API to cancel a session.
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let id = dragging, let from = arrangement.position(of: id), let gap = pointerGap(info) else { return [] }
        dropGap = gap
        tableView.setDropRow(gap, dropOperation: .above)
        return Self.landing(from: from, gap: gap) == nil ? [] : .move
    }

    private func pointerGap(_ info: NSDraggingInfo) -> Int? {
        guard dragging != nil else { return nil }
        return Self.gap(atY: table.convert(info.draggingLocation, from: nil).y, rowCount: arrangement.rows.count)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let id = dragging, let from = arrangement.position(of: id),
              let to = Self.landing(from: from, gap: row) else { return false }
        move(id, to: to)
        return true
    }
}

extension StackArranger: NSPopoverDelegate {
    /// A press on the badge reaches here first, since it is outside the popover. Refusing it lets the
    /// badge's own action toggle, instead of closing here and reopening there.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown, let view = anchorView,
              event.window === view.window else { return true }
        return !anchorRect.contains(view.convert(event.locationInWindow, from: nil))
    }

    func popoverDidShow(_ notification: Notification) {
        guard let window = table.window else { return }
        window.makeKey()
        window.makeFirstResponder(table)
    }

    func popoverDidClose(_ notification: Notification) {
        dragging = nil
    }
}

/// The list. Only a press on a row's grip starts a drag, and the arranger's keys go to `onKey`
/// before the table's own key handling sees them.
final class ArrangerTable: NSTableView {
    var onKey: (ArrangerKey) -> Void = { _ in }
    /// The pointer has moved to another gap than the drop row shows.
    var dropIsStale: (NSDraggingInfo) -> Bool = { _ in false }
    /// Where the last press landed, so a click on a grip that did not drag is not taken for a click on a name.
    private(set) var lastMouseDown = NSPoint.zero

    override func canDragRows(with rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool {
        let row = row(at: mouseDownPoint)
        let rect = rect(ofRow: row)
        return row >= 0 && ArrangerCell.isGrip(x: mouseDownPoint.x - rect.minX, rowWidth: rect.width)
    }

    /// NSTableView asks `validateDrop` only when its own proposal changes, and a row's whole middle is
    /// one proposal, so the half the pointer entered by would stick. `draggingEntered` makes it
    /// propose afresh. Setting the drop row here instead, outside `validateDrop`, hides the insertion line.
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if dropIsStale(sender) { _ = super.draggingEntered(sender) }
        return super.draggingUpdated(sender)
    }

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard let key = ArrangerKey(keyCode: event.keyCode, option: flags.contains(.option),
                                    otherModifiers: !flags.subtracting(.option).isEmpty) else {
            super.keyDown(with: event)
            return
        }
        onKey(key)
    }
}

/// The row's background: the keyboard's row in Ideator's own highlight rather than the system's blue,
/// and the shown card's row fainter.
final class ArrangerRow: NSTableRowView {
    static let reuse = NSUserInterfaceItemIdentifier("arranger-row")

    var isCurrent = false {
        didSet { if isCurrent != oldValue { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.reuse
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isCurrent else { return }
        Palette.highlight.withAlphaComponent(0.5).setFill()
        highlightShape.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        Palette.highlight.setFill()
        highlightShape.fill()
    }

    private var highlightShape: NSBezierPath { NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5) }
}

/// What a row shows, and what VoiceOver reads for it: "<title>, 3 of 7", plus ", current card" for
/// the shown one, with Move up and Move down in the actions menu, and press shows the card. Its
/// grip and title are not elements, so the row is read once.
final class ArrangerCell: NSTableCellView {
    static let reuse = NSUserInterfaceItemIdentifier("arranger-cell")
    static let gripWidth: CGFloat = 30
    private static let titleInset: CGFloat = 12

    let grip = GripView()
    private let title = NSTextField(labelWithString: "")
    private var spoken = ""
    private(set) var cardID: CardID?
    var onStep: (Arrangement.Step) -> Void = { _ in }
    var onPress: () -> Void = {}

    /// The grip is the strip at the row's trailing edge; `x` is measured from the row's leading edge.
    static func isGrip(x: CGFloat, rowWidth: CGFloat) -> Bool { x >= rowWidth - gripWidth && x <= rowWidth }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.reuse
        title.font = .systemFont(ofSize: 12)
        title.textColor = Palette.ink
        title.lineBreakMode = .byTruncatingTail
        title.setAccessibilityElement(false)
        addSubview(grip)
        addSubview(title)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Move up") { [weak self] in self?.onStep(.up); return true },
            NSAccessibilityCustomAction(name: "Move down") { [weak self] in self?.onStep(.down); return true },
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ row: StackRow, spoken: String, isCurrent: Bool) {
        cardID = row.id
        title.stringValue = row.title
        title.font = .systemFont(ofSize: 12, weight: isCurrent ? .semibold : .regular)
        self.spoken = spoken
    }

    /// Every press lands on the cell, so the table sees the click or the drag whatever it hit.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func layout() {
        super.layout()
        grip.frame = NSRect(x: bounds.width - Self.gripWidth, y: 0, width: Self.gripWidth, height: bounds.height)
        let height = title.intrinsicContentSize.height
        title.frame = NSRect(x: Self.titleInset, y: (bounds.height - height) / 2,
                             width: max(bounds.width - Self.gripWidth - Self.titleInset, 0), height: height)
    }

    // NSTableView wraps every cell in its own AXCell and forwards this view's label and actions to it.
    // Making the view an element too nests a second AXCell with the same label inside the first.
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .cell }
    override func accessibilityLabel() -> String? { spoken }
    override func accessibilityChildren() -> [Any]? { [] }

    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}

/// ≡ in the strip at a row's right. The only place a drag starts. Not a VoiceOver element.
final class GripView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func draw(_ dirtyRect: NSRect) {
        Palette.inkSoft.setFill()
        for line in -1...1 {
            NSRect(x: bounds.midX - 5, y: bounds.midY + CGFloat(line) * 3 - 0.5, width: 10, height: 1).fill()
        }
    }
}
