import XCTest
@testable import Ideator

/// What the tour sees of a desk, and the events it finds between two looks. The desk's own rules
/// make every change; the tour only reads.
final class TourFlowTests: XCTestCase {
    private typealias Fixtures = TourDeskFixtures

    private func id(_ name: String) -> CardID { Fixtures.id(name) }
    private func slot(_ index: Int) -> Place { Fixtures.slot(index) }

    private func facts(_ desk: Desk, visibility: Visibility = .all) -> TourFacts {
        Fixtures.world(desk, visibility: visibility).facts
    }

    /// The events a reader's action caused: what the tour finds when it looks before and after,
    /// knowing `reader` as the card New made.
    private func events(_ before: Desk, visibilityBefore: Visibility = .all,
                        _ after: Desk, visibilityAfter: Visibility = .all, reader: CardID? = nil) -> [TourEvent] {
        TourFacts.events(from: facts(before, visibility: visibilityBefore), to: facts(after, visibility: visibilityAfter),
                         reader: reader)
    }

    private func applying(_ command: Command, to desk: Desk) -> Desk {
        var next = desk
        _ = next.apply(command)
        return next
    }

    // MARK: The facts

    func testTheLooseCardsAreInSpreadsReadingOrderWithTheDesksOwnTieBreak() {
        let places: [(String, Place)] = [
            ("far", slot(7)), ("home", slot(0)), ("mid", slot(5)),
            ("tie-b", .free(GridPoint(x: 0.5, y: 0.4))), ("tie-a", .free(GridPoint(x: 0.5, y: 0.4))),
            ("high", .free(GridPoint(x: 0.5, y: 0.3))),
        ]
        let plain = Fixtures.desk(popped: places)
        // The desk's own order for the same cards, read back from a set that remembers their places.
        let asSet = Fixtures.desk(popped: places, set: (cells: .standard, homes: places))
        let known = asSet.spreadSet!.inReadingOrder.map(\.id)

        XCTAssertEqual(known.prefix(2).map(\.rawValue), ["home", "mid"], "sanity: the desk's order starts at the top left")
        XCTAssertEqual(facts(plain).loose, known, "the tour's order is the desk's order, ties by id")
    }

    func testCardsOfTheSpreadSetAreNotLooseAndTheSetIsOutWhileOneIsOnTheDesktop() {
        let desk = Fixtures.desk(popped: [("a", slot(0)), ("set1", slot(1)), ("set2", slot(2))], stack: ["s"],
                                 set: (cells: .standard, homes: [("set1", slot(1)), ("set2", slot(2))]))

        XCTAssertEqual(facts(desk).loose, [id("a")])
        XCTAssertTrue(facts(desk).setOut)
        XCTAssertEqual(facts(desk).total, 4, "desktop and stack together")
        XCTAssertFalse(facts(Fixtures.desk(popped: [("a", slot(0))])).setOut)
    }

    func testACardUnderHideAllIsStillLoose() {
        let desk = Fixtures.desk(popped: [("a", slot(0))])

        XCTAssertEqual(facts(desk, visibility: .hideAll).loose, [id("a")])
        XCTAssertTrue(facts(desk, visibility: .hideAll).isHidden)
        XCTAssertFalse(facts(desk).isHidden)
    }

    // MARK: How many blank cards Spread would make

    private func preview(_ desk: Desk, cells: SpreadCells = .standard) -> [Int] {
        Fixtures.world(desk, cells: cells).spreadPreview.map(\.index)
    }

    func testSpreadPreviewIsEveryTickedCellThatIsFree() {
        XCTAssertEqual(preview(Fixtures.desk()), [0, 1, 2, 5, 6, 7])
        XCTAssertEqual(Fixtures.world(Fixtures.desk()).freeSpreadCells, 6)
        XCTAssertEqual(preview(Fixtures.desk(), cells: Fixtures.cells(7, 0)), [0, 7], "in reading order")
    }

    func testSpreadPreviewSkipsCellsACardOrTheStackTakes() {
        let snapped = Fixtures.desk(popped: [("a", slot(1))])
        XCTAssertEqual(preview(snapped), [0, 2, 5, 6, 7])

        let free = Fixtures.desk(popped: [("a", .free(GridPoint(x: 0.1, y: 0.37)))])   // covers cell 5 most
        XCTAssertEqual(preview(free), [0, 1, 2, 6, 7])

        let stacked = Fixtures.desk(stack: ["s"], stackSlot: 6)
        XCTAssertEqual(preview(stacked), [0, 1, 2, 5, 7], "the stack in a ticked cell takes it")
    }

    func testSpreadPreviewIsEmptyWithNoCellsTickedOrEveryTickedCellTaken() {
        XCTAssertEqual(preview(Fixtures.desk(), cells: .empty), [])
        let taken = Fixtures.desk(popped: [("a", slot(0)), ("b", slot(1))])
        XCTAssertEqual(preview(taken, cells: Fixtures.cells(0, 1)), [])
        XCTAssertFalse(Fixtures.world(taken, cells: Fixtures.cells(0, 1)).spreadCanAct)
        XCTAssertTrue(Fixtures.world(taken).spreadCanAct)
    }

