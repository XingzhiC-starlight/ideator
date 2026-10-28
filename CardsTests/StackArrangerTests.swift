import XCTest
@testable import Ideator

/// The arranger's pure rules, and its keyboard and VoiceOver paths driven without a popover.
/// Opening it, grip drags, the insertion line and the popover following the badge need a shown
/// window: those are `verify-cards` work (features/arrange-stack.md).
final class StackArrangerTests: XCTestCase {
    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    private func rows(_ names: String...) -> [StackRow] { names.map { StackRow(id: id($0), title: $0.uppercased()) } }

    private func arrangement(_ names: [String], current: String? = nil) -> Arrangement {
        Arrangement(rows: names.map { StackRow(id: id($0), title: $0.uppercased()) }, current: current.map(id))
    }

    /// What a desk, a command log and the words spoken look like to the arranger's `send`.
    /// `nonisolated` because a main-actor class that is freed at the end of a synchronous test
    /// crashes the runtime's isolated deinit.
    private nonisolated final class Wire {
        var desk: Desk
        var sent: [Command] = []
        var spoken: [String] = []
        init(_ desk: Desk) { self.desk = desk }
        var order: [String] { desk.stack.map(\.id.rawValue) }
    }

    /// An arranger wired to a desk the way DeskController wires it: a command goes to the desk and
    /// the face comes straight back, before `send` returns. The popover is never shown.
    private func arranger(over names: [String]) -> (arranger: StackArranger, wire: Wire) {
        let notes = Dictionary(uniqueKeysWithValues: names.map { (CardID(rawValue: $0), Note(header: $0.uppercased(), body: [])) })
        let wire = Wire(Desk(notes: notes, saved: SavedDesk(stack: names.map { CardID(rawValue: $0) })))
        var arranger: StackArranger?
        arranger = StackArranger(send: { command in
            wire.sent.append(command)
            wire.desk.apply(command)
            arranger?.apply(wire.desk.stackFace(hasKey: false).arrangement)
        }, spoken: { wire.spoken.append($0) })
        arranger!.apply(wire.desk.stackFace(hasKey: false).arrangement)
        arranger!.table.reloadData()
        return (arranger!, wire)
    }

    private func select(_ row: Int, in arranger: StackArranger) {
        arranger.table.selectRowIndexes([row], byExtendingSelection: false)
    }

    func testLandingAccountsForTheDraggedRowLeavingTheList() {
        XCTAssertEqual(StackArranger.landing(from: 0, gap: 3), 2, "dropped below two rows, it lands at index 2")
        XCTAssertEqual(StackArranger.landing(from: 3, gap: 0), 0, "dropped above, it lands where the gap is")
        XCTAssertEqual(StackArranger.landing(from: 2, gap: 4), 3, "dropped after the last row but one")
        XCTAssertNil(StackArranger.landing(from: 1, gap: 1), "the gap just above the card is where it is")
        XCTAssertNil(StackArranger.landing(from: 1, gap: 2), "and so is the gap just below it")
    }

    func testGapIsAboveARowFromItsUpperHalfAndBelowFromItsLowerHalf() {
        let h = StackArranger.rowHeight
        XCTAssertEqual(StackArranger.gap(atY: 2, rowCount: 4), 0, "near the top row's top edge")
        XCTAssertEqual(StackArranger.gap(atY: h / 2 - 6, rowCount: 4), 0, "6 points above the top row's center")
        XCTAssertEqual(StackArranger.gap(atY: h / 2 + 6, rowCount: 4), 1, "6 points below it")
        XCTAssertEqual(StackArranger.gap(atY: h + h / 2 - 6, rowCount: 4), 1, "upper half of the second row")
        XCTAssertEqual(StackArranger.gap(atY: 3 * h + h / 2 + 6, rowCount: 4), 4, "lower half of the last row")
        XCTAssertEqual(StackArranger.gap(atY: -3, rowCount: 4), 0, "above the list")
        XCTAssertEqual(StackArranger.gap(atY: 10 * h, rowCount: 4), 4, "below the last row")
    }

    func testRowBatchIsOneRemovalAndOneInsertionForAMove() {
        let batch = StackArranger.rowBatch(from: rows("a", "b", "c", "d"), to: rows("c", "a", "b", "d"))
        XCTAssertEqual(batch.removals, [2], "c leaves its old index")
        XCTAssertEqual(batch.insertions, [0], "and joins at its new one")
    }

    func testRowBatchForACardThatLeavesAndOneThatJoins() {
        let batch = StackArranger.rowBatch(from: rows("a", "b", "c"), to: rows("a", "c", "d"))
        XCTAssertEqual(batch.removals, [1], "b is gone, in old indexes")
        XCTAssertEqual(batch.insertions, [2], "d is new, in new indexes")
        let same = StackArranger.rowBatch(from: rows("a", "b"), to: [StackRow(id: id("a"), title: "Renamed"), StackRow(id: id("b"), title: "B")])
        XCTAssertTrue(same.removals.isEmpty && same.insertions.isEmpty, "a rename moves nothing")
    }

