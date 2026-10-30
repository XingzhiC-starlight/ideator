import XCTest
@testable import Ideator

final class SpreadTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    private func slot(_ index: Int) -> Place { .slot(Slot(index: index)!) }

    private func cells(_ indices: Int...) -> SpreadCells { SpreadCells(indices: indices) }

    private func saved(_ name: String, _ place: Place) -> SavedPlacement {
        switch place {
        case .slot(let slot): SavedPlacement(slot: slot.index, card: id(name))
        case .free(let point): SavedPlacement(free: point, card: id(name))
        }
    }

    /// A desk as a launch loads it: `popped` cards where they are, `stack` top first, the stack in
    /// `stackSlot`, and, with `homes`, a Spread set laid out for `setCells` that remembers them.
    private func desk(popped: [(String, Place)] = [], stack: [String] = [], clarity: Bool = false,
                      stackSlot: Int? = nil, homes: [(String, Place)]? = nil, setCells: SpreadCells = .standard) -> Desk {
        let names = popped.map(\.0) + stack
        return Desk(notes: Dictionary(uniqueKeysWithValues: names.map { (id($0), Note(header: $0, body: [])) }),
                    saved: SavedDesk(clarity: clarity, stackSlot: stackSlot,
                                     placements: popped.map { saved($0.0, $0.1) }, stack: stack.map(id),
                                     spread: homes.map { SavedSpread(cells: setCells.indices, members: $0.map { saved($0.0, $0.1) }) }))
    }

    /// The desktop cards, by id, and where each is.
    private func out(_ desk: Desk) -> [CardID: Place] {
        Dictionary(uniqueKeysWithValues: desk.popped.map { ($0.card.id, $0.place) })
    }

    private func shown(_ desk: Desk) -> String { desk.selectedCard?.id.rawValue ?? "blank" }

    /// The desktop card in `cell`.
    private func card(in cell: Int, of desk: Desk) -> CardID {
        desk.popped.first { $0.place == slot(cell) }!.card.id
    }

    /// Types into a card, so a Gather of its set keeps the set instead of deleting it.
    private func write(_ id: CardID, in desk: inout Desk) {
        desk.apply(.edit(id, Note(header: "written", body: [])))
    }

    @discardableResult
    private func spread(_ desk: inout Desk, _ cells: SpreadCells = .standard, fresh: Bool = false) -> CardID? {
        desk.apply(.spread(cells, fresh: fresh, at: now))
    }

    func testTheFirstClickMakesABlankCardInEachTickedCellInReadingOrderAndReturnsTheFirst() {
        var desk = desk(stack: ["x"])
        let first = spread(&desk, cells(7, 0, 5))
        XCTAssertEqual(desk.popped.map(\.place), [slot(0), slot(5), slot(7)], "one card per ticked cell, in reading order")
        XCTAssertEqual(desk.poppedCards.map(\.note), [.blank, .blank, .blank], "each one blank")
        XCTAssertEqual(first, desk.popped.first?.card.id, "the first is the one to focus")
        XCTAssertEqual(desk.spreadSet?.cells, cells(0, 5, 7), "the set remembers the cells")
        XCTAssertEqual(desk.spreadSet?.homes, out(desk), "and holds every card it made, at its cell")
        XCTAssertEqual(desk.stack.map(\.id), [id("x")], "the stack is untouched")
    }

    func testATakenCellIsSkippedByPopsRuleSnappedFreeOrTheStack() {
        var desk = desk(popped: [("a", slot(0)), ("b", .free(GridPoint(x: 0.31, y: 0.12)))], stackSlot: 5)
        spread(&desk)
        XCTAssertEqual(desk.popped.dropFirst(2).map(\.place), [slot(2), slot(6), slot(7)],
                       "a snapped card takes 0, a free card takes 1, the stack takes 5")
    }

    func testEveryCellTakenChangesNothing() {
        var desk = desk(popped: [0, 1, 2, 5, 6, 7].map { ("p\($0)", slot($0)) }, stack: ["x"], clarity: true)
        let before = desk
        XCTAssertNil(spread(&desk), "no card comes out")
        XCTAssertEqual(desk, before, "and nothing changes, Clarity included")
    }

    func testNoTickedCellsChangesNothingAndKeepsTheSet() {
        var desk = desk(stack: ["s1", "s2"], homes: [("s1", slot(0)), ("s2", slot(1))])
        let before = desk
        spread(&desk, .empty)
        XCTAssertEqual(desk, before, "a click with no cells ticked leaves the set in the stack")
        spread(&desk, .empty, fresh: true)
        XCTAssertEqual(desk, before, "so does a fresh one")
    }

    func testTheCeilingStopsSpreadAt19Cards() {
        let snapped = Slot.all.filter { ![Slot.stackHome.index, 18, 19].contains($0.index) }
        var desk = desk(popped: snapped.map { ("p\($0.index)", .slot($0)) } + [("f", .free(Slot.all[0].center))])
        XCTAssertEqual(desk.popped.count, 18)
        spread(&desk, cells(18, 19))
        XCTAssertEqual(desk.popped.count, 19, "one more card, then the ceiling")
        XCTAssertEqual(desk.popped.last?.place, slot(18), "in the first ticked cell")
    }

    func testGatherPutsTheSetsDesktopCardsAtTheBottomInReadingOrder() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0, 1, 2))
        let (c0, c1, c2) = (card(in: 0, of: desk), card(in: 1, of: desk), card(in: 2, of: desk))
        write(c1, in: &desk)
        desk.apply(.move(.card(c0), to: slot(13)))
        desk.apply(.move(.card(c2), to: .free(GridPoint(x: 0.7, y: 0.1))))   // over cell 3
        XCTAssertNil(spread(&desk))
        XCTAssertEqual(desk.popped, [], "the desktop is empty")
        XCTAssertEqual(desk.stack.map(\.id), [id("x"), c1, c2, c0], "they join the bottom in reading order of where they were")
    }

    func testGatherKeepsTheStackOnItsPageCardOrBlank() {
        var desk = desk(stack: ["x", "y"])
        spread(&desk)
        write(card(in: 0, of: desk), in: &desk)
        spread(&desk)
        XCTAssertEqual(shown(desk), "x", "the card it showed")
        spread(&desk)
        desk.apply(.flipStack(.previous))
        spread(&desk)
        XCTAssertEqual(shown(desk), "blank", "or the blank page")
    }

    func testAClickWithSomeOutGathersOnlyThose() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0, 1, 2))
        let c1 = card(in: 1, of: desk)
        write(c1, in: &desk)
        spread(&desk)
        desk.apply(.showStacked(c1))
        desk.apply(.pop)
        XCTAssertEqual(desk.stackFace(hasKey: false).spreadButton, .gather(deletes: false), "one card of the set is out")
        spread(&desk, cells(0, 1, 2))
        XCTAssertEqual(desk.popped, [], "the click gathers it")
        XCTAssertEqual(desk.stack.count, 4, "and brings nothing out")
    }

    func testSpreadAgainPutsEachCardBackAtItsExactPlaceFreeOrSnapped() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0, 1, 2))
        let (c0, c1) = (card(in: 0, of: desk), card(in: 1, of: desk))
        write(c0, in: &desk)
        let spot = GridPoint(x: 0.47, y: 0.71)
        desk.apply(.move(.card(c0), to: .free(spot)))
        desk.apply(.move(.card(c1), to: slot(13)))
        let places = out(desk)
        spread(&desk, cells(0, 1, 2))
        XCTAssertNil(spread(&desk, cells(0, 1, 2)), "putting cards back makes no card to focus")
        XCTAssertEqual(out(desk), places, "each is back exactly where it was")
        XCTAssertEqual(desk.stack.map(\.id), [id("x")])
    }

    func testATakenHomeLeavesTheCardStackedInTheSetAndALaterSpreadTriesAgain() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0, 1))
        let (c0, c1) = (card(in: 0, of: desk), card(in: 1, of: desk))
        write(c0, in: &desk)
        spread(&desk)
        let blocker = desk.apply(.new(at: now.addingTimeInterval(60)))!
        XCTAssertEqual(desk.place(of: .card(blocker)), slot(0), "New takes c0's cell")
        spread(&desk, cells(0, 1))
        XCTAssertEqual(desk.place(of: .card(c1)), slot(1), "c1 comes back")
        XCTAssertNil(desk.place(of: .card(c0)), "c0 stays in the stack")
        XCTAssertEqual(desk.spreadSet?.contains(c0), true, "still in the set")
        desk.apply(.move(.card(blocker), to: slot(13)))
        spread(&desk, cells(0, 1))
        spread(&desk, cells(0, 1))
        XCTAssertEqual(desk.place(of: .card(c0)), slot(0), "a later Spread brings it back")
    }

    func testReturnToStackOnASetCardRemembersItsPlaceAndKeepsItInTheSet() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0))
        let c0 = card(in: 0, of: desk)
        let spot = GridPoint(x: 0.47, y: 0.71)
        desk.apply(.move(.card(c0), to: .free(spot)))
        desk.apply(.returnToStack(c0))
        XCTAssertEqual(desk.stack.first?.id, c0, "Return to stack still puts it on top")
        XCTAssertEqual(desk.spreadSet?.homes, [c0: .free(spot)], "and it stays in the set, remembering where it was")
        spread(&desk, cells(0))
        XCTAssertEqual(desk.place(of: .card(c0)), .free(spot), "Spread puts it back there")
    }

    func testReturnToStackOnAnOrdinaryCardStillForgets() {
        var desk = desk(popped: [("a", slot(13))], stack: ["s1"], homes: [("s1", slot(1))])
        desk.apply(.returnToStack(id("a")))
        desk.apply(.pop)
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(0), "a later Pop takes the first free slot")
        XCTAssertEqual(desk.spreadSet?.homes, [id("s1"): slot(1)], "and the set is as it was")
    }

    func testPoppingASetCardByHandThenGatheringRemembersTheNewPlace() {
        var desk = desk()
        spread(&desk, cells(0))
        let c0 = card(in: 0, of: desk)
        write(c0, in: &desk)
        spread(&desk)
        let blocker = desk.apply(.new(at: now.addingTimeInterval(60)))!
        desk.apply(.showStacked(c0))
        desk.apply(.pop)
        XCTAssertEqual(desk.place(of: .card(c0)), slot(1), "Pop takes the first free slot")
        spread(&desk, cells(0))
        desk.apply(.delete(blocker))
        spread(&desk, cells(0))
        XCTAssertEqual(desk.place(of: .card(c0)), slot(1), "Spread brings it back where it last was, not to its cell")
    }

    func testChangedCellsMoveTheSetInReadingOrderAtTheNextSpreadNotTheGather() {
        var desk = desk()
        spread(&desk, cells(0, 1, 2))
        let made = [0, 1, 2].map { card(in: $0, of: desk) }
        write(made[0], in: &desk)
        spread(&desk, cells(10, 11, 12))
        XCTAssertEqual(desk.popped, [], "a click with a card out gathers, whatever the cells")
        XCTAssertEqual(desk.spreadSet?.cells, cells(0, 1, 2), "and the set is not moved yet")
        spread(&desk, cells(10, 11, 12))
        XCTAssertEqual([10, 11, 12].map { card(in: $0, of: desk) }, made, "the card from the first old place goes to the first new cell")
        XCTAssertEqual(desk.spreadSet?.cells, cells(10, 11, 12))
    }

    func testMoreCellsThanCardsFillsTheExtrasWithNewSetCards() {
        var desk = desk()
        spread(&desk, cells(0, 1))
        let made = [0, 1].map { card(in: $0, of: desk) }
        write(made[0], in: &desk)
        spread(&desk)
        let first = spread(&desk, cells(0, 1, 2, 3))
        XCTAssertEqual([0, 1].map { card(in: $0, of: desk) }, made, "the old cards keep their order")
        XCTAssertEqual(first, card(in: 2, of: desk), "a new card fills the first extra cell, and it is the one to focus")
        XCTAssertEqual(desk.popped.map(\.place), [0, 1, 2, 3].map(slot))
        XCTAssertEqual(desk.spreadSet?.homes, out(desk), "every card is in the set")
    }

    func testFewerCellsThanCardsLetsTheLastCardsGoAsOrdinaryCards() {
        var desk = desk()
        spread(&desk)
        let made = [0, 1, 2, 5, 6, 7].map { card(in: $0, of: desk) }
        write(made[5], in: &desk)
        spread(&desk)
        spread(&desk, cells(10, 11))
        XCTAssertEqual([10, 11].map { card(in: $0, of: desk) }, Array(made.prefix(2)), "the first two in reading order come out")
        XCTAssertEqual(desk.stack.map(\.id), Array(made.dropFirst(2)), "the rest stay in the stack")
        XCTAssertEqual(desk.spreadSet?.homes.keys.sorted(), made.prefix(2).sorted(), "as ordinary cards")
    }

    func testFreshSendsTheOldSetsDesktopCardsToTheBottomAndMakesANewSet() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0, 1))
        let (c0, c1) = (card(in: 0, of: desk), card(in: 1, of: desk))
        desk.apply(.move(.card(c0), to: slot(13)))
        let first = spread(&desk, cells(2, 3), fresh: true)
        XCTAssertEqual(desk.stack.map(\.id), [id("x"), c1, c0], "the old set's cards go to the bottom in reading order")
        XCTAssertEqual(desk.popped.map(\.place), [slot(2), slot(3)], "new cards fill the cells")
        XCTAssertEqual(first, desk.popped.first?.card.id)
        XCTAssertEqual(desk.spreadSet?.homes, out(desk), "the set is only the new cards")
    }

    func testFreshThatCanPlaceNothingChangesNothing() {
        var desk = desk()
        spread(&desk, cells(0))
        let before = desk
        XCTAssertNil(spread(&desk, .empty, fresh: true))
        XCTAssertEqual(desk, before, "the old set's card stays out and the set stays")
    }

    func testDeletingEveryCardInTheSetMakesTheNextClickFresh() {
        var desk = desk()
        spread(&desk, cells(0, 1))
        let made = [0, 1].map { card(in: $0, of: desk) }
        desk.apply(.delete(made[0]))
        XCTAssertEqual(desk.spreadSet?.homes.keys.sorted(), [made[1]], "a deleted card leaves the set")
        desk.apply(.delete(made[1]))
        XCTAssertNil(desk.spreadSet, "with its last card gone, there is no set")
        XCTAssertNotNil(spread(&desk, cells(0, 1)), "so the next click makes new cards")
        XCTAssertEqual(desk.popped.map(\.place), [slot(0), slot(1)])
    }

    // MARK: A set with no text is deleted at Gather

    func testAClickOnASetWithNothingWrittenDeletesEveryCardAndEndsTheSet() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0, 1, 2))
        let (c0, c2) = (card(in: 0, of: desk), card(in: 2, of: desk))
        desk.apply(.move(.card(c0), to: .free(GridPoint(x: 0.47, y: 0.71))))
        desk.apply(.returnToStack(c2))
        XCTAssertNil(spread(&desk), "no card comes out, so none gets the cursor")
        XCTAssertEqual(desk.popped, [], "the desktop cards are gone")
        XCTAssertEqual(desk.stack.map(\.id), [id("x")], "the stacked one too, and a card outside the set stays")
        XCTAssertNil(desk.spreadSet, "the set ended with its last card")
        XCTAssertNotNil(spread(&desk, cells(0, 1)), "so the next click makes a fresh set")
        XCTAssertEqual(desk.popped.map(\.place), [slot(0), slot(1)])
        XCTAssertEqual(desk.spreadSet?.homes, out(desk), "of the new cards only")
    }

    func testOneWrittenCardAnywhereInTheSetKeepsEveryEmptyOneAndGathersAsToday() {
        for written in [0, 1] {
            var desk = desk(stack: ["x"])
            spread(&desk, cells(0, 1, 2))
            let made = [0, 1, 2].map { card(in: $0, of: desk) }
            write(made[1], in: &desk)
            if written == 1 { desk.apply(.returnToStack(made[1])) }   // the text is in the stack
            XCTAssertNil(spread(&desk))
            XCTAssertEqual(desk.popped, [], "the set's desktop cards are gathered")
            XCTAssertEqual(Set(desk.stack.map(\.id)), Set([id("x")] + made), "and every empty card is kept")
            XCTAssertEqual(desk.spreadSet?.homes.keys.sorted(), made.sorted(), "in the set")
        }
    }

    func testACardTypedInAndClearedCountsAsEmpty() {
        let cleared: [Note] = [.blank, Note(header: " ", body: [Line(kind: .todo(done: true), runs: [])]),
                               Note(header: "", body: [Line(kind: .bullet, runs: [Run(text: " ")])])]
        for note in cleared {
            var desk = desk()
            spread(&desk, cells(0, 1))
            let (c0, c1) = (card(in: 0, of: desk), card(in: 1, of: desk))
            write(c0, in: &desk)
            write(c1, in: &desk)
            desk.apply(.edit(c0, note))
            desk.apply(.edit(c1, .blank))
            spread(&desk)
            XCTAssertEqual(desk.allCards, [], "nothing is left of a set that was typed in and cleared")
        }
    }

    func testTextBelowAnEmptyHeaderCountsAsWritten() {
        var desk = desk()
        spread(&desk, cells(0, 1))
        desk.apply(.edit(card(in: 1, of: desk), Note(header: "", body: [Line(runs: [Run(text: "the body")])])))
        spread(&desk)
        XCTAssertEqual(desk.stack.count, 2, "gathered, not deleted")
    }

    func testAFreshClickNeverDeletesAnEmptySet() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0, 1, 2))
        let made = [0, 1, 2].map { card(in: $0, of: desk) }
        desk.apply(.returnToStack(made[2]))
        spread(&desk, cells(5, 6), fresh: true)
        XCTAssertEqual(desk.stack.map(\.id).filter(made.contains).sorted(), made.sorted(), "every old card is stacked, as an ordinary card")
        XCTAssertEqual(desk.popped.count, 2, "beside the new set")
        XCTAssertEqual(desk.spreadSet?.homes, out(desk))
    }

    func testDeletingAnEmptySetKeepsTheStackOnItsPage() {
        var desk = desk(stack: ["x", "y"])
        spread(&desk, cells(0, 1))
        spread(&desk)
        XCTAssertEqual(shown(desk), "x", "the card it showed")

        spread(&desk, cells(0, 1))
        let returned = card(in: 1, of: desk)
        desk.apply(.returnToStack(returned))
        XCTAssertEqual(shown(desk), returned.rawValue, "Return to stack shows the card it returned")
        spread(&desk)
        XCTAssertEqual(shown(desk), "x", "a shown card that is deleted gives the page to the card under it")

        spread(&desk, cells(0, 1))
        desk.apply(.flipStack(.previous))
        XCTAssertEqual(shown(desk), "blank")
        spread(&desk)
        XCTAssertEqual(shown(desk), "blank", "the blank page stays")
        XCTAssertEqual(desk.stack.map(\.id), [id("x"), id("y")])
    }

    func testDeletingTouchesNothingOutsideTheSet() {
        var desk = desk(stack: ["x"])
        spread(&desk, cells(0, 1))
        let blank = desk.apply(.new(at: now.addingTimeInterval(60)))!
        desk.apply(.move(.stack, to: slot(13)))
        desk.apply(.setClarity(true))
        spread(&desk)
        XCTAssertEqual(desk.allCards.map(\.id).sorted(), [blank, id("x")].sorted(), "another empty card is not in the set")
        XCTAssertEqual(desk.place(of: .card(blank)), slot(2), "and it stays where it is")
        XCTAssertEqual(desk.stackPlace, slot(13))
        XCTAssertTrue(desk.clarity, "Clarity stays as it was")
    }

    func testNewCardsTurnClarityOffAndPuttingBackLeavesIt() {
        var desk = desk(clarity: true)
        spread(&desk)
        XCTAssertFalse(desk.clarity, "new cards open expanded, as New's do")
        write(card(in: 0, of: desk), in: &desk)
        desk.apply(.setClarity(true))
        spread(&desk)
        XCTAssertTrue(desk.clarity, "Gather leaves Clarity alone")
        spread(&desk)
        XCTAssertTrue(desk.clarity, "and so does putting cards back")
    }

    func testTheFaceSaysGatherWhileASetCardIsOutAndDeleteWhileNoCardOfItHasText() {
        var desk = desk()
        func face() -> SpreadButton { desk.stackFace(hasKey: false).spreadButton }
        XCTAssertEqual(face(), .spread, "no set")
        spread(&desk, cells(0, 1))
        XCTAssertEqual(face(), .gather(deletes: true), "the set is out and empty")
        let (c0, c1) = (card(in: 0, of: desk), card(in: 1, of: desk))
        desk.apply(.returnToStack(c1))
        XCTAssertEqual(face(), .gather(deletes: true), "one card is still out")
        write(c1, in: &desk)
        XCTAssertEqual(face(), .gather(deletes: false), "text in a stacked card of the set counts")
        desk.apply(.edit(c1, .blank))
        XCTAssertEqual(face(), .gather(deletes: true), "and clearing it counts the other way")
        desk.apply(.returnToStack(c0))
        XCTAssertEqual(face(), .spread, "none is out")
    }
}
