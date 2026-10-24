import XCTest
@testable import Ideator

final class VisibilityTests: XCTestCase {
    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    func testEverythingShowsUntilHideAll() {
        let visibility = Visibility.all
        XCTAssertTrue(visibility.shows(id("a")), "a popped card shows")
        XCTAssertTrue(visibility.showsStackCard, "and so does the stack's card area")
        XCTAssertFalse(visibility.isHidden, "nothing is hidden")
    }

    func testHideAllHidesEveryPoppedCardAndTheStackCardArea() {
        let visibility = Visibility.hideAll
        XCTAssertFalse(visibility.shows(id("a")), "a popped card is hidden")
        XCTAssertFalse(visibility.showsStackCard, "so is the stack's card area")
        XCTAssertTrue(visibility.isHidden, "the state says so")
    }

    func testRevealingACardShowsOnlyThatCard() {
        var visibility = Visibility.hideAll
        visibility.reveal(id("a"))
        XCTAssertTrue(visibility.shows(id("a")), "the revealed card shows")
        XCTAssertFalse(visibility.shows(id("b")), "the others stay hidden")
        XCTAssertFalse(visibility.showsStackCard, "and so does the stack's card area")
    }

    func testRevealingTheStackCardShowsOnlyIt() {
        var visibility = Visibility.hideAll
        visibility.revealStackCard()
        XCTAssertTrue(visibility.showsStackCard, "the stack's card area shows")
        XCTAssertFalse(visibility.shows(id("a")), "popped cards stay hidden")
    }

    func testHidingAllAgainForgetsWhatWasRevealed() {
        var visibility = Visibility.hideAll
        visibility.reveal(id("a"))
        visibility.revealStackCard()
        visibility = .hideAll
        XCTAssertFalse(visibility.shows(id("a")), "Hide all hides the revealed card again")
        XCTAssertFalse(visibility.showsStackCard, "and the stack's card area")
    }

    func testRevealingWhileEverythingShowsChangesNothing() {
        var visibility = Visibility.all
        visibility.reveal(id("a"))
        visibility.revealStackCard()
        XCTAssertEqual(visibility, .all, "there is nothing to reveal")
    }

    func testANewCardWhileHiddenTakesTheSlotItWouldHaveTakenWithEverythingShown() {
        var desk = Desk(notes: [:], saved: SavedDesk())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = desk.apply(.new(at: now))!
        var visibility = Visibility.hideAll
        let second = desk.apply(.new(at: now.addingTimeInterval(1)))!
        visibility.reveal(second)
        XCTAssertEqual(desk.place(of: .card(first)), .slot(Slot(index: 0)!), "the hidden card has the first slot")
        XCTAssertEqual(desk.place(of: .card(second)), .slot(Slot(index: 1)!), "it goes after the hidden card's slot")
        XCTAssertTrue(visibility.shows(second), "the new card shows")
        XCTAssertFalse(visibility.shows(first), "the hidden one does not")
    }

    private func deskWithStack(_ names: String...) -> Desk {
        Desk(notes: Dictionary(uniqueKeysWithValues: names.map { (id($0), Note(header: $0, body: [])) }),
             saved: SavedDesk(stack: names.map(id)))
    }

    func testShowingAStackedCardWhileHiddenBringsBackTheStacksCardAreaAndNothingElse() {
        var desk = deskWithStack("a", "b")
        let arrived = desk.apply(.new(at: Date(timeIntervalSince1970: 1_700_000_000)))!
        var visibility = Visibility.hideAll
        let command = Command.showStacked(id("b"))
        let shownCard = desk.apply(command)
        visibility.reveal(after: command, arrived: shownCard, in: desk)
        XCTAssertTrue(visibility.showsStackCard, "the stack's card area is back, to show the card")
        XCTAssertFalse(visibility.shows(arrived), "a popped card stays hidden")
        XCTAssertTrue(visibility.isHidden, "and Hide all is still on")
    }

    func testMovingStackedCardsOrShowingAnUnknownOneWhileHiddenRevealsNothing() {
        var desk = deskWithStack("a", "b")
        var visibility = Visibility.hideAll
        for command in [Command.arrange(id("b"), at: 0), .arrange(id("ghost"), at: 0), .showStacked(id("ghost"))] {
            let arrived = desk.apply(command)
            visibility.reveal(after: command, arrived: arrived, in: desk)
        }
        XCTAssertEqual(visibility, .hideAll, "a move changes the order, not what is on screen")
    }

    func testNewAndPopStillRevealWhatTheyBringOut() {
        var desk = deskWithStack("a")
        var visibility = Visibility.hideAll
        let made = Command.new(at: Date(timeIntervalSince1970: 1_700_000_000))
        let arrived = desk.apply(made)
        visibility.reveal(after: made, arrived: arrived, in: desk)
        XCTAssertTrue(visibility.shows(arrived!), "New shows the new card")
        XCTAssertFalse(visibility.showsStackCard, "and not the stack's card area")
        let popped = desk.apply(.pop)
        visibility.reveal(after: .pop, arrived: popped, in: desk)
        XCTAssertTrue(visibility.shows(popped!), "Pop shows the card it took")
    }

    func testNewOnAFullDesktopWhileHiddenShowsTheStacksBlankPage() {
        var desk = Desk(notes: Dictionary(uniqueKeysWithValues: (0...19).map { (id("c\($0)"), Note(header: "c", body: [])) }),
                        saved: SavedDesk(placements: Slot.all.filter { $0 != Slot.stackHome }.enumerated()
                            .map { SavedPlacement(slot: $1.index, card: id("c\($0)")) }, stack: [id("c19")]))
        var visibility = Visibility.hideAll
        let made = Command.new(at: Date(timeIntervalSince1970: 1_700_000_000))
        let arrived = desk.apply(made)
        visibility.reveal(after: made, arrived: arrived, in: desk)
        XCTAssertNil(arrived, "the desktop is full, so nothing arrives")
        XCTAssertTrue(visibility.showsStackCard, "the blank page it shows needs the card area")
    }

    func testTheRibbonOnlyWindowIsTheTopOfTheStacksCell() {
        let cell = CGRect(x: 0, y: 700, width: 302, height: 237)
        let frame = StackWindow.ribbonOnlyFrame(in: cell)
        XCTAssertEqual(frame.minX, cell.minX, "same left edge")
        XCTAssertEqual(frame.width, cell.width, "same width")
        XCTAssertEqual(frame.maxY, cell.maxY, "same top edge")
        XCTAssertLessThan(frame.height, cell.height / 2, "much shorter than the cell")
        XCTAssertGreaterThan(frame.height, 40, "yet taller than the ribbon, for the gap around it")
    }
}
