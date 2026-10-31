import XCTest
@testable import Ideator

/// A reader walking the tour: the desk's own rules make every change and the flow only looks, so
/// each test is a story told with real commands and no window.
final class TourFlowWalkTests: XCTestCase {
    private typealias Fixtures = TourDeskFixtures

    /// The desk, what Hide all and Settings hold beside it, and the flow that looks at them.
    private struct Walk {
        var desk: Desk
        var visibility = Visibility.all
        var shortcut = Fixtures.shortcut
        var cells = SpreadCells.standard
        var flow = TourFlow()
        /// The last card a New of the reader's made, as the desk reported it: the test's own answer
        /// to which card is the reader's, never the flow's.
        private(set) var made: CardID?

        init(desk: Desk = Fixtures.desk(stack: ["s"])) { self.desk = desk }

        /// A look, as the session takes one: the flow tells it which card is the reader's.
        var world: TourWorld {
            let world = Fixtures.world(desk, visibility: visibility, shortcut: shortcut, cells: cells)
            flow.inform(world)
            return world
        }
        var stop: Stop? { flow.stop }
        var card: HintCard? { flow.stop?.card(in: world) }
        var title: String? { card?.title.spoken }
        var reader: CardID? { world.readerCard }

        @discardableResult
        mutating func input(_ input: TourInput) -> TourEffect? { flow.apply(input, in: world) }

        mutating func settle() { input(.deskSettled) }

        /// The reader acts: the desk applies the command, then the controller would render and settle.
        mutating func send(_ command: Command) {
            let arrived = desk.apply(command)
            if case .new = command, let arrived { made = arrived }
            settle()
        }

        mutating func hideAll() {
            visibility = .hideAll
            settle()
        }

        mutating func showAll() {
            visibility = .all
            settle()
        }

        // The honest road to each page's first screen, one real action per wait.

        mutating func toPage2() {
            input(.begin(.firstPage))
            input(.next)
        }

        mutating func toPage3() {
            toPage2()
            send(.new(at: Fixtures.now))
            input(.next)
        }

        mutating func toPage4() {
            toPage3()
            hideAll()
            showAll()
            input(.next)
        }

        mutating func toPage5() {
            toPage4()
            send(.returnToStack(made!))
            input(.next)
        }

        mutating func toPage6() {
            toPage5()
            input(.next)
        }
    }

    private func stop(_ phase: TourPhase, _ reading: Reading = .fresh) -> Stop { Stop(phase: phase, reading: reading) }

    // MARK: Page 1 and 2

    func testNewEndsThePlusPhaseAndASecondLookChangesNothing() {
        var walk = Walk()
        walk.input(.begin(.firstPage))
        XCTAssertEqual(walk.stop, stop(.stack))

        walk.input(.next)
        XCTAssertEqual(walk.stop, stop(.clickNew))

        walk.send(.new(at: Fixtures.now))
        XCTAssertEqual(walk.stop, stop(.typeIn, .after(.new)))

        let settled = walk.flow
        walk.settle()
        walk.settle()
        XCTAssertEqual(walk.flow, settled, "looking again at the same world is a no-op")
    }

    func testACardAlreadyOnTheDeskWhenTheTourStartsIsNotNew() {
        var walk = Walk(desk: Fixtures.desk(popped: [("a", Fixtures.slot(0))]))
        walk.toPage2()

        walk.settle()

        XCTAssertEqual(walk.stop, stop(.clickNew), "the page waits for the reader to click New, not for what was there")
    }

    func testNothingBeforeTheStartAndNothingAfterTheEndMovesTheTour() {
        var walk = Walk()
        XCTAssertNil(walk.input(.next))
        walk.input(.happened(.space))
        walk.settle()
        XCTAssertNil(walk.stop, "no tour is running until a start")

        walk.input(.begin(.firstPage))
        walk.input(.skip)
        XCTAssertEqual(walk.input(.finish), .openNotesFolder)
        walk.input(.next)
        walk.input(.back)
        walk.settle()
        XCTAssertNil(walk.stop, "page 9's button ends the tour and nothing restarts it")
    }