    func testNudgeStopsAtTheEndsAndSaysWhenTheCardIsGone() {
        let list = arrangement(["a", "b", "c"])
        XCTAssertEqual(list.nudge(id("b"), .up), .move(to: 0))
        XCTAssertEqual(list.nudge(id("b"), .down), .move(to: 2))
        XCTAssertEqual(list.nudge(id("a"), .up), .alreadyAtTop, "there is no wrap")
        XCTAssertEqual(list.nudge(id("c"), .down), .alreadyAtBottom)
        XCTAssertEqual(list.nudge(id("ghost"), .up), .gone, "a card that left has no place")
    }

    func testPlacesAreSpokenFromOne() {
        let list = arrangement(["a", "b", "c"], current: "b")
        XCTAssertEqual(list.spokenPlace(of: id("c")), "3 of 3")
        XCTAssertNil(list.spokenPlace(of: id("ghost")))
        XCTAssertEqual(list.spokenRow(at: 0), "A, 1 of 3", "an ordinary row reads its title and place")
        XCTAssertEqual(list.spokenRow(at: 1), "B, 2 of 3, current card", "the shown card says so")
    }

    func testTheKeyboardStartsOnTheShownCardOrTheTopRowOnTheBlankPage() {
        XCTAssertEqual(arrangement(["a", "b"], current: "b").opening, id("b"))
        XCTAssertEqual(arrangement(["a", "b"], current: nil).opening, id("a"), "the blank page has no row, so the top one")
        XCTAssertNil(Arrangement.empty.opening)
    }

    func testTheFaceBecomesTheArrangementTheDeskShows() {
        var desk = Desk(notes: [id("a"): Note(header: "A", body: []), id("b"): Note(header: "", body: [])],
                        saved: SavedDesk(stack: [id("a"), id("b")]))
        desk.apply(.flipStack(.next))
        let shown = desk.stackFace(hasKey: false).arrangement
        XCTAssertEqual(shown.rows.map(\.id), [id("a"), id("b")], "rows are the stack, top first")
        XCTAssertEqual(shown.rows.map(\.title), ["A", "Untitled"])
        XCTAssertEqual(shown.current, id("b"), "and the current card is the shown one")
        desk.apply(.flipStack(.next))
        XCTAssertNil(desk.stackFace(hasKey: false).arrangement.current, "the blank page is nobody's row")
    }

    func testAKeystrokeInTheShownCardLeavesTheArrangementEqual() {
        var desk = Desk(notes: [id("a"): Note(header: "A", body: [])], saved: SavedDesk(stack: [id("a")]))
        let before = desk.stackFace(hasKey: false).arrangement
        desk.apply(.edit(id("a"), Note(header: "A", body: [Line(runs: [Run(text: "more text")])])))
        XCTAssertEqual(desk.stackFace(hasKey: false).arrangement, before, "so an open list is not touched by typing in the body")
        desk.apply(.edit(id("a"), Note(header: "AB", body: [])))
        XCTAssertNotEqual(desk.stackFace(hasKey: false).arrangement, before, "but a new header is a rename")
    }

    func testTheKeyMapTakesOptionArrowsReturnSpaceAndEscapeOnly() {
        XCTAssertEqual(ArrangerKey(keyCode: 126, option: true, otherModifiers: false), .moveUp)
        XCTAssertEqual(ArrangerKey(keyCode: 125, option: true, otherModifiers: false), .moveDown)
        XCTAssertNil(ArrangerKey(keyCode: 126, option: false, otherModifiers: false), "plain arrows are the table's")
        XCTAssertNil(ArrangerKey(keyCode: 126, option: true, otherModifiers: true), "⌘⌥↑ is somebody else's")
        for code: UInt16 in [36, 76, 49] {
            XCTAssertEqual(ArrangerKey(keyCode: code, option: false, otherModifiers: false), .show, "Return, Enter and Space show")
        }
        XCTAssertEqual(ArrangerKey(keyCode: 53, option: false, otherModifiers: false), .close)
        XCTAssertNil(ArrangerKey(keyCode: 0, option: false, otherModifiers: false))
    }

    func testOptionDownMovesTheSelectedCardOneDownAndAnnouncesWhereItWent() {
        let (arranger, wire) = arranger(over: ["a", "b", "c"])
        select(0, in: arranger)
        arranger.table.onKey(.moveDown)
        XCTAssertEqual(wire.order, ["b", "a", "c"], "the card moved one place down")
        XCTAssertEqual(wire.sent.count, 1, "with one command")
        guard case .arrange(let moved, at: 1)? = wire.sent.first else { return XCTFail("sent \(wire.sent)") }
        XCTAssertEqual(moved, id("a"))
        XCTAssertEqual(wire.spoken, ["Moved to 2 of 3"], "VoiceOver hears the card's real new place")
        XCTAssertEqual(arranger.selectedID, id("a"), "and the card stays selected")
    }

