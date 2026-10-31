import XCTest
@testable import Ideator

/// The nine pages as data: their shape, the walks over them, and the copy the prototype approved.
final class TourScriptTests: XCTestCase {
    private typealias Fixtures = TourDeskFixtures

    private func slot(_ index: Int) -> Place { Fixtures.slot(index) }

    /// The card New made is out, Spread ticked on its factory cells, nothing else.
    private func ordinary() -> TourWorld { Fixtures.world(Fixtures.desk(popped: [("a", slot(0))]), reader: "a") }
    private func noReaderCard() -> TourWorld { Fixtures.world(Fixtures.desk(stack: ["s"])) }
    /// A card out that New did not make: the tour has no reader's card.
    private func olderCardOnly() -> TourWorld { Fixtures.world(Fixtures.desk(popped: [("old", slot(0))])) }
    /// Every cell taken: New makes no card.
    private func fullDesktop() -> TourWorld { Fixtures.world(Fixtures.fullDesk()) }
    /// Nothing ticked in Settings, or every ticked cell taken: the Spread button would do nothing.
    private func spreadOff() -> TourWorld { Fixtures.world(Fixtures.desk(), cells: .empty) }
    private func spreadTaken() -> TourWorld {
        Fixtures.world(Fixtures.desk(popped: [("a", slot(0)), ("b", slot(1))]), cells: Fixtures.cells(0, 1))
    }
    private func setOut() -> TourWorld {
        Fixtures.world(Fixtures.desk(popped: [("a", slot(0))], set: (cells: .standard, homes: [("a", slot(0))])))
    }

    private var worlds: [TourWorld] {
        [ordinary(), noReaderCard(), olderCardOnly(), fullDesktop(), spreadOff(), spreadTaken(), setOut()]
    }

    private let phases = TourPhase.allCases

    // MARK: Shape

    func testThePagesAreOneToNineAndEachPagesPhasesAreContiguous() {
        let pages = phases.map(\.page)

        XCTAssertEqual(Set(pages), Set(1...9))
        XCTAssertEqual(TourPhase.pageCount, 9)
        XCTAssertEqual(pages, pages.sorted(), "declaration order is walking order, so a page never comes back")
    }

    func testAWaitEndsOnTheSamePageOnTheNextDeclaredPhase() {
        let waiting = phases.filter { !$0.script.waitsFor.isEmpty }

        XCTAssertEqual(waiting, [.clickNew, .clickHide, .clickShow, .clickReturn, .clickSpread, .clickGather])
        for phase in waiting {
            let next = TourScript.after(phase)
            XCTAssertEqual(next.page, phase.page, "\(phase) hands over on its own page")
            XCTAssertEqual(next, phases[phases.firstIndex(of: phase)! + 1], "\(phase) hands over to the next declared phase")
        }
    }

    func testTheLastPhaseOfEveryPageIsNotAWait() {
        for page in 1...9 {
            let last = phases.last { $0.page == page }!
            XCTAssertTrue(last.script.waitsFor.isEmpty, "Back lands on page \(page)'s \(last) and must find a Next or the end, not a wait")
        }
    }

    func testOnlyWaitingPhasesAreMissingNextAndOnlyThe9thEndsWithStartUsing() {
        for phase in phases {
            let expected: PhaseScript.Footer = !phase.script.waitsFor.isEmpty ? .backOnly
                : phase.page == 9 ? .backAndStartUsing : .backAndNext
            XCTAssertEqual(phase.script.footer, expected, "\(phase)")
        }
    }

    func testOptionalIsPerPhaseAsInThePrototype() {
        XCTAssertEqual(phases.filter(\.script.isOptional), [.clickSpread, .clarity, .aiTool],
                       "page 6's first ask, page 7 and page 8; not the off page, not page 6's later phases")
    }

    func testEveryPageAdmitsAPhaseInEveryWorldOnArrivalAndOnBack() {
        for (n, world) in worlds.enumerated() {
            for page in 1...9 {
                XCTAssertEqual(TourScript.entry(of: page, in: world).page, page, "world \(n), entry of \(page)")
                XCTAssertEqual(TourScript.landing(of: page, in: world).page, page, "world \(n), landing of \(page)")
                XCTAssertTrue(TourScript.entry(of: page, in: world).script.gate.admits(world), "world \(n), entry of \(page)")
                XCTAssertTrue(TourScript.landing(of: page, in: world).script.gate.admits(world), "world \(n), landing of \(page)")
            }
        }
    }