    func testBeginningAgainRestartsAtThePageItIsGiven() {
        var walk = Walk()
        walk.toPage3()

        walk.input(.begin(.firstPage))
        XCTAssertEqual(walk.stop, stop(.stack))

        walk.input(.begin(.lastPage))
        XCTAssertEqual(walk.stop, stop(.done), "a background start goes straight to the last page")
    }

    func testNextDoesNothingWhereThePageWaitsForTheReader() {
        var walk = Walk()
        walk.toPage2()
        let waiting = walk.flow

        walk.input(.next)

        XCTAssertEqual(walk.flow, waiting, "the footer has no Next there, and neither has the flow")
    }

    func testTheTypeInPageSaysWhatIsTrueWhenTheReadersCardIsGone() {
        var walk = Walk()
        walk.toPage3()
        walk.input(.back)
        XCTAssertEqual(walk.stop, stop(.typeIn), "Back lands on page 2's finished phase")
        XCTAssertEqual(walk.title, "Type or paste into your card")

        walk.send(.delete(walk.made!))
        XCTAssertEqual(walk.title, "Each New makes one card", "read live, never cached")
    }

    // MARK: A card the reader did not make

    private let older = Fixtures.id("old")

    /// An owner who updated: a note of theirs is out at slot 0 when the tour begins.
    private func ownerWithAnOlderCard() -> Walk {
        Walk(desk: Fixtures.desk(popped: [("old", Fixtures.slot(0))], stack: ["s"]))
    }

    private func face(at place: Place) -> CGRect { Surfaces.face(of: Fixtures.grid.frame(of: place)) }

    /// The face the panel would sit beside for the current phase, with no live window to measure.
    private func readerFace(_ walk: Walk) -> CGRect? {
        Surfaces(walk.world, aim: walk.stop!.phase.script.aim, measure: { _ in nil }).readerFace
    }

    func testAnOlderCardIsNotTheReadersSoPage2KeepsWaitingForNew() {
        var walk = ownerWithAnOlderCard()
        walk.toPage2()
        XCTAssertEqual(walk.stop, stop(.clickNew))
        XCTAssertNil(walk.reader, "the card that was out first is not the reader's")

        walk.send(.edit(older, Note(header: "typed", body: [])))
        walk.send(.returnToStack(older))

        XCTAssertEqual(walk.stop, stop(.clickNew), "nothing the older card does is New")
        XCTAssertNil(walk.reader)
    }

    func testNewMakesTheReadersCardAndPage2SitsBesideItNotBesideTheOlderOne() {
        var walk = ownerWithAnOlderCard()
        walk.toPage2()

        walk.send(.new(at: Fixtures.now))

        let made = walk.made!
        XCTAssertEqual(walk.desk.place(of: .card(made)), Fixtures.slot(1), "sanity: the first free slot after the older card's")
        XCTAssertEqual(walk.stop, stop(.typeIn, .after(.new)))
        XCTAssertEqual(walk.reader, made)
        XCTAssertEqual(walk.title, "Type or paste into your card")
        XCTAssertEqual(walk.stop?.phase.script.aim.anchor, .readerCard)
        XCTAssertEqual(readerFace(walk), face(at: Fixtures.slot(1)))
        XCTAssertNotEqual(readerFace(walk), face(at: Fixtures.slot(0)))
    }

    func testPage4RingsTheCardNewMadeAndReturningTheOlderOneChangesNothing() {
        var walk = ownerWithAnOlderCard()
        walk.toPage4()
        XCTAssertEqual(walk.stop, stop(.clickReturn), "the card New made is out, so the ask is on")
        XCTAssertEqual(walk.reader, walk.made)
        XCTAssertEqual(readerFace(walk), face(at: Fixtures.slot(1)), "the hover corner is on the new card")

        walk.send(.returnToStack(older))
        XCTAssertEqual(walk.stop, stop(.clickReturn), "the older card is not what the page waits for")
        XCTAssertEqual(walk.reader, walk.made)

        walk.send(.returnToStack(walk.made!))
        XCTAssertEqual(walk.stop, stop(.afterReturn, .after(.returned)))
        XCTAssertEqual(walk.title, "Your card is in the stack")
    }

