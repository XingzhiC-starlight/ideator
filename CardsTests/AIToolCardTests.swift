import XCTest
@testable import Ideator

/// A card from an AI tool (`add_card`) joins the stack, never the desktop, where Settings says.
final class AIToolCardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let typed = Note(header: "From a tool", body: [Line(kind: .bullet, runs: [Run(text: "eggs")])])

    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    private func deskWithStack(_ names: String..., clarity: Bool = false) -> Desk {
        Desk(notes: Dictionary(uniqueKeysWithValues: names.map { (id($0), Note(header: $0, body: [])) }),
             saved: SavedDesk(clarity: clarity, stack: names.map(id)))
    }

    private func shown(_ desk: Desk) -> String { desk.selectedCard?.note.header ?? "blank" }
    private func stack(_ desk: Desk) -> [String] { desk.stack.map(\.note.header) }

    @discardableResult
    private func add(_ desk: inout Desk, to landing: Landing, typing: Bool = false) -> CardID? {
        desk.apply(.addFromTool(typed, at: now, to: landing, typing: typing))
    }

    func testTopPutsTheCardOnTopAndTheStackShowsIt() {
        var desk = deskWithStack("a", "b")
        desk.apply(.flipStack(.next))
        XCTAssertEqual(shown(desk), "b")

        XCTAssertNil(add(&desk, to: .top), "nothing arrives on the desktop")

        XCTAssertEqual(stack(desk), ["From a tool", "a", "b"])
        XCTAssertEqual(shown(desk), "From a tool", "the stack switches to the new card")
        XCTAssertEqual(desk.popped, [])
    }

    func testTopWhileTheUserTypesInTheStackedCardKeepsShowingThatCard() {
        var desk = deskWithStack("a", "b")
        desk.apply(.flipStack(.next))
        add(&desk, to: .top, typing: true)
        XCTAssertEqual(stack(desk), ["From a tool", "a", "b"], "the card still goes to the top")
        XCTAssertEqual(shown(desk), "b", "the card being typed in stays")
    }

    func testTopWhileTheUserTypesOnTheBlankPageKeepsTheBlankPage() {
        var desk = deskWithStack("a")
        desk.apply(.flipStack(.next))
        add(&desk, to: .top, typing: true)
        XCTAssertEqual(stack(desk), ["From a tool", "a"])
        XCTAssertEqual(shown(desk), "blank")
    }

    func testBottomPutsTheCardAtTheBottomAndTheStackKeepsShowingWhatItShowed() {
        var desk = deskWithStack("a", "b")
        add(&desk, to: .bottom)
        XCTAssertEqual(stack(desk), ["a", "b", "From a tool"])
        XCTAssertEqual(shown(desk), "a")

        desk.apply(.flipStack(.previous))
        XCTAssertEqual(shown(desk), "blank")
        add(&desk, to: .bottom)
        XCTAssertEqual(shown(desk), "blank", "the blank page stays after the new last card")
        XCTAssertEqual(desk.stack.count, 4)
    }

    func testTheCardTakesClaritysGlobalState() {
        var on = deskWithStack("a", clarity: true)
        add(&on, to: .top)
        XCTAssertEqual(on.stack.first?.collapsed, true)
        XCTAssertTrue(on.clarity, "the card does not move the Clarity button")

        var off = deskWithStack("a")
        add(&off, to: .bottom)
        XCTAssertEqual(off.stack.last?.collapsed, false)
    }

    func testEachCardGetsItsTextAndAFileOfItsOwn() {
        var desk = deskWithStack("a")
        add(&desk, to: .top)
        add(&desk, to: .bottom)
        XCTAssertEqual(desk.stack.map(\.note), [typed, Note(header: "a", body: []), typed])
        XCTAssertEqual(Set(desk.stack.map(\.id)).count, 3, "two cards in the same second get different files")
    }

    func testAFullDesktopStillTakesTheCardIntoTheStack() {
        let slots = Slot.all.filter { $0 != Slot.stackHome }
        let names = slots.map { "p\($0.index)" }
        var desk = Desk(notes: Dictionary(uniqueKeysWithValues: names.map { (id($0), Note(header: $0, body: [])) }),
                        saved: SavedDesk(placements: zip(slots, names).map { SavedPlacement(slot: $0.index, card: id($1)) }))
        XCTAssertNil(desk.firstFreeSlot)

        add(&desk, to: .top)

        XCTAssertEqual(stack(desk), ["From a tool"])
        XCTAssertEqual(desk.popped.count, 19)
    }
}