    func testSpreadPreviewIsEmptyWhileASetCardIsOutBecauseTheButtonGathers() {
        let out = Fixtures.desk(popped: [("a", slot(0))], set: (cells: .standard, homes: [("a", slot(0))]))

        XCTAssertEqual(preview(out), [])
        XCTAssertTrue(Fixtures.world(out).spreadCanAct, "there is a set out to gather")
    }

    func testASetWaitingInTheStackDoesNotShrinkTheCount() {
        let waiting = Fixtures.desk(stack: ["a", "b"], set: (cells: .standard, homes: [("a", slot(0)), ("b", slot(1))]))

        XCTAssertEqual(preview(waiting), [0, 1, 2, 5, 6, 7], "the prototype counts ticked cells that are not taken")
    }

    func testTheDryRunLeavesTheWorldsDeskAlone() {
        let desk = Fixtures.desk(popped: [("a", slot(1))], stack: ["s"])
        let world = Fixtures.world(desk)

        _ = world.spreadPreview

        XCTAssertEqual(world.desk, desk)
    }

    func testTheCountAgreesWithWhatAFreshSpreadClickReallyPutsOut() {
        let desk = Fixtures.desk(popped: [("a", slot(0)), ("b", .free(GridPoint(x: 0.5, y: 0.38)))], stack: ["s"])
        let predicted = Fixtures.world(desk).spreadPreview
        let after = applying(.spread(.standard, fresh: true, at: Fixtures.now), to: desk)

        XCTAssertEqual(after.popped.count - desk.popped.count, predicted.count)
        XCTAssertEqual(after.popped.dropFirst(desk.popped.count).map(\.place.slot), predicted)
    }

    // MARK: Events between two looks

    func testTwoLooksAtTheSameWorldFindNothing() {
        let desk = Fixtures.desk(popped: [("a", slot(0))], stack: ["s"])

        XCTAssertEqual(events(desk, desk), [])
        XCTAssertEqual(events(desk, visibilityBefore: .hideAll, desk, visibilityAfter: .hideAll), [])
    }

    func testHideAllAndShowAllAreEdgesOfTheHiddenFlag() {
        let desk = Fixtures.desk(popped: [("a", slot(0))])

        XCTAssertEqual(events(desk, desk, visibilityAfter: .hideAll), [.hidden])
        XCTAssertEqual(events(desk, visibilityBefore: .hideAll, desk), [.shown])
        let revealed = Visibility.hidden(revealed: [id("a")], stackCard: false)
        XCTAssertEqual(events(desk, visibilityBefore: .hideAll, desk, visibilityAfter: revealed), [],
                       "a card shown under Hide all is still Hide all")
    }

    func testNewMakesOneCardMoreThatIsLoose() {
        let before = Fixtures.desk(stack: ["s"])
        let after = applying(.new(at: Fixtures.now), to: before)

        XCTAssertEqual(events(before, after), [.new])
    }

    func testANewCardWhileAnotherIsOutIsStillNew() {
        let before = Fixtures.desk(popped: [("a", slot(0))])
        let after = applying(.new(at: Fixtures.now), to: before)

        XCTAssertEqual(events(before, after), [.new], "the card is loose now and was not before, whatever else is out")
    }

    func testSeveralCardsAppearingInOneLookAreNewToo() {
        let before = Fixtures.desk(popped: [("a", slot(0))])
        let after = Fixtures.desk(popped: [("a", slot(0)), ("b", slot(1)), ("c", slot(2))])

        XCTAssertEqual(events(before, after), [.new], "more than one card in a look is still New")
    }

    func testNewOnAFullDesktopChangesNothingSoFindsNothing() {
        let full = Fixtures.fullDesk(stack: [])
        let after = applying(.new(at: Fixtures.now), to: full)

        XCTAssertEqual(events(full, after), [], "no card, no event, so the page that waits for New keeps waiting")
    }

    func testPoppingAStackedCardIsNotNewBecauseTheTotalStaysTheSame() {
        let before = Fixtures.desk(stack: ["s"])
        let after = applying(.pop, to: before)

        XCTAssertEqual(after.popped.count, 1, "sanity: the card came out")
        XCTAssertEqual(events(before, after), [])
    }

    func testACardAnAIToolAddsToTheStackIsNotNew() {
        let before = Fixtures.desk(popped: [("a", slot(0))])
        let after = applying(.addFromTool(Note(header: "from a tool", body: []), at: Fixtures.now, to: .top, typing: false),
                             to: before)

        XCTAssertEqual(after.allCards.count, 2, "sanity: it joined")
        XCTAssertEqual(events(before, after), [])
    }

    func testTypingFindsNothing() {
        let before = Fixtures.desk(popped: [("a", slot(0))])
        let after = applying(.edit(id("a"), Note(header: "typed", body: [])), to: before)

        XCTAssertEqual(events(before, after), [])
    }