    func testDeletingTheCardNewMadeEndsPage4WithDeletedAndTheOlderCardStays() {
        var walk = ownerWithAnOlderCard()
        walk.toPage4()

        walk.send(.delete(walk.made!))

        XCTAssertEqual(walk.stop, stop(.afterReturn, .after(.deleted)))
        XCTAssertEqual(walk.title, "Your card is deleted")
        XCTAssertEqual(walk.desk.popped.map(\.card.id), [older])
    }

    func testPage4IsSkippedWhenOnlyAnOlderCardIsOutByTheTimeNextIsPressed() {
        var walk = ownerWithAnOlderCard()
        walk.toPage3()
        walk.send(.returnToStack(walk.made!))
        XCTAssertEqual(walk.desk.popped.map(\.card.id), [older], "sanity: a card is still out")
        walk.hideAll()
        walk.showAll()

        walk.input(.next)

        XCTAssertEqual(walk.stop, stop(.afterReturn), "that card is not the reader's to return")
        XCTAssertEqual(walk.title, "The stack holds your cards")
    }

    func testHideAllAndShowAllKeepTheReadersCard() {
        var walk = Walk()
        walk.toPage3()

        walk.hideAll()
        XCTAssertEqual(walk.reader, walk.made, "Hide all orders the windows out; the card is still on the desk")

        walk.showAll()
        XCTAssertEqual(walk.reader, walk.made)
    }

    func testSeveralNewCardsInOneLookGiveTheReadersCardToTheEarliestInReadingOrder() {
        var walk = ownerWithAnOlderCard()
        walk.toPage2()

        walk.desk = Fixtures.desk(popped: [("old", Fixtures.slot(0)), ("late", Fixtures.slot(6)), ("early", Fixtures.slot(1))],
                                  stack: ["s"])
        walk.settle()

        XCTAssertEqual(walk.stop, stop(.typeIn, .after(.new)))
        XCTAssertEqual(walk.reader, Fixtures.id("early"))
    }

    func testPage4WaitsForTheNewestCardNewMadeAndNotForAnEarlierOne() {
        var walk = Walk()
        walk.toPage4()
        let first = walk.made!

        walk.send(.new(at: Fixtures.now.addingTimeInterval(60)))
        let newest = walk.made!
        XCTAssertNotEqual(newest, first)
        XCTAssertEqual(walk.reader, newest)

        walk.send(.returnToStack(first))
        XCTAssertEqual(walk.stop, stop(.clickReturn), "the card the page points at is still out")

        walk.send(.returnToStack(newest))
        XCTAssertEqual(walk.stop, stop(.afterReturn, .after(.returned)))
    }

    func testAPopOrAnAIToolsCardIsNotNewSoPage2KeepsWaiting() {
        var walk = Walk(desk: Fixtures.desk(stack: ["s", "t"]))
        walk.toPage2()

        walk.send(.pop)
        XCTAssertEqual(walk.stop, stop(.clickNew), "a Pop moves a card out; it makes none")
        walk.send(.addFromTool(Note(header: "from a tool", body: []), at: Fixtures.now, to: .top, typing: false))

        XCTAssertEqual(walk.stop, stop(.clickNew), "an AI tool's card lands in the stack")
        XCTAssertNil(walk.reader)
    }

    func testAStartedTourForgetsTheReadersCardOfTheLastRun() {
        var walk = Walk()
        walk.toPage3()
        let lastRun = walk.made!

        walk.input(.begin(.firstPage))
        XCTAssertEqual(walk.desk.popped.map(\.card.id), [lastRun], "sanity: the card is still out")
        XCTAssertNil(walk.reader, "Show the Tour starts over: that card is not this run's")

        walk.input(.next)
        walk.send(.new(at: Fixtures.now.addingTimeInterval(60)))
        XCTAssertNotEqual(walk.made, lastRun)
        XCTAssertEqual(walk.reader, walk.made)
    }

