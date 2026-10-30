import XCTest
@testable import Ideator

final class PlacementTests: XCTestCase {
    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    private func slot(_ index: Int) -> Place { .slot(Slot(index: index)!) }

    /// The stack in its default place (top-right) and each name popped into the slot given.
    private func desk(_ popped: [String: Int], stack: [String] = []) -> Desk {
        let names = Array(popped.keys) + stack
        return Desk(notes: Dictionary(uniqueKeysWithValues: names.map { (id($0), Note(header: $0, body: [])) }),
                    saved: SavedDesk(placements: popped.sorted { $0.value < $1.value }
                                        .map { SavedPlacement(slot: $0.value, card: id($0.key)) },
                                     stack: stack.map(id)))
    }

    // MARK: The snap rule

    func testADropNearASlotsCenterSnapsAndOneFurtherAwayStaysFree() {
        let center = Slot(index: 7)!.center
        let near = GridPoint(x: center.x + 0.1 / 5, y: center.y)        // 10 % of a cell to the right
        let far = GridPoint(x: center.x + 0.2 / 5, y: center.y)         // 20 %
        XCTAssertEqual(Place.dropped(at: near), slot(7), "within 15 % of a cell it snaps")
        XCTAssertEqual(Place.dropped(at: far), .free(far), "beyond it, it stays exactly where it was dropped")
        XCTAssertEqual(Place.guide(at: near).snaps, true, "and the guide says so beforehand")
        XCTAssertEqual(Place.guide(at: far).slot, Slot(index: 7), "the guide outlines the nearest slot either way")
        XCTAssertEqual(Place.guide(at: far).snaps, false, "but promises no snap")
    }

    // MARK: Hanging off the edges

