import XCTest
@testable import Ideator

final class DeskTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    private func note(_ header: String) -> Note { Note(header: header, body: []) }

    /// A note with enough body to want a summary.
    private func longNote(_ header: String) -> Note {
        Note(header: header, body: ["one", "two"].map { Line(runs: [Run(text: $0)]) })
    }

    private func notes(_ names: [String]) -> [CardID: Note] {
        Dictionary(uniqueKeysWithValues: names.map { (id($0), note($0)) })
    }

    private func deskWithStack(_ names: String...) -> Desk {
        Desk(notes: notes(names), saved: SavedDesk(stack: names.map(id)))
    }

    private func stackOrder(_ desk: Desk) -> [String] { desk.stack.map(\.id.rawValue) }

    /// What the stack shows: a card's name, or "blank" for the blank page.
    private func shown(_ desk: Desk) -> String {
        desk.stackFace(hasKey: false).selected?.id.rawValue ?? "blank"
    }

    /// What the stack shows after each of `count` flips in `direction`.
    private func tour(_ desk: Desk, _ direction: Direction, _ count: Int) -> [String] {
        var desk = desk
        return (0..<count).map { _ in
            desk.apply(.flipStack(direction))
            return shown(desk)
        }
    }

    /// The stack in its default place and a card in each of the other 19 slots.
    private func fullDesktop(stack: String...) -> Desk {
        let slots = Slot.all.filter { $0 != Slot.stackHome }
        let names = slots.map { "p\($0.index)" }
        return Desk(notes: notes(names + stack), saved: SavedDesk(
            placements: zip(slots, names).map { SavedPlacement(slot: $0.index, card: id($1)) },
            stack: stack.map(id)))
    }

    private func slot(_ index: Int) -> Place { .slot(Slot(index: index)!) }

    func testTheLoopShowsEachCardThenTheBlankPageThenWrapsAround() {
        let desk = deskWithStack("a", "b")
        XCTAssertEqual(shown(desk), "a", "the top card shows first")
        XCTAssertEqual(tour(desk, .next, 3), ["b", "blank", "a"], "next goes down, through the blank page, back to the top")
        XCTAssertEqual(tour(desk, .previous, 3), ["blank", "b", "a"], "previous from the top lands on the blank page")
    }

    func testFlippingNextThenPreviousComesBack() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        desk.apply(.flipStack(.next))
        desk.apply(.flipStack(.previous))
        XCTAssertEqual(shown(desk), "b", "previous undoes one next")
        XCTAssertEqual(stackOrder(desk), ["a", "b", "c"], "flipping never reorders the stack")
    }

    func testFlippingWorksWithZeroAndOneCard() {
        let empty = Desk(notes: [:], saved: SavedDesk())
        XCTAssertEqual(tour(empty, .next, 2), ["blank", "blank"], "with no cards the blank page stays")
        XCTAssertEqual(tour(empty, .previous, 2), ["blank", "blank"], "in both directions")
        let single = deskWithStack("a")
        XCTAssertEqual(tour(single, .next, 3), ["blank", "a", "blank"], "one card and the blank page alternate")
        XCTAssertEqual(tour(single, .previous, 2), ["blank", "a"], "in both directions")
    }

    func testPopTakesTheSelectedCardAndTheStackShowsTheNextOne() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        let popped = desk.apply(.pop)
        XCTAssertEqual(popped, id("b"), "after one flip the second card is the one shown, and it pops")
        XCTAssertEqual(popped.flatMap { desk.place(of: .card($0)) }, slot(0), "it lands in the first free slot")
        XCTAssertEqual(stackOrder(desk), ["a", "c"], "the rest keep their order")
        XCTAssertEqual(shown(desk), "c", "the stack shows the card that was under it")
    }

    func testPoppingTheBottomCardShowsTheBlankPage() {
        var desk = deskWithStack("a", "b")
        desk.apply(.flipStack(.next))
        desk.apply(.pop)
        XCTAssertEqual(shown(desk), "blank", "nothing is under the bottom card but the blank page")
    }

    func testPopDoesNothingOnTheBlankPage() {
        var desk = deskWithStack("a")
        desk.apply(.flipStack(.next))
        XCTAssertNil(desk.apply(.pop), "no card arrives")
        XCTAssertEqual(stackOrder(desk), ["a"], "the stack is untouched")
        XCTAssertTrue(desk.poppedCards.isEmpty, "and the desktop too")
    }

    func testPopDoesNothingOnAFullDesktop() {
        var desk = fullDesktop(stack: "x")
        XCTAssertNil(desk.apply(.pop), "no free slot, no pop")
        XCTAssertEqual(shown(desk), "x", "the card stays on the stack")
        XCTAssertTrue(desk.stackFace(hasKey: false).desktopFull, "and the stack says so")
    }

    func testDeletingTheSelectedCardShowsTheOneUnderIt() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        desk.apply(.delete(id("b")))
        XCTAssertEqual(stackOrder(desk), ["a", "c"], "b is gone")
        XCTAssertEqual(shown(desk), "c", "the stack shows the card under it")
    }

    func testDeletingTheBottomCardLeavesTheBlankPageShowing() {
        var desk = deskWithStack("a", "b")
        desk.apply(.flipStack(.next))
        desk.apply(.delete(id("b")))
        XCTAssertEqual(shown(desk), "blank", "the blank page is what comes after the last card")
    }

    func testDeletingACardAboveTheSelectionKeepsTheSelectedCardShowing() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        desk.apply(.delete(id("a")))
        XCTAssertEqual(shown(desk), "b", "the selection follows its card")
    }

    func testWritingOnTheBlankPageMakesABottomCardThatStaysSelected() {
        var desk = deskWithStack("a", "b")
        desk.apply(.flipStack(.previous))
        XCTAssertEqual(shown(desk), "blank", "the blank page shows")
        desk.apply(.writeBlank(note("x"), at: now))
        XCTAssertEqual(stackOrder(desk).count, 3, "a card was made")
        XCTAssertEqual(Array(stackOrder(desk).prefix(2)), ["a", "b"], "at the bottom")
        XCTAssertEqual(desk.selectedCard?.note, note("x"), "it is the one that shows")
        XCTAssertEqual(desk.stackFace(hasKey: false).count, 3, "and the badge counts it")
        desk.apply(.flipStack(.next))
        XCTAssertEqual(shown(desk), "blank", "a fresh blank page follows it")
        XCTAssertEqual(tour(desk, .next, 1), ["a"], "and then the loop starts over")
    }

    func testWritingOnTheBlankPageOfAnEmptyStack() {
        var desk = Desk(notes: [:], saved: SavedDesk())
        desk.apply(.writeBlank(note("x"), at: now))
        XCTAssertEqual(desk.selectedCard?.note, note("x"), "the first card shows as soon as it exists")
        XCTAssertFalse(desk.selectedCard?.collapsed ?? true, "expanded, for the cursor to stay in")
    }

    func testWritingIsIgnoredWhenACardShowsOrTheNoteIsBlank() {
        var desk = deskWithStack("a")
        desk.apply(.writeBlank(note("x"), at: now))
        XCTAssertEqual(stackOrder(desk), ["a"], "a card shows, so there is no blank page to write on")
        desk.apply(.flipStack(.next))
        desk.apply(.writeBlank(.blank, at: now))
        XCTAssertEqual(stackOrder(desk), ["a"], "a blank note creates nothing")
        XCTAssertEqual(shown(desk), "blank", "and the blank page stays")
    }

    func testClarityOnCollapsesStackedCardsToo() {
        var desk = deskWithStack("a", "b")
        desk.apply(.pop)
        desk.apply(.toggleClarity)
        XCTAssertTrue(desk.clarity, "the global flag is on")
        XCTAssertTrue(desk.allCards.allSatisfy(\.collapsed), "popped and stacked cards collapse")
        XCTAssertEqual(desk.stackFace(hasKey: false).selected?.collapsed, true, "the stack shows it collapsed")
        desk.apply(.toggleClarity)
        XCTAssertTrue(desk.allCards.allSatisfy { !$0.collapsed }, "off expands every card")
    }

    func testExpandingOneCardLeavesClarityOn() {
        var desk = deskWithStack("a", "b")
        let popped = desk.apply(.pop)
        desk.apply(.toggleClarity)
        desk.apply(.setCollapsed(popped!, false))
        XCTAssertTrue(desk.clarity, "the global flag stays on")
        XCTAssertFalse(desk.poppedCards[0].collapsed, "the card itself is expanded")
        XCTAssertTrue(desk.stack[0].collapsed, "the others stay collapsed")
    }

    func testAPoppedCardKeepsItsState() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.toggleClarity)
        desk.apply(.setCollapsed(id("a"), false))
        desk.apply(.pop)
        XCTAssertFalse(desk.poppedCards[0].collapsed, "a card expanded on its own stays expanded while clarity is on")
        desk.apply(.pop)
        XCTAssertTrue(desk.poppedCards[1].collapsed, "a card collapsed by clarity comes out collapsed")
        desk.apply(.toggleClarity)
        desk.apply(.setCollapsed(id("c"), true))
        desk.apply(.pop)
        XCTAssertTrue(desk.poppedCards[2].collapsed, "and one collapsed on its own while clarity is off stays collapsed")
    }

    func testNewOnAFullDesktopShowsTheBlankPageAndCreatesNothing() {
        var desk = fullDesktop(stack: "x")
        XCTAssertEqual(shown(desk), "x", "a card shows before")
        XCTAssertNil(desk.apply(.new(at: now)), "the desktop is full, so no card arrives")
        XCTAssertEqual(shown(desk), "blank", "the stack shows its blank page instead")
        XCTAssertEqual(desk.allCards.count, 19 + 1, "and nothing was created")
    }

    func testNewIsRefusedOnceAllNineteenSlotsAreFull() {
        var desk = Desk(notes: [:], saved: SavedDesk())
        for n in 1...19 {
            let arrived = desk.apply(.new(at: now))
            XCTAssertNotNil(arrived, "card \(n) of 19 gets a slot")
        }
        XCTAssertNil(desk.apply(.new(at: now)), "the 20th card is refused")
        XCTAssertEqual(desk.allCards.count, 19, "and is not created")
    }

    func testReturningACardPutsItOnTopOfTheStackAndShowsIt() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        let popped = desk.apply(.pop)!
        desk.apply(.flipStack(.next))
        desk.apply(.returnToStack(popped))
        XCTAssertEqual(stackOrder(desk), ["b", "a", "c"], "the card is on top")
        XCTAssertEqual(shown(desk), "b", "and the stack shows it")
        XCTAssertNil(desk.place(of: .card(popped)), "it left the desktop")
    }

    func testArrangingPutsOneCardAtTheIndexAndTheOthersKeepTheirOrder() {
        var desk = deskWithStack("a", "b", "c", "d")
        desk.apply(.arrange(id("c"), at: 0))
        XCTAssertEqual(stackOrder(desk), ["c", "a", "b", "d"], "c goes to the top and the rest keep their order")
        desk.apply(.arrange(id("c"), at: 3))
        XCTAssertEqual(stackOrder(desk), ["a", "b", "d", "c"], "and to the bottom")
        desk.apply(.arrange(id("d"), at: 1))
        XCTAssertEqual(stackOrder(desk), ["a", "d", "b", "c"], "and into the middle, moving up")
        desk.apply(.arrange(id("a"), at: 2))
        XCTAssertEqual(stackOrder(desk), ["d", "b", "a", "c"], "and into the middle, moving down")
    }

    func testArrangingClampsAnIndexPastEitherEnd() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.arrange(id("b"), at: -4))
        XCTAssertEqual(stackOrder(desk), ["b", "a", "c"], "before the top is the top")
        desk.apply(.arrange(id("b"), at: 99))
        XCTAssertEqual(stackOrder(desk), ["a", "c", "b"], "past the bottom is the bottom")
    }

    func testArrangingKeepsTheSameCardShowingWhereverItGoes() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        XCTAssertEqual(shown(desk), "b", "b shows")
        desk.apply(.arrange(id("a"), at: 2))
        XCTAssertEqual(stackOrder(desk), ["b", "c", "a"], "a went below b")
        XCTAssertEqual(shown(desk), "b", "b still shows, now from the top")
        desk.apply(.arrange(id("b"), at: 2))
        XCTAssertEqual(stackOrder(desk), ["c", "a", "b"], "the shown card itself moved")
        XCTAssertEqual(shown(desk), "b", "and the stack went with it")
        desk.apply(.arrange(id("c"), at: 1))
        XCTAssertEqual(shown(desk), "b", "a card passing over it changes nothing")
    }

    func testArrangingKeepsTheBlankPageShowing() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.previous))
        XCTAssertEqual(shown(desk), "blank", "the blank page shows")
        desk.apply(.arrange(id("c"), at: 0))
        XCTAssertEqual(stackOrder(desk), ["c", "a", "b"], "the card moved")
        XCTAssertEqual(shown(desk), "blank", "and the blank page still shows")
        XCTAssertEqual(tour(desk, .next, 1), ["c"], "its loop is still the whole stack")
    }

    func testArrangingACardThatIsNotStackedOrAlreadyThereChangesNothing() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        let popped = desk.apply(.pop)!
        let before = desk
        desk.apply(.arrange(popped, at: 0))
        XCTAssertEqual(desk, before, "a card on the desktop is not in the arranger's list")
        desk.apply(.arrange(id("ghost"), at: 0))
        XCTAssertEqual(desk, before, "nor is a card that does not exist")
        desk.apply(.arrange(id("c"), at: 1))
        XCTAssertEqual(desk, before, "a move to the card's own place is no move")
        var alone = deskWithStack("a")
        let aloneBefore = alone
        alone.apply(.arrange(id("a"), at: 5))
        XCTAssertEqual(alone, aloneBefore, "a single card has nowhere to go")
    }

    func testArrangingChangesNothingButTheOrder() {
        var desk = fullDesktop(stack: "x", "y", "z")
        desk.apply(.toggleClarity)
        let before = desk
        desk.apply(.arrange(id("z"), at: 0))
        XCTAssertEqual(desk.popped, before.popped, "the desktop is as it was")
        XCTAssertEqual(desk.stackPlace, before.stackPlace, "so is the stack's place")
        XCTAssertEqual(desk.clarity, before.clarity, "and Clarity")
        XCTAssertEqual(desk.stack.sorted { $0.id < $1.id }, before.stack.sorted { $0.id < $1.id },
                       "every stacked card keeps its text, state and summary")
    }

    func testTheArrangedOrderIsWhatTheSidecarSavesAndALaunchReads() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.arrange(id("c"), at: 0))
        XCTAssertEqual(desk.saved.stack, [id("c"), id("a"), id("b")], "the sidecar lists the new order")
        let relaunched = Desk(notes: notes(["a", "b", "c"]), saved: desk.saved)
        XCTAssertEqual(stackOrder(relaunched), ["c", "a", "b"], "a launch reads it back")
        XCTAssertEqual(shown(relaunched), "c", "and shows the new top card")
    }

    func testShowingAStackedCardTurnsTheStackToItWithoutReordering() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.showStacked(id("c")))
        XCTAssertEqual(shown(desk), "c", "the stack shows c")
        XCTAssertEqual(stackOrder(desk), ["a", "b", "c"], "the order is untouched")
        XCTAssertEqual(tour(desk, .next, 2), ["blank", "a"], "and the loop carries on from there")
        desk.apply(.flipStack(.next))
        desk.apply(.showStacked(id("b")))
        XCTAssertEqual(shown(desk), "b", "a card shows from any page, the blank one included")
    }

    func testShowingACardThatIsNotStackedChangesNothing() {
        var desk = deskWithStack("a", "b")
        desk.apply(.flipStack(.next))
        let popped = desk.apply(.pop)!
        let before = desk
        desk.apply(.showStacked(popped))
        XCTAssertEqual(desk, before, "a card on the desktop is not shown by the stack")
        desk.apply(.showStacked(id("ghost")))
        XCTAssertEqual(desk, before, "nor is one that does not exist")
    }

    func testTheFaceListsStackedCardsTopFirstWithTheirTitles() {
        var desk = Desk(notes: [id("a"): note("Alpha"), id("b"): note(""), id("c"): note("Gamma")],
                        saved: SavedDesk(stack: [id("c"), id("a"), id("b")]))
        desk.apply(.flipStack(.next))
        let rows = desk.stackFace(hasKey: false).stacked
        XCTAssertEqual(rows.map(\.id), [id("c"), id("a"), id("b")], "top first")
        XCTAssertEqual(rows.map(\.title), ["Gamma", "Alpha", "Untitled"], "an empty header reads Untitled")
        desk.apply(.pop)
        XCTAssertEqual(desk.stackFace(hasKey: false).stacked.map(\.id), [id("c"), id("b")], "a popped card is not listed")
        desk.apply(.flipStack(.previous))
        desk.apply(.flipStack(.previous))
        XCTAssertEqual(shown(desk), "blank", "the blank page shows")
        XCTAssertEqual(desk.stackFace(hasKey: false).stacked.count, 2, "and has no row")
    }

    func testLaunchShowsTheTopCardOrTheBlankPageWhenEmpty() {
        XCTAssertEqual(shown(deskWithStack("a", "b")), "a", "the top card shows at launch")
        XCTAssertEqual(shown(Desk(notes: [:], saved: SavedDesk())), "blank", "an empty stack shows the blank page")
    }

    func testTheBadgeCountsRealCardsOnly() {
        var desk = deskWithStack("a", "b")
        XCTAssertEqual(desk.stackFace(hasKey: false).count, 2, "two cards")
        desk.apply(.flipStack(.previous))
        XCTAssertEqual(shown(desk), "blank", "the blank page shows")
        XCTAssertEqual(desk.stackFace(hasKey: false).count, 2, "and it is not counted")
    }

    func testSyncingFilesKeepsTheBlankPageShowingWhenFilesJoin() {
        var desk = deskWithStack("a")
        desk.apply(.flipStack(.next))
        desk.apply(.syncFiles(notes(["a", "b", "c"])))
        XCTAssertEqual(stackOrder(desk), ["a", "b", "c"], "new files join the bottom in id order")
        XCTAssertEqual(shown(desk), "blank", "the blank page still shows")
    }

    func testSyncingFilesKeepsTheSelectedCardWhenFilesJoin() {
        var desk = deskWithStack("a", "b")
        desk.apply(.flipStack(.next))
        desk.apply(.syncFiles(notes(["a", "b", "c"])))
        XCTAssertEqual(shown(desk), "b", "the selected card still shows")
    }

    func testSyncingFilesShowsTheNextCardWhenTheSelectedFileGoes() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        desk.apply(.syncFiles(notes(["a", "c"])))
        XCTAssertEqual(shown(desk), "c", "the card under the removed one shows")
        desk.apply(.syncFiles(notes(["a"])))
        XCTAssertEqual(shown(desk), "blank", "and the blank page when it was the bottom one")
    }

    func testFilesThatJoinWhileClarityIsOnComeInCollapsed() {
        var desk = deskWithStack("a")
        desk.apply(.toggleClarity)
        desk.apply(.syncFiles(notes(["a", "b"])))
        XCTAssertTrue(desk.allCards.allSatisfy(\.collapsed), "every card follows the global switch")
    }

    func testRebuildDropsMissingFilesAndAppendsUnknownFilesInIdOrder() {
        let saved = SavedDesk(
            placements: [SavedPlacement(slot: 0, card: id("ghost")), SavedPlacement(slot: 1, card: id("a"))],
            stack: [id("gone"), id("c")])
        let desk = Desk(notes: notes(["a", "b", "c", "d"]), saved: saved)
        XCTAssertNil(desk.place(of: .card(id("ghost"))), "a placement whose file is missing is dropped")
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(1), "a placement whose file exists is kept")
        XCTAssertEqual(stackOrder(desk), ["c", "b", "d"],
                       "a stack entry whose file is missing is dropped; files the sidecar never heard of go last, by id")
    }

    func testSummaryForAnEditedNoteIsDropped() {
        var desk = deskWithStack("a")
        let before = note("a")
        let after = Note(header: "a", body: [Line(runs: [Run(text: "more")])])
        desk.apply(.edit(id("a"), after))
        desk.apply(.storeSummary(id("a"), Summary(source: before.digest, outcome: .text("old"))))
        XCTAssertNil(desk.allCards[0].summary, "a summary of the note as it was before the edit is dropped")
        desk.apply(.storeSummary(id("a"), Summary(source: after.digest, outcome: .text("new"))))
        XCTAssertEqual(desk.allCards[0].summary?.outcome, .text("new"), "a summary of the current note is kept")
    }

    func testForgettingFailedSummariesMakesThoseCardsTryAgainAndKeepsTheTextOnes() {
        let reason = "HTTP 401: invalid x-api-key"
        let outcomes: [(String, Summary.Outcome)] = [
            ("a", .failed(reason: reason)), ("b", .text("kept")), ("c", .failed(reason: reason)), ("d", .text("kept"))]
        var desk = Desk(
            notes: Dictionary(uniqueKeysWithValues: outcomes.map { (id($0.0), longNote($0.0)) }),
            saved: SavedDesk(placements: [SavedPlacement(slot: 0, card: id("a")), SavedPlacement(slot: 1, card: id("b"))],
                             stack: [id("c"), id("d")]))
        for (name, outcome) in outcomes {
            desk.apply(.storeSummary(id(name), Summary(source: longNote(name).digest, outcome: outcome)))
        }
        func face(_ name: String) -> SummaryFace {
            Desk.summaryFace(of: desk.allCards.first { $0.id == id(name) }!, hasKey: true)
        }
        XCTAssertEqual(face("a"), .unavailable(reason: reason), "a failed summary stays for as long as nothing forgets it")
        desk.apply(.forgetFailedSummaries)
        XCTAssertEqual(face("a"), .loading, "a popped card whose summary failed tries again")
        XCTAssertEqual(face("c"), .loading, "so does a stacked one")
        XCTAssertEqual(face("b"), .text("kept"), "a popped card's summary that worked stays")
        XCTAssertEqual(face("d"), .text("kept"), "and so does a stacked one's")
    }

    private func summaryFace(on desk: Desk) -> SummaryFace {
        Desk.summaryFace(of: desk.allCards[0], hasKey: true)
    }

    private func reload(sidecarSummary prompt: Digest) -> Desk {
        let note = longNote("a")
        let saved = SavedDesk(stack: [id("a")], summaries: [
            SavedSummary(card: id("a"), source: note.digest, text: "kept", prompt: prompt)])
        return Desk(notes: [id("a"): note], saved: saved)
    }

    func testASavedSummaryFromTheCurrentPromptSurvivesRelaunch() throws {
        var desk = Desk(notes: [id("a"): longNote("a")], saved: SavedDesk(stack: [id("a")]))
        desk.apply(.storeSummary(id("a"), Summary(source: longNote("a").digest, outcome: .text("kept"))))
        let json = try JSONEncoder().encode(desk.saved)
        let reloaded = Desk(notes: [id("a"): longNote("a")], saved: try JSONDecoder().decode(SavedDesk.self, from: json))
        XCTAssertEqual(summaryFace(on: reloaded), .text("kept"), "a summary the current prompt wrote comes back")
        XCTAssertEqual(summaryFace(on: reload(sidecarSummary: Summary.prompt)), .text("kept"))
    }

    func testASavedSummaryFromAnotherPromptIsDroppedSoTheCardIsWantedAgain() {
        let older = reload(sidecarSummary: Digest(of: "some older prompt"))
        XCTAssertEqual(summaryFace(on: older), .loading, "a stamp of another prompt is not this prompt's summary")
        XCTAssertNil(older.allCards[0].summary, "and the Summarizer sees no summary to keep")
    }
}