    // MARK: A full desktop

    func testOnAFullDesktopPage2HasNoWaitAndPage4IsSkipped() {
        var walk = Walk(desk: Fixtures.fullDesk())
        XCTAssertNil(walk.desk.firstFreeSlot, "sanity: New would beep and make no card")

        walk.input(.begin(.firstPage))
        walk.input(.next)

        XCTAssertEqual(walk.stop, stop(.typeIn), "no card can come, so the page does not wait for one")
        XCTAssertEqual(walk.title, "Each New makes one card")
        XCTAssertEqual(walk.card?.footer, .backAndNext)

        walk.input(.next)
        XCTAssertEqual(walk.stop, stop(.clickHide))
        walk.input(.back)
        XCTAssertEqual(walk.stop, stop(.typeIn), "Back lands on the same neutral text")

        walk.input(.next)
        walk.hideAll()
        walk.showAll()
        walk.input(.next)
        XCTAssertEqual(walk.stop, stop(.afterReturn), "none of the 19 cards is one the reader made")
    }

    func testPage2StopsWaitingOnceTheDesktopFillsUp() {
        var walk = Walk(desk: Fixtures.desk(stack: (0..<19).map { "s\($0)" }))
        walk.toPage2()
        for _ in 0..<18 { walk.send(.pop) }
        XCTAssertEqual(walk.stop, stop(.clickNew), "one cell is free, so New would make a card")

        walk.send(.pop)

        XCTAssertNil(walk.desk.firstFreeSlot, "sanity: the desktop is full")
        XCTAssertEqual(walk.stop, stop(.typeIn))
        XCTAssertEqual(walk.title, "Each New makes one card")
        XCTAssertEqual(walk.card?.footer, .backAndNext)
    }

    // MARK: Page 3, Hide and Show

    func testHideThenShowWalkPage3EvenWhenTheShortcutDidIt() {
        var walk = Walk()
        walk.toPage3()
        XCTAssertEqual(walk.stop, stop(.clickHide))

        walk.hideAll()
        XCTAssertEqual(walk.stop, stop(.clickShow, .after(.hidden)))

        walk.hideAll()
        XCTAssertEqual(walk.stop, stop(.clickShow, .after(.hidden)), "Hide all while hidden is nothing")

        walk.showAll()
        XCTAssertEqual(walk.stop, stop(.allBack, .after(.shown)))

        walk.showAll()
        XCTAssertEqual(walk.stop, stop(.allBack, .after(.shown)), "Show all on a shown desk is nothing")
    }

    func testPage3NamesTheShortcutTheWorldHasRightNow() {
        var walk = Walk()
        walk.toPage3()
        XCTAssertEqual(walk.card?.body.spoken,
                       "Your card and the stack's page go away; only the ribbon stays. ⌃⌥I does the same from any app.")

        walk.shortcut = ShortcutReading(display: "⌃⌥K", works: false)
        XCTAssertEqual(walk.card?.body.spoken,
                       "Your card and the stack's page go away; only the ribbon stays. "
                           + "Ideator couldn't claim ⌃⌥K, so there is no shortcut yet; choose one in Settings.",
                       "Settings changes it with no notification, so every look reads it again")
    }

    // MARK: Page 4, Return or Delete

    func testReturningTheReadersCardIsReturnedAndDeletingItIsDeleted() {
        var returned = Walk()
        returned.toPage4()
        XCTAssertEqual(returned.stop, stop(.clickReturn))
        returned.send(.returnToStack(returned.made!))
        XCTAssertEqual(returned.stop, stop(.afterReturn, .after(.returned)))
        XCTAssertEqual(returned.title, "Your card is in the stack")

        var deleted = Walk()
        deleted.toPage4()
        deleted.send(.delete(deleted.made!))
        XCTAssertEqual(deleted.stop, stop(.afterReturn, .after(.deleted)))
        XCTAssertEqual(deleted.title, "Your card is deleted")
        XCTAssertTrue(deleted.card!.body.spoken.hasPrefix("Cards you return instead stay in the stack."))
    }