    private let screen = Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 1000))   // 300 × 250 cards
    private let screenWithDock = Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 1000),
                                      reachable: CGRect(x: 0, y: 70, width: 1500, height: 930))

    func testSnappedSlotsAreAlwaysFullyOnScreenAndSizedFromTheWholeScreen() {
        for grid in [screen, screenWithDock] {
            for slot in Slot.all {
                let frame = grid.frame(of: slot)
                XCTAssertTrue(grid.area.contains(frame), "slot \(slot.index) is inside the screen")
                XCTAssertEqual(frame.size, CGSize(width: 300, height: 250), "the Dock does not shrink a slot")
            }
        }
    }

    /// Where a card dragged until its center is at `center` ends up.
    private func dropped(_ center: CGPoint, on grid: Grid) -> CGRect {
        grid.frame(of: Place.dropped(at: grid.point(at: center)))
    }

    func testAFreeCardCanHangOffTheLeftRightAndBottomLeavingOnlyItsGrabStrip() {
        let left = dropped(CGPoint(x: -500, y: 500), on: screen)
        XCTAssertEqual(left.minX, -260, "the card's width minus 40 points hangs off the left")
        XCTAssertEqual(left.maxX, 40, "so 40 points of it stay on screen")
        let right = dropped(CGPoint(x: 2000, y: 500), on: screen)
        XCTAssertEqual(right.minX, 1460, "only 40 points stay on screen at the right")
        XCTAssertEqual(right.maxX, 1760, "the rest hangs off")
        let bottom = dropped(CGPoint(x: 750, y: -500), on: screen)
        XCTAssertEqual(bottom.maxY, 40, "at the bottom its top 40 points, the header, stay on screen")
        XCTAssertEqual(bottom.minY, -210, "the rest of the card hangs off")
    }

    func testTheTopOfAFreeCardNeverGoesAboveTheArea() {
        let frame = dropped(CGPoint(x: 900, y: 5000), on: screen)
        XCTAssertEqual(frame.maxY, screen.area.maxY, "the header stops at the top, under the menu bar")
        XCTAssertEqual(frame.minX, 750, "sideways it stays where it was dropped")
    }

    func testADropThatKeepsEnoughOfTheCardOnScreenStaysExactlyWhereItWas() {
        let frame = dropped(CGPoint(x: -100, y: 500), on: screen)
        XCTAssertEqual(frame.minX, -250, "50 points on screen is enough, so nothing moves")
        XCTAssertEqual(frame.midY, 500, "and neither does its height")
        XCTAssertEqual(Place.dropped(at: screen.point(at: CGPoint(x: -100, y: 500))),
                       .free(GridPoint(x: -100.0 / 1500, y: 0.5)), "the saved spot is the exact drop, off screen as it is")
    }

    func testAHeaderCannotHideUnderTheDock() {
        let frame = dropped(CGPoint(x: 750, y: -500), on: screenWithDock)
        XCTAssertEqual(frame.maxY, 110, "the header's 40 points end up just above the Dock")
    }

    func testEveryFreeCardKeepsItsGrabStripOnScreenWhereverItWasPut() {
        let grids = [
            screen,
            Grid(area: CGRect(x: 0, y: 0, width: 1512, height: 949)),                                   // fractional cells
            Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 1000),
                 reachable: CGRect(x: 80, y: 70, width: 1420, height: 930)),                             // Dock at the left
        ]
        for grid in grids {
            for x in stride(from: -1.0, through: 2.0, by: 0.37) {
                for y in stride(from: -1.0, through: 2.0, by: 0.37) {
                    let frame = grid.frame(of: .free(GridPoint(x: x, y: y)))
                    let overlap = frame.intersection(grid.reachable)
                    XCTAssertGreaterThanOrEqual(overlap.width, 40, "40 points of width stay reachable at \(x), \(y)")
                    XCTAssertGreaterThanOrEqual(frame.maxY - 40, grid.reachable.minY, "the top strip clears the bottom at \(x), \(y)")
                    XCTAssertLessThanOrEqual(frame.maxY, grid.reachable.maxY, "the top never rises above the area at \(x), \(y)")
                }
            }
        }
    }

    func testAPointFarOutsideTheScreenSavesAndLoadsAsItWasAndOnlyRendersPulledBack() throws {
        let hanging = GridPoint(x: -0.08, y: 0.3)   // leaves 60 points of a card on a 3000 wide screen, 30 on a 1500 wide one
        var desk = desk(["a": 1], stack: ["b"])
        desk.apply(.move(.card(id("a")), to: .free(hanging)))
        let json = try JSONEncoder().encode(desk.saved)
        let loaded = Desk(notes: Dictionary(uniqueKeysWithValues: desk.allCards.map { ($0.id, $0.note) }),
                          saved: try JSONDecoder().decode(SavedDesk.self, from: json))
        XCTAssertEqual(loaded.place(of: .card(id("a"))), .free(hanging), "the saved point is not clamped")

        let big = Grid(area: CGRect(x: 0, y: 0, width: 3000, height: 1000))
        let small = Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 1000))
        XCTAssertEqual(big.frame(of: .free(hanging)).maxX, 60, "a big screen shows it as saved")
        XCTAssertEqual(small.frame(of: .free(hanging)).maxX, 40, "a small one pulls it back to 40 points")
    }

    func testNonsensePointsAreMadeSane() throws {
        XCTAssertEqual(GridPoint(x: -5, y: .nan), GridPoint(x: -1, y: 0.5), "too far left is capped, not a number is the middle")
        XCTAssertEqual(GridPoint(x: .infinity, y: 9), GridPoint(x: 0.5, y: 2), "infinity is the middle, too far down is capped")
        let json = #"{"version":2,"clarity":false,"stackFree":{"x":1e300,"y":-1e300},"placements":[{"free":{"x":-1e300,"y":1e300},"card":"a"}],"stack":["b"],"summaries":[]}"#
        let saved = try JSONDecoder().decode(SavedDesk.self, from: Data(json.utf8))
        var desk = Desk(notes: [id("a"): Note(header: "a", body: []), id("b"): Note(header: "b", body: [])], saved: saved)
        for place in [desk.stackPlace, desk.place(of: .card(id("a")))!] {
            let frame = screen.frame(of: place)
            XCTAssertGreaterThanOrEqual(frame.intersection(screen.area).width, 40, "it still renders within reach")
            XCTAssertLessThanOrEqual(frame.maxY, screen.area.maxY, "below the top")
        }
        XCTAssertEqual(desk.apply(.pop), id("b"), "and the desk works")
    }

    func testSlotContainingPointsPastTheEdgesIsTheEdgesCell() {
        XCTAssertEqual(Slot(containing: GridPoint(x: -0.3, y: -0.5)), Slot(index: 0), "past the top-left corner")
        XCTAssertEqual(Slot(containing: GridPoint(x: 1.7, y: 0.1)), Slot(index: 4), "past the right edge, top row")
        XCTAssertEqual(Slot(containing: GridPoint(x: -0.05, y: 1.2)), Slot(index: 15), "past the left edge, below the bottom")
        XCTAssertEqual(Slot(containing: GridPoint(x: 0.5, y: 1.9)), Slot(index: 17), "below the bottom, middle column")
    }

    func testAFreeCardHangingOffTheLeftStillTakesTheSlotItCoversForPop() {
        var desk = desk(["a": 0], stack: ["b"])
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: -0.05, y: 0.1))))
        XCTAssertEqual(desk.apply(.pop), id("b"))
        XCTAssertEqual(desk.place(of: .card(id("b"))), slot(1), "pop skips the corner slot it hangs over")
    }

    func testAFreeCardsFrameIsACellCenteredOnItsPoint() {
        let grid = Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 1000))
        let frame = grid.frame(of: .free(GridPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(frame, CGRect(x: 600, y: 375, width: 300, height: 250), "one cell in size, centered")
        XCTAssertEqual(grid.point(at: CGPoint(x: frame.midX, y: frame.midY)), GridPoint(x: 0.5, y: 0.5),
                       "and its center reads back as the same point")
        XCTAssertEqual(grid.frame(of: slot(0)).maxY, 1000, "slot 0 is the top-left cell")
    }

    // MARK: Moving

    func testAFreeCardTakesTheSlotItCoversMostForPop() {
        var desk = desk(["a": 0], stack: ["b"])
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: 0.6, y: 0.4))))   // mostly over slot 8
        XCTAssertEqual(desk.firstFreeSlot, Slot(index: 0), "its old slot is free again")
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: 0.13, y: 0.1))))  // mostly over slot 0, not snapped
        XCTAssertEqual(desk.apply(.pop), id("b"))
        XCTAssertEqual(desk.place(of: .card(id("b"))), slot(1), "pop skips the slot the free card covers")
    }

    func testSnappingOntoACardSendsItToTheMoversExactFreeSpot() {
        var desk = desk(["a": 1, "b": 2])
        let spot = GridPoint(x: 0.47, y: 0.71)
        desk.apply(.move(.card(id("a")), to: .free(spot)))
        desk.apply(.move(.card(id("a")), to: slot(2)))
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(2), "the dragged card takes the slot")
        XCTAssertEqual(desk.place(of: .card(id("b"))), .free(spot), "the occupant goes where it came from")
    }

    func testSnappingOntoACardSwapsSlots() {
        var desk = desk(["a": 1, "b": 2])
        desk.apply(.move(.card(id("a")), to: slot(2)))
        XCTAssertEqual(desk.place(of: .card(id("b"))), slot(1), "slot for slot, as before")
    }

    func testSnappingOntoASlotAFreeCardCoversLeavesTheFreeCardPut() {
        let spot = GridPoint(x: 0.75, y: 0.1)   // over slot 3
        var desk = desk(["a": 1, "b": 2])
        desk.apply(.move(.card(id("a")), to: .free(spot)))
        desk.apply(.move(.card(id("b")), to: slot(3)))
        XCTAssertEqual(desk.place(of: .card(id("b"))), slot(3), "the dragged card snaps")
        XCTAssertEqual(desk.place(of: .card(id("a"))), .free(spot), "and the free card overlapping it stays")
    }

    func testMovingTheStackFreesItsSlotForPop() {
        var desk = desk(["p0": 0, "p1": 1, "p2": 2, "p3": 3], stack: ["a"])
        XCTAssertEqual(desk.firstFreeSlot, Slot(index: 5), "slots 0 to 3 are cards and 4 is the stack")
        desk.apply(.move(.stack, to: slot(7)))
        XCTAssertEqual(desk.stackPlace, slot(7), "the stack moved")
        desk.apply(.pop)
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(4), "and its old slot is a card slot now")
    }

    func testSnappingACardOntoTheStackSwapsThem() {
        var desk = desk(["a": 1])
        desk.apply(.move(.card(id("a")), to: slot(4)))
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(4), "the card takes the stack's slot")
        XCTAssertEqual(desk.stackPlace, slot(1), "and the stack takes the card's")
    }

    func testPilingFreeCardsStillStopsAtNineteen() {
        var desk = Desk(notes: [:], saved: SavedDesk())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for n in 0..<19 {
            let card = desk.apply(.new(at: now.addingTimeInterval(Double(n))))!
            desk.apply(.move(.card(card), to: .free(GridPoint(x: 0.5, y: 0.5))))
        }
        XCTAssertNil(desk.firstFreeSlot, "slots are left, but 19 cards are on the desktop")
        XCTAssertNil(desk.apply(.new(at: now)), "so New is refused")
    }

    func testReturningAFreeCardForgetsWhereItWas() {
        var desk = desk(["a": 1])
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: 0.5, y: 0.5))))
        desk.apply(.returnToStack(id("a")))
        desk.apply(.pop)
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(0), "a later pop takes the first free slot")
    }

    // MARK: The sidecar

    func testFreePlacesAndTheStacksPlaceSurviveSavingAndLoading() throws {
        var desk = desk(["a": 1, "b": 2], stack: ["c"])
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: 0.31, y: 0.62))))
        desk.apply(.move(.stack, to: .free(GridPoint(x: 0.8, y: 0.2))))
        let json = try JSONEncoder().encode(desk.saved)
        let saved = try JSONDecoder().decode(SavedDesk.self, from: json)
        let notes = Dictionary(uniqueKeysWithValues: desk.allCards.map { ($0.id, $0.note) })
        XCTAssertEqual(Desk(notes: notes, saved: saved), desk, "every place comes back exactly")
    }

    func testASpreadSetSurvivesSavingAndLoadingOutAndGathered() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var desk = desk([:], stack: ["c"])
        desk.apply(.spread(SpreadCells(indices: [0, 1]), fresh: false, at: now))
        desk.apply(.edit(desk.popped[1].card.id, Note(header: "Written", body: [])))
        desk.apply(.move(.card(desk.popped[0].card.id), to: .free(GridPoint(x: 0.31, y: 0.62))))
        func reloaded() throws -> Desk {
            let saved = try JSONDecoder().decode(SavedDesk.self, from: JSONEncoder().encode(desk.saved))
            return Desk(notes: Dictionary(uniqueKeysWithValues: desk.allCards.map { ($0.id, $0.note) }), saved: saved)
        }
        XCTAssertEqual(try reloaded(), desk, "the set comes back while its cards are out")
        desk.apply(.spread(SpreadCells(indices: [0, 1]), fresh: false, at: now))
        XCTAssertEqual(try reloaded(), desk, "and once gathered, with each card's place")
    }

    func testTheStackStartsTopRightAndPopFillsFromTheTopLeft() {
        var desk = Desk(notes: [id("a"): Note(header: "a", body: [])], saved: SavedDesk(stack: [id("a")]))
        XCTAssertEqual(desk.stackPlace, slot(4), "with no sidecar the stack is in the top-right slot")
        let frame = screen.frame(of: desk.stackPlace)
        XCTAssertEqual([frame.maxX, frame.maxY], [screen.area.maxX, screen.area.maxY], "which is the top-right corner")
        desk.apply(.pop)
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(0), "and the first card goes top-left")
    }

    func testAVersionTwoSidecarKeepsTheStackWhereItWas() {
        let desk = Desk(notes: [:], saved: SavedDesk(stackSlot: 0))
        XCTAssertEqual(desk.stackPlace, slot(0), "a recorded top-left stack is not moved to the new default")
    }

    func testASidecarCardInTheStacksSlotJoinsTheStack() {
        let saved = SavedDesk(stackSlot: 6, placements: [SavedPlacement(slot: 6, card: id("a"))])
        let desk = Desk(notes: [id("a"): Note(header: "a", body: [])], saved: saved)
        XCTAssertEqual(desk.stackPlace, slot(6), "the stack keeps its slot")
        XCTAssertEqual(desk.stack.map(\.id), [id("a")], "the card that claimed it goes to the stack")
    }
}