    func testOnlyTheFirstAndLastPagesHaveTheirOwnBoundariesToTheFlow() {
        XCTAssertEqual(TourScript.entry(of: 1, in: ordinary()), .stack)
        XCTAssertEqual(TourScript.entry(of: TourPhase.pageCount, in: ordinary()), .done)
        XCTAssertNil(TourScript.following(.done, in: ordinary()), "nothing after the last page")
    }

    // MARK: Walking

    func testNextWalksThePagesInOrderForAReaderWithACard() {
        let world = ordinary()
        var walked: [TourPhase] = [.stack]
        while let next = TourScript.following(walked.last!, in: world) { walked.append(next) }

        XCTAssertEqual(walked, [.stack, .clickNew, .clickHide, .clickReturn, .follow, .clickSpread, .clarity, .aiTool, .done],
                       "Next lands on each page's opening; the waits inside a page end by the reader's action")
    }

    func testPage4IsSkippedBackToItsNeutralStateWhenTheCardNewMadeIsNotOut() {
        for world in [noReaderCard(), olderCardOnly()] {
            XCTAssertEqual(TourScript.following(.allBack, in: world), .afterReturn, "no card to return: straight to the stack text")
            XCTAssertEqual(TourScript.entry(of: 4, in: world), .afterReturn)
        }
        XCTAssertEqual(TourScript.following(.allBack, in: ordinary()), .clickReturn)
    }

    func testPage2IsSkippedToItsNeutralTextWhenNewWouldMakeNoCard() {
        let world = fullDesktop()

        XCTAssertNil(world.desk.firstFreeSlot, "sanity: the desktop is full")
        XCTAssertEqual(TourScript.following(.stack, in: world), .typeIn, "no card can come, so there is nothing to wait for")
        XCTAssertEqual(TourScript.entry(of: 2, in: world), .typeIn)
        XCTAssertEqual(TourScript.landing(of: 2, in: world), .typeIn)
        XCTAssertEqual(TourScript.following(.stack, in: ordinary()), .clickNew)
        XCTAssertEqual(TourScript.following(.stack, in: olderCardOnly()), .clickNew, "an older card does not stand in for New")
        XCTAssertEqual(titles(.typeIn, world), "Each New makes one card")
    }

    func testPage6OpensOnTheAskOrTheOffPageAndNextNeverStepsIntoTheOtherOpening() {
        XCTAssertEqual(TourScript.entry(of: 6, in: ordinary()), .clickSpread)
        XCTAssertEqual(TourScript.entry(of: 6, in: spreadOff()), .spreadOff)
        XCTAssertEqual(TourScript.entry(of: 6, in: spreadTaken()), .spreadOff)
        XCTAssertEqual(TourScript.entry(of: 6, in: setOut()), .clickSpread, "a set to gather is an ask, not an off page")

        XCTAssertEqual(TourScript.following(.follow, in: spreadOff()), .spreadOff)
        XCTAssertEqual(TourScript.following(.spreadOff, in: spreadOff()), .clarity)
        XCTAssertEqual(TourScript.following(.spreadOff, in: ordinary()), .clarity,
                       "Settings ticked cells with no notification: Next still leaves the page it said Next on")
        XCTAssertEqual(TourScript.following(.afterGather, in: ordinary()), .clarity)
    }

    func testBackLandsOnThePreviousPagesFinishedNeutralPhase() {
        let world = ordinary()

        XCTAssertEqual(TourScript.landing(of: 1, in: world), .stack)
        XCTAssertEqual(TourScript.landing(of: 2, in: world), .typeIn)
        XCTAssertEqual(TourScript.landing(of: 3, in: world), .allBack)
        XCTAssertEqual(TourScript.landing(of: 4, in: world), .afterReturn)
        XCTAssertEqual(TourScript.landing(of: 5, in: world), .follow)
        XCTAssertEqual(TourScript.landing(of: 6, in: world), .afterGather)
        XCTAssertEqual(TourScript.landing(of: 6, in: spreadOff()), .spreadOff, "the single page when the button would do nothing")
        XCTAssertEqual(TourScript.landing(of: 6, in: spreadTaken()), .spreadOff)
        XCTAssertEqual(TourScript.landing(of: 7, in: world), .clarity)
        XCTAssertEqual(TourScript.landing(of: 8, in: world), .aiTool)
    }

    // MARK: The copy

    private func context(_ world: TourWorld, _ reading: Reading = .fresh) -> TourContext {
        TourContext(world: world, reading: reading)
    }

    private func titleLine(_ phase: TourPhase, _ world: TourWorld, _ reading: Reading = .fresh) -> TourLine {
        phase.script.title(context(world, reading))
    }

    private func bodyLine(_ phase: TourPhase, _ world: TourWorld, _ reading: Reading = .fresh) -> TourLine {
        phase.script.body(context(world, reading))
    }