    func testPage4IsSkippedWhenTheReadersCardIsGoneByTheTimeNextIsPressed() {
        var walk = Walk()
        walk.toPage3()
        walk.send(.returnToStack(walk.made!))   // while page 3 is still asking for Hide
        walk.hideAll()
        walk.showAll()
        XCTAssertEqual(walk.stop, stop(.allBack, .after(.shown)))

        walk.input(.next)

        XCTAssertEqual(walk.stop, stop(.afterReturn), "no card to return: the stack text, neutral")
        XCTAssertEqual(walk.title, "The stack holds your cards")
    }

    func testTheHoverButtonsAreHeldOnlyWhilePage4Asks() {
        var walk = Walk()
        walk.toPage4()
        XCTAssertTrue(walk.stop!.phase.script.aim.showsHoverButtons)
        XCTAssertEqual(walk.reader, walk.made)

        walk.send(.returnToStack(walk.made!))
        XCTAssertFalse(walk.stop!.phase.script.aim.showsHoverButtons)
    }

    // MARK: Page 5

    func testPage5AnswersSpaceAppAndCardsInPlaceAndNextClearsIt() {
        var walk = Walk()
        walk.toPage5()
        XCTAssertEqual(walk.stop, stop(.follow))
        XCTAssertEqual(walk.title, "Your cards follow you")

        walk.input(.happened(.space))
        XCTAssertEqual(walk.stop, stop(.follow, .reacted(.space)))
        XCTAssertEqual(walk.title, "Still here on this Space")

        walk.input(.happened(.appFront))
        XCTAssertEqual(walk.title, "Click any card to come forward")

        walk.input(.happened(.cardsFront))
        XCTAssertEqual(walk.title, "Back in front")
        XCTAssertEqual(walk.card?.footer, .backAndNext, "Next always")

        walk.input(.next)
        XCTAssertEqual(walk.stop?.reading, .fresh)
        XCTAssertEqual(walk.stop?.phase.page, 6)
    }

    func testSystemEventsOnOtherPagesAreIgnored() {
        var walk = Walk()
        walk.toPage3()
        let waiting = walk.flow

        for event in [TourEvent.space, .appFront, .cardsFront] { walk.input(.happened(event)) }

        XCTAssertEqual(walk.flow, waiting)
    }

    func testBackToPage5ReadsNeutralAgain() {
        var walk = Walk()
        walk.toPage6()
        walk.input(.back)
        XCTAssertEqual(walk.stop, stop(.follow))

        walk.input(.happened(.space))
        walk.input(.next)
        walk.input(.back)
        XCTAssertEqual(walk.stop, stop(.follow), "the reaction does not outlive the visit")
    }

    // MARK: Page 6, Spread

    func testSpreadThenGatherWithTextEndsOnThePutAwayText() {
        var walk = Walk()
        walk.toPage6()
        XCTAssertEqual(walk.stop, stop(.clickSpread))
        XCTAssertEqual(walk.title, "Click Spread: 6 blank cards")
        XCTAssertTrue(walk.card!.isOptional)

        walk.send(.spread(.standard, fresh: false, at: Fixtures.now))
        XCTAssertEqual(walk.stop, stop(.clickGather, .after(.spreadOut)))
        XCTAssertFalse(walk.card!.isOptional, "once Spread was clicked, the later phases are not optional")

        let first = walk.desk.popped.first!.card.id
        walk.send(.edit(first, Note(header: "kept", body: [])))
        walk.send(.spread(.standard, fresh: false, at: Fixtures.now))

        XCTAssertEqual(walk.stop, stop(.afterGather, .after(.gathered)))
        XCTAssertEqual(walk.title, "In the stack, back in one click")
    }