    func testTheReadersCardGoingBackToTheStackIsReturned() {
        let before = Fixtures.desk(popped: [("a", slot(0)), ("b", slot(1))])
        let after = applying(.returnToStack(id("a")), to: before)

        XCTAssertEqual(events(before, after, reader: id("a")), [.returned])
    }

    func testTheReadersCardBeingDeletedIsDeleted() {
        let before = Fixtures.desk(popped: [("a", slot(0)), ("b", slot(1))])
        let after = applying(.delete(id("a")), to: before)

        XCTAssertEqual(events(before, after, reader: id("a")), [.deleted])
    }

    func testAFileVanishingFromTheFolderReadsAsDeletedToo() {
        let before = Fixtures.desk(popped: [("a", slot(0))])
        let after = applying(.syncFiles([:]), to: before)

        XCTAssertEqual(events(before, after, reader: id("a")), [.deleted], "the page then says what is true: the card is gone")
    }

    func testAnotherCardLeavingIsNotTheReadersCard() {
        let before = Fixtures.desk(popped: [("a", slot(0)), ("b", slot(1))])

        XCTAssertEqual(events(before, applying(.returnToStack(id("b")), to: before), reader: id("a")), [])
        XCTAssertEqual(events(before, applying(.delete(id("b")), to: before), reader: id("a")), [])
    }

    func testWithNoReadersCardNoCardsLeavingIsReturnedOrDeleted() {
        let before = Fixtures.desk(popped: [("old", slot(0)), ("b", slot(1))])

        XCTAssertEqual(events(before, applying(.returnToStack(id("old")), to: before)), [],
                       "a card that was out before the tour is not the one the pages are about")
        XCTAssertEqual(events(before, applying(.delete(id("old")), to: before)), [])
    }

    func testMovingTheReadersCardIsNotReturnedOrDeleted() {
        let before = Fixtures.desk(popped: [("a", slot(0))])
        let after = applying(.move(.card(id("a")), to: slot(12)), to: before)

        XCTAssertEqual(events(before, after, reader: id("a")), [])
    }

    func testASpreadClickThatPutsBlankCardsOutIsSpreadOutAndNotNewOrLoose() {
        let before = Fixtures.desk(popped: [("a", slot(3))])
        let after = applying(.spread(.standard, fresh: false, at: Fixtures.now), to: before)

        XCTAssertEqual(events(before, after), [.spreadOut])
        XCTAssertEqual(facts(after).loose, [id("a")], "the set's cards are not the reader's")
    }

    func testARefusedSpreadFindsNothing() {
        let before = Fixtures.desk(popped: [("a", slot(0)), ("b", slot(1))])
        let after = applying(.spread(Fixtures.cells(0, 1), fresh: false, at: Fixtures.now), to: before)

        XCTAssertEqual(after, before, "sanity: the desk refused")
        XCTAssertEqual(events(before, after), [])
    }

    func testGatheringASetWithTextIsGatheredAndAnEmptyOneIsVanished() {
        let homes: [(String, Place)] = [("s1", slot(0)), ("s2", slot(1))]
        let texty = Fixtures.desk(popped: homes, set: (cells: Fixtures.cells(0, 1), homes: homes))
        XCTAssertEqual(events(texty, applying(.spread(Fixtures.cells(0, 1), fresh: false, at: Fixtures.now), to: texty)),
                       [.gathered], "the cards went to the stack and are still a set")

        let empty = Fixtures.desk(popped: homes, set: (cells: Fixtures.cells(0, 1), homes: homes), blank: ["s1", "s2"])
        XCTAssertEqual(events(empty, applying(.spread(Fixtures.cells(0, 1), fresh: false, at: Fixtures.now), to: empty)),
                       [.vanished], "an all-blank set is deleted")
    }

    func testASetComingBackOutOfTheStackIsSpreadOutToo() {
        let homes: [(String, Place)] = [("s1", slot(0)), ("s2", slot(1))]
        let stacked = Fixtures.desk(stack: ["s1", "s2"], set: (cells: Fixtures.cells(0, 1), homes: homes))
        let after = applying(.spread(Fixtures.cells(0, 1), fresh: false, at: Fixtures.now), to: stacked)

        XCTAssertEqual(events(stacked, after), [.spreadOut])
    }

    func testNewSpreadSweepsTheOldSetToTheStackWithoutAGatherEvent() {
        let homes: [(String, Place)] = [("s1", slot(0)), ("s2", slot(1))]
        let out = Fixtures.desk(popped: homes, set: (cells: Fixtures.cells(0, 1), homes: homes))
        let after = applying(.spread(Fixtures.cells(5, 6), fresh: true, at: Fixtures.now), to: out)

        XCTAssertEqual(events(out, after), [], "a set was out and a set is out: the page keeps waiting for the real Gather")
    }

    func testHidingAndReturningInOneLookFindBothInOrder() {
        let before = Fixtures.desk(popped: [("a", slot(0))])
        let after = applying(.returnToStack(id("a")), to: before)

        XCTAssertEqual(events(before, after, visibilityAfter: .hideAll, reader: id("a")), [.hidden, .returned])
    }
}