    private func titles(_ phase: TourPhase, _ world: TourWorld, _ reading: Reading = .fresh) -> String {
        titleLine(phase, world, reading).spoken
    }

    private func bodies(_ phase: TourPhase, _ world: TourWorld, _ reading: Reading = .fresh) -> String {
        bodyLine(phase, world, reading).spoken
    }

    func testTitlesAreThePrototypesExactly() {
        let world = ordinary()

        XCTAssertEqual(titles(.stack, world), "The stack holds your cards")
        XCTAssertEqual(titles(.clickNew, world), "Click New on the stack")
        XCTAssertEqual(titles(.typeIn, world), "Type or paste into your card")
        XCTAssertEqual(titles(.typeIn, noReaderCard()), "Each New makes one card")
        XCTAssertEqual(titles(.typeIn, olderCardOnly()), "Each New makes one card", "an older card is not the reader's")
        XCTAssertEqual(titles(.clickHide, world), "Click Hide all to hide every card")
        XCTAssertEqual(titles(.clickShow, world), "Click Show all to bring them back")
        XCTAssertEqual(titles(.allBack, world), "Hidden, not deleted: all back")
        XCTAssertEqual(titles(.clickReturn, world), "Hover your card, click Return to stack")
        XCTAssertEqual(titles(.afterReturn, world, .after(.returned)), "Your card is in the stack")
        XCTAssertEqual(titles(.afterReturn, world, .after(.deleted)), "Your card is deleted")
        XCTAssertEqual(titles(.afterReturn, world), "The stack holds your cards", "Back or no card to return")
        XCTAssertEqual(titles(.follow, world), "Your cards follow you")
        XCTAssertEqual(titles(.spreadOff, spreadOff()), "Spread is off")
        XCTAssertEqual(titles(.spreadOff, spreadTaken()), "Spread needs free cells")
        XCTAssertEqual(titles(.clickSpread, world), "Click Spread: 5 blank cards")
        XCTAssertEqual(titles(.clickGather, setOut()), "Click Spread again to put them away")
        XCTAssertEqual(titles(.afterGather, world, .after(.gathered)), "In the stack, back in one click")
        XCTAssertEqual(titles(.afterGather, world, .after(.vanished)), "Gone, nothing was kept")
        XCTAssertEqual(titles(.afterGather, world), "Spread, then Gather")
        XCTAssertEqual(titles(.clarity, world), "Clarity: a summary per card")
        XCTAssertEqual(titles(.aiTool, world), "Your AI tool can add cards")
        XCTAssertEqual(titles(.done, world), "Done: replay from the menu bar")
    }

    func testChipsAreWrittenAsChipsNotAsCharacters() {
        XCTAssertEqual(titleLine(.clickNew, ordinary()).runs, [.text("Click "), .chip(.plus), .text(" on the stack")])
        XCTAssertEqual(titleLine(.clickHide, ordinary()).runs, [.text("Click "), .chip(.hide), .text(" to hide every card")])
        XCTAssertEqual(titleLine(.clickGather, setOut()).runs,
                       [.text("Click "), .chip(.spreadOn), .text(" again to put them away")], "Gather wears the accent-colored symbol")
        XCTAssertEqual(titleLine(.clickSpread, ordinary()).runs,
                       [.text("Click "), .chip(.spread), .text(" Spread: 5 blank cards")])
    }

    func testPage3NamesTheLiveShortcutAndSaysSoWhenItDidNotRegister() {
        let works = Fixtures.world(Fixtures.desk(), shortcut: ShortcutReading(display: "⌃⌥J", works: true))
        let broken = Fixtures.world(Fixtures.desk(), shortcut: ShortcutReading(display: "⌃⌥J", works: false))

        XCTAssertEqual(bodies(.clickHide, works),
                       "Your card and the stack's page go away; only the ribbon stays. ⌃⌥J does the same from any app.")
        XCTAssertEqual(bodies(.clickShow, works), "Nothing was deleted; the cards are only hidden. ⌃⌥J works here too.")
        XCTAssertEqual(bodies(.clickHide, broken),
                       "Your card and the stack's page go away; only the ribbon stays. "
                           + "Ideator couldn't claim ⌃⌥J, so there is no shortcut yet; choose one in Settings.")
        XCTAssertEqual(bodies(.clickShow, broken), "Nothing was deleted; the cards are only hidden.")
        XCTAssertEqual(bodyLine(.clickHide, works).runs.last, .text(" does the same from any app."))
        XCTAssertTrue(bodyLine(.clickHide, works).runs.contains(.key("⌃⌥J")), "the shortcut is a key cap")
    }