    func testSpreadThenGatherAllBlankEndsOnGoneNothingWasKept() {
        var walk = Walk()
        walk.toPage6()
        walk.send(.spread(.standard, fresh: false, at: Fixtures.now))

        walk.send(.spread(.standard, fresh: false, at: Fixtures.now))

        XCTAssertEqual(walk.stop, stop(.afterGather, .after(.vanished)))
        XCTAssertEqual(walk.title, "Gone, nothing was kept")
    }

    func testASetComingBackOutOfTheStackEndsPage6sFirstWaitToo() {
        let homes: [(String, Place)] = [("g1", Fixtures.slot(0)), ("g2", Fixtures.slot(1))]
        var walk = Walk(desk: Fixtures.desk(stack: ["g1", "g2"], set: (cells: .standard, homes: homes)))
        walk.toPage6()
        XCTAssertEqual(walk.stop, stop(.clickSpread))

        walk.send(.spread(.standard, fresh: false, at: Fixtures.now))

        XCTAssertEqual(walk.stop, stop(.clickGather, .after(.spreadOut)))
    }

    func testAFinishedGatherWaitProceedsEvenIfSettingsHaveSinceTickedNothing() {
        var walk = Walk()
        walk.toPage6()
        walk.send(.spread(.standard, fresh: false, at: Fixtures.now))
        walk.cells = .empty   // the reader unticked every cell in Settings

        walk.send(.spread(.standard, fresh: false, at: Fixtures.now))

        XCTAssertEqual(walk.stop, stop(.afterGather, .after(.vanished)), "a wait that ended is not asked again whether it may")
    }

    func testSpreadIsOffWhenNothingIsTickedAndFollowsSettingsLive() {
        var walk = Walk()
        walk.cells = .empty
        walk.toPage6()
        XCTAssertEqual(walk.stop, stop(.spreadOff))
        XCTAssertEqual(walk.title, "Spread is off")
        XCTAssertEqual(walk.card?.footer, .backAndNext)
        XCTAssertFalse(walk.card!.isOptional)

        walk.cells = .standard
        walk.settle()
        XCTAssertEqual(walk.stop, stop(.clickSpread), "ticked in Settings: the ask comes back")
        XCTAssertEqual(walk.card?.footer, .backOnly)

        walk.cells = .empty
        walk.settle()
        XCTAssertEqual(walk.stop, stop(.spreadOff))
    }

    func testPage6IsOneNextWhenTheButtonWouldDoNothing() {
        var walk = Walk(desk: Fixtures.desk(stack: ["s"]))
        walk.cells = Fixtures.cells(0)
        walk.toPage5()
        walk.desk = Fixtures.desk(popped: [("t", Fixtures.slot(0))], stack: ["s"])   // the one ticked cell is taken
        walk.input(.next)
        XCTAssertEqual(walk.stop, stop(.spreadOff))
        XCTAssertEqual(walk.title, "Spread needs free cells")

        walk.input(.next)
        XCTAssertEqual(walk.stop?.phase, .clarity)
        walk.input(.back)
        XCTAssertEqual(walk.stop, stop(.spreadOff), "Back lands on the same single page")
    }

    func testNextFromTheOffPageLeavesEvenIfSettingsTickedCellsSinceTheLastLook() {
        var walk = Walk()
        walk.cells = .empty
        walk.toPage6()
        walk.cells = .standard   // no settle: Settings sends no notification

        walk.input(.next)

        XCTAssertEqual(walk.stop?.phase, .clarity)
    }

    // MARK: Back, Skip and the last page

    func testBackLandsOnThePreviousPagesFinishedNeutralPhaseFromAWaitToo() {
        var walk = Walk()
        walk.toPage6()
        walk.send(.spread(.standard, fresh: false, at: Fixtures.now))
        XCTAssertEqual(walk.stop?.phase, .clickGather)

        walk.input(.back)
        XCTAssertEqual(walk.stop, stop(.follow), "from a wait on page 6 to page 5")
        walk.input(.back)
        XCTAssertEqual(walk.stop, stop(.afterReturn), "page 4 lands on its finished phase, not on the ask for a Return")
        XCTAssertEqual(walk.title, "The stack holds your cards", "with its neutral text, whatever happened the first time")
    }