    func testMovingPastAnEndSendsNothingAndSaysSo() {
        let (arranger, wire) = arranger(over: ["a", "b"])
        select(0, in: arranger)
        arranger.table.onKey(.moveUp)
        select(1, in: arranger)
        arranger.table.onKey(.moveDown)
        XCTAssertTrue(wire.sent.isEmpty, "nothing reaches the desk")
        XCTAssertEqual(wire.spoken, ["Already at the top", "Already at the bottom"])
    }

    func testReturnShowsTheSelectedCardWithoutMovingAnything() {
        let (arranger, wire) = arranger(over: ["a", "b", "c"])
        select(2, in: arranger)
        arranger.table.onKey(.show)
        XCTAssertEqual(wire.desk.selectedCard?.id, id("c"), "the stack turned to c")
        XCTAssertEqual(wire.order, ["a", "b", "c"], "and nothing was reordered")
        XCTAssertEqual(arranger.selectedID, id("c"))
    }

    func testAClosedArrangerOnlyRemembersWhatTheDeskShows() {
        let (arranger, wire) = arranger(over: ["a", "b"])
        wire.desk.apply(.flipStack(.next))
        arranger.apply(wire.desk.stackFace(hasKey: false).arrangement)
        XCTAssertNil(arranger.table.window, "nothing opened")
        XCTAssertEqual(arranger.arrangement.current, id("b"), "but it knows b shows")
    }

    func testARowReadsItsTitlePlaceAndCurrentMarkAndOffersMoveUpMoveDownAndPress() throws {
        let row = ArrangerCell()
        var pressed = 0
        var steps: [Arrangement.Step] = []
        row.onPress = { pressed += 1 }
        row.onStep = { steps.append($0) }
        row.show(StackRow(id: id("a"), title: "Groceries"), spoken: "Groceries, 3 of 7, current card", isCurrent: true)
        XCTAssertEqual(row.accessibilityLabel(), "Groceries, 3 of 7, current card")
        XCTAssertEqual(row.accessibilityRole(), .cell)
        XCTAssertEqual((row.accessibilityChildren() ?? []).count, 0, "its grip and title are not read separately")
        XCTAssertFalse(row.grip.isAccessibilityElement(), "the grip is hidden from VoiceOver")
        let actions = try XCTUnwrap(row.accessibilityCustomActions())
        XCTAssertEqual(actions.map(\.name), ["Move up", "Move down"])
        XCTAssertTrue(row.accessibilityPerformPress(), "press shows the card")
        XCTAssertEqual(pressed, 1)
        for action in actions { _ = action.handler?() }
        XCTAssertEqual(steps, [.up, .down], "the actions step the card")
    }

    func testOnlyAPressOnTheGripAtTheRowsRightEdgeCanStartADrag() {
        let table = StackArranger(send: { _ in }).table
        let width: CGFloat = 260
        XCTAssertTrue(ArrangerCell.isGrip(x: width - 10, rowWidth: width), "the strip at the right is the grip")
        XCTAssertTrue(ArrangerCell.isGrip(x: width - ArrangerCell.gripWidth, rowWidth: width), "from its leading edge")
        XCTAssertFalse(ArrangerCell.isGrip(x: width - ArrangerCell.gripWidth - 1, rowWidth: width), "the name is not")
        XCTAssertFalse(ArrangerCell.isGrip(x: 10, rowWidth: width), "and neither is the row's left end")
        XCTAssertEqual(table.numberOfColumns, 1, "one column, no header")
        XCTAssertNil(table.headerView)
    }

    func testTheGripSitsAtTheRightEdgeAndTheTitleStopsBeforeIt() {
        let cell = ArrangerCell(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        cell.show(StackRow(id: id("a"), title: String(repeating: "A very long header ", count: 8)), spoken: "", isCurrent: false)
        cell.layoutSubtreeIfNeeded()
        XCTAssertEqual(cell.grip.frame.maxX, 260, "the grip ends at the trailing edge")
        XCTAssertEqual(cell.grip.frame.width, ArrangerCell.gripWidth)
        let title = cell.subviews.compactMap { $0 as? NSTextField }.first!
        XCTAssertLessThan(title.frame.minX, 20, "the title starts at the left edge")
        XCTAssertLessThanOrEqual(title.frame.maxX, cell.grip.frame.minX, "and truncates before the grip")
    }

    func testTheContentGrowsToTenRowsThenScrolls() {
        XCTAssertLessThan(StackArranger.contentHeight(rowCount: 3), StackArranger.contentHeight(rowCount: 4))
        XCTAssertEqual(StackArranger.contentHeight(rowCount: 10), StackArranger.contentHeight(rowCount: 40), "past ten rows it stays put")
    }
}