    func testPage4TellsDeleteFromReturnInItsBody() {
        let world = ordinary()

        XCTAssertTrue(bodies(.afterReturn, world, .after(.deleted)).hasPrefix("Cards you return instead stay in the stack. Flip through"))
        XCTAssertTrue(bodies(.afterReturn, world, .after(.returned)).hasPrefix("Flip through stacked cards at the stack's edges."))
        XCTAssertEqual(bodies(.typeIn, noReaderCard()), "It appears at the top left, ready to type. The first line is its title.")
    }

    func testPage5HasThreeReactionsAndKeepsItsNextAlways() {
        let script = TourPhase.follow.script

        XCTAssertEqual(Set(script.reactions.keys), [.space, .appFront, .cardsFront])
        XCTAssertEqual(script.reactions[.space]?.title.spoken, "Still here on this Space")
        XCTAssertEqual(script.reactions[.appFront]?.title.spoken, "Click any card to come forward")
        XCTAssertEqual(script.reactions[.cardsFront]?.title.spoken, "Back in front")
        XCTAssertTrue(script.waitsFor.isEmpty)
    }

    func testPage6CountsTheFreeTickedCellsAndNamesWhyTheButtonIsOff() {
        let someTaken = Fixtures.world(Fixtures.desk(popped: [("a", slot(0)), ("b", slot(6))]))

        XCTAssertEqual(titles(.clickSpread, someTaken), "Click Spread: 4 blank cards", "the chip before its own name is read once")
        XCTAssertTrue(bodies(.spreadOff, spreadOff()).contains("None are ticked"))
        XCTAssertTrue(bodies(.spreadOff, spreadTaken()).contains("Every one of them is taken right now"))
    }

    func testPage7And8KeepTheCurlyQuotes() {
        XCTAssertTrue(bodies(.clarity, ordinary()).contains("“Summary unavailable”"))
        XCTAssertTrue(bodies(.aiTool, ordinary()).contains("“put this in Ideator”"))
    }

    func testEveryTitleInEveryReadingFitsOneLine() {
        let readings: [Reading] = [.fresh] + [TourEvent.new, .hidden, .shown, .returned, .deleted, .spreadOut, .gathered, .vanished,
                                              .space, .appFront, .cardsFront].flatMap { [Reading.after($0), .reacted($0)] }
        for phase in phases {
            for world in worlds {
                for reading in readings {
                    let title = titles(phase, world, reading)
                    XCTAssertLessThanOrEqual(title.count, 44, "\(phase) / \(reading): \(title)")
                }
            }
            for (event, reaction) in phase.script.reactions {
                XCTAssertLessThanOrEqual(reaction.title.spoken.count, 44, "\(phase) reacting to \(event)")
            }
        }
    }

    func testNoCopyEverSaysAlwaysOnTop() {
        for phase in phases {
            for world in worlds {
                for reading in [Reading.fresh, .after(.deleted), .after(.returned), .after(.gathered), .after(.vanished)] {
                    let text = (titles(phase, world, reading) + " " + bodies(phase, world, reading)).lowercased()
                    XCTAssertFalse(text.contains("always on top"), "\(phase): \(text)")
                }
            }
            for reaction in phase.script.reactions.values {
                XCTAssertFalse((reaction.title.spoken + reaction.body.spoken).lowercased().contains("always on top"))
            }
        }
    }

    func testNoTourElementIsNamedExactlyNew() {
        for phase in phases {
            for world in worlds {
                XCTAssertNotEqual(titles(phase, world), "New", "the verify harness takes a control named New for the stack's button")
            }
        }
    }

    func testWhereEachPageAimsItsPanelAndRing() {
        XCTAssertEqual(TourPhase.stack.script.aim, Aim(anchor: .stack, ring: .stack))
        XCTAssertEqual(TourPhase.clickNew.script.aim, Aim(anchor: .control(.new), ring: .control(.new)))
        XCTAssertEqual(TourPhase.typeIn.script.aim, Aim(anchor: .readerCard))
        XCTAssertEqual(TourPhase.clickReturn.script.aim, Aim(anchor: .readerCard, ring: .hoverCorner, showsHoverButtons: true))
        XCTAssertEqual(TourPhase.follow.script.aim, Aim(anchor: .belowStack))
        XCTAssertEqual(TourPhase.clickSpread.script.aim,
                       Aim(anchor: .control(.spread), ring: .control(.spread), litCells: true))
        XCTAssertEqual(TourPhase.done.script.aim, Aim(anchor: .stackTop, ring: .menuBarIcon))
        XCTAssertEqual(phases.filter(\.script.aim.showsHoverButtons), [.clickReturn], "only page 4's ask holds the hover buttons")
    }
}