    func testBackWalksTheEarlierPagesToTheirFinishedPhases() {
        var walk = Walk()
        walk.toPage6()

        var seen: [TourPhase] = []
        while true {
            seen.append(walk.stop!.phase)
            if walk.input(.back) == .showWelcome { break }
        }

        XCTAssertEqual(seen, [.clickSpread, .follow, .afterReturn, .allBack, .typeIn, .stack])
        XCTAssertNil(walk.stop, "Back from page 1 hands over to the welcome")
        XCTAssertNil(walk.input(.next), "and the tour is over until the welcome starts it again")
    }

    func testBackFromPage1ShowsTheWelcomeAndBeginStartsPage1Again() {
        var walk = Walk()
        walk.input(.begin(.firstPage))

        XCTAssertEqual(walk.input(.back), .showWelcome)
        XCTAssertNil(walk.stop)

        walk.input(.begin(.firstPage))
        XCTAssertEqual(walk.stop, stop(.stack))
    }

    func testSkipGoesToPage9FromAnyPhaseIncludingAWait() {
        var walk = Walk()
        walk.toPage3()
        XCTAssertEqual(walk.stop?.phase, .clickHide)

        walk.input(.skip)

        XCTAssertEqual(walk.stop, stop(.done))
        XCTAssertEqual(walk.card?.progress, "9 of 9")
        XCTAssertFalse(walk.card!.canSkip)
        XCTAssertEqual(walk.card?.footer, .backAndStartUsing)
    }

    func testBackFromPage9ReachesPage8AndFinishIsOnlyPage9s() {
        var walk = Walk()
        walk.input(.begin(.firstPage))
        walk.input(.finish)
        XCTAssertEqual(walk.stop, stop(.stack), "a stray finish on page 1 is nothing")

        walk.input(.skip)
        walk.input(.back)
        XCTAssertEqual(walk.stop, stop(.aiTool))
        XCTAssertEqual(walk.card?.progress, "8 of 9")
        XCTAssertTrue(walk.card!.isOptional)
        walk.input(.next)
        XCTAssertEqual(walk.input(.finish), .openNotesFolder)
        XCTAssertNil(walk.stop)
    }

    func testSkipAndBackOnPage6UseTheLiveWorldToChooseThePhase() {
        var walk = Walk()
        walk.toPage3()
        walk.input(.skip)
        walk.cells = .empty
        walk.input(.back)
        walk.input(.back)
        walk.input(.back)

        XCTAssertEqual(walk.stop, stop(.spreadOff), "pages 8, 7 and then 6, which is its off page in this world")
    }

    // MARK: What the panel is told

    func testTheCardCarriesTheProgressTheSkipLinkAndTheFooter() {
        var walk = Walk()
        walk.input(.begin(.firstPage))
        XCTAssertEqual(walk.card, HintCard(progress: "1 of 9", isOptional: false, canSkip: true,
                                           title: "The stack holds your cards",
                                           body: "The tan strip is its ribbon, with the buttons. Below it, one stacked card shows at a time.",
                                           footer: .backAndNext))

        walk.input(.next)
        XCTAssertEqual(walk.card?.progress, "2 of 9")
        XCTAssertEqual(walk.card?.footer, .backOnly, "page 2 waits for New")
    }

    func testClarityAndTheAIToolPageAreOptional() {
        var walk = Walk()
        walk.input(.begin(.firstPage))
        walk.input(.skip)
        walk.input(.back)
        walk.input(.back)

        XCTAssertEqual(walk.stop, stop(.clarity))
        XCTAssertEqual(walk.card?.progress, "7 of 9")
        XCTAssertTrue(walk.card!.isOptional)
    }
}
