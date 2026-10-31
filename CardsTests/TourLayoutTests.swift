import XCTest
@testable import Ideator

/// Where the hint panel, its notch, the rings and the lit cells go: the prototype's `renderGuide` on a
/// synthetic 1500 × 1000 screen below the menu bar, whose cells are 300 × 250.
final class TourLayoutTests: XCTestCase {
    private let grid = Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 1000))
    /// A two-line hint at the full width: 316 × 152 visible, as the prototype's page 1 measures.
    private let panel = CGSize(width: 322, height: 158)

    private func face(_ slot: Int) -> CGRect { Surfaces.face(of: grid.frame(of: Slot(index: slot)!)) }

    private func surfaces(stack slot: Int = 4, hidden: Bool = false) -> Surfaces {
        let cell = grid.frame(of: Slot(index: slot)!)
        return Surfaces(screen: grid.area, stack: Surfaces.face(of: hidden ? StackWindow.ribbonOnlyFrame(in: cell) : cell),
                        allHidden: hidden, controls: [:])
    }

    /// The panel's visible face, from the window `point` returns.
    private func face(of pointing: Pointing) -> CGRect { pointing.panel.insetBy(dx: CardShape.gap, dy: CardShape.gap) }

    func testThePanelIs316WideOnScreensFrom1300PointsAnd240Below() {
        XCTAssertEqual(TourLayout.faceWidth(screenWidth: 1512), 316)
        XCTAssertEqual(TourLayout.faceWidth(screenWidth: 1300), 316)
        XCTAssertEqual(TourLayout.faceWidth(screenWidth: 1280), 240, "a cell less 28 is under 240 there, so 240")
        XCTAssertEqual(TourLayout.faceWidth(screenWidth: 1024), 240)
    }

    func testPageOneSitsLeftOfTheStackAtItsRibbonWithTheWholeStackRinged() {
        let pointing = TourLayout.point(Aim(anchor: .stack, ring: .stack), at: surfaces(), panel: panel)

        let stack = face(4)   // 1203…1497 × 753…997
        XCTAssertEqual(face(of: pointing), CGRect(x: stack.minX - 16 - 316, y: 990 - 152, width: 316, height: 152),
                       "16 pt left of the stack; its top 28 above the ribbon's line, but no higher than 10 below the menu bar")
        XCTAssertEqual(pointing.panel.size, panel)
        XCTAssertEqual(pointing.notch, .right(at: 18), "pointing at the ribbon, 18 pt from the corner at the closest")
        XCTAssertEqual(pointing.rings, [RingShape(rect: stack.insetBy(dx: -5, dy: -5), radius: 15)])
        XCTAssertEqual(pointing.lit, [])
        XCTAssertFalse(pointing.needsMenuBarLevel)
    }

    func testARibbonButtonPageNotchesAtTheButtonAndRingsItsSquareFiveOutWithRadiusNine() {
        var s = surfaces(stack: 9)   // 503…747 high
        let spread = CGRect(x: 1260, y: 717, width: 20, height: 18)   // its center is 726
        s.controls = [.spread: spread]

        let pointing = TourLayout.point(Aim(anchor: .control(.spread), ring: .control(.spread)), at: s, panel: panel)

        XCTAssertEqual(face(of: pointing).maxY, 726 + 28, "its top 28 above the button's center")
        XCTAssertEqual(face(of: pointing).maxX, face(9).minX - 16)
        XCTAssertEqual(pointing.notch, .right(at: 28), "the notch at the button's height")
        XCTAssertEqual(pointing.rings, [RingShape(rect: CGRect(x: 1256, y: 712, width: 28, height: 28), radius: 9)],
                       "the prototype's 18 pt button square at the hit area's center, 5 out")
    }

    func testTheReadersCardPagesSitRightOfTheCardAndRingItsHoverButtons() {
        var s = surfaces()
        s.readerFace = face(0)   // 3…297 × 753…997
        let row = CGRect(x: 220, y: 974, width: 64, height: 18)
        s.hoverCorner = row

        let pointing = TourLayout.point(Aim(anchor: .readerCard, ring: .hoverCorner, showsHoverButtons: true), at: s, panel: panel)

        XCTAssertEqual(face(of: pointing).origin, CGPoint(x: 297 + 16, y: 990 - 152),
                       "16 pt right of the card, 2 below its top but no higher than 10 below the menu bar")
        XCTAssertEqual(pointing.notch, .left(at: 18), "pointing at the card's top, on the panel's left edge")
        XCTAssertEqual(pointing.rings, [RingShape(rect: row.insetBy(dx: -5, dy: -5), radius: 9)])
    }

    func testWithoutAReadersCardThePanelGoesBesideTheStack() {
        let pointing = TourLayout.point(Aim(anchor: .readerCard), at: surfaces(), panel: panel)

        XCTAssertEqual(face(of: pointing).maxX, face(4).minX - 16)
        XCTAssertEqual(pointing.rings, [], "no hover row to ring")
    }

    func testPageFiveSitsUnderTheStackPointingUpAtItsMiddle() {
        let pointing = TourLayout.point(Aim(anchor: .belowStack), at: surfaces(), panel: panel)

        let stack = face(4)
        XCTAssertEqual(face(of: pointing).maxY, stack.minY - 16)
        XCTAssertEqual(face(of: pointing).maxX, 1500 - 8, "right-aligned with the stack, then kept 8 pt in from the edge")
        XCTAssertEqual(pointing.notch, .top(at: stack.midX - face(of: pointing).minX), "the notch still at the stack's middle")
        XCTAssertEqual(pointing.rings, [])
    }

    func testUnderHideAllPageFiveSits16PointsBelowTheRibbonOnlyStack() {
        let s = surfaces(hidden: true)
        let pointing = TourLayout.point(Aim(anchor: .belowStack), at: s, panel: panel)

        XCTAssertEqual(s.stack, CGRect(x: 1203, y: 1000 - 3 - 40, width: 294, height: 40), "the 40 pt ribbon is all that shows")
        XCTAssertEqual(face(of: pointing).maxY, s.stack.minY - 16)
    }

    func testTheLastPageTopAlignsWithTheStackAndRingsTheMenuBarIconAboveTheMenuBar() {
        var s = surfaces()
        let icon = CGRect(x: 1320, y: 1000, width: 30, height: 24)
        s.menuBarIcon = icon

        let pointing = TourLayout.point(Aim(anchor: .stackTop, ring: .menuBarIcon), at: s, panel: panel)

        XCTAssertEqual(face(of: pointing).maxY, face(4).maxY - 2)
        XCTAssertEqual(pointing.notch, .right(at: 28))
        XCTAssertEqual(pointing.rings, [RingShape(rect: icon.insetBy(dx: -3, dy: -3), radius: 7)])
        XCTAssertTrue(pointing.needsMenuBarLevel)

        s.menuBarIcon = nil
        let hiddenIcon = TourLayout.point(Aim(anchor: .stackTop, ring: .menuBarIcon), at: s, panel: panel)
        XCTAssertEqual(hiddenIcon.rings, [], "an icon the menu bar hides gets no ring")
        XCTAssertFalse(hiddenIcon.needsMenuBarLevel)
    }

    func testAPanelPushedUpFromTheBottomStillPointsAtItsTarget() {
        let tall = CGSize(width: 322, height: 306)   // a 300 pt face
        let pointing = TourLayout.point(Aim(anchor: .stack), at: surfaces(stack: 19), panel: tall)   // the stack's face is 3…247 high

        XCTAssertEqual(face(of: pointing).minY, 70, "70 pt stay free above the bottom edge, for the Dock")
        XCTAssertEqual(pointing.notch, .right(at: face(of: pointing).maxY - (247 - 23)), "at the stack's ribbon line")
    }

    func testThePanelChangesSidesRatherThanCoverWhatItPointsAt() {
        let stackLeft = TourLayout.point(Aim(anchor: .control(.new)), at: surfaces(stack: 0), panel: panel)
        XCTAssertEqual(face(of: stackLeft).minX, face(0).maxX + 16, "no room left of a stack in the left column")
        XCTAssertEqual(stackLeft.notch, .left(at: 18))

        var s = surfaces(stack: 9)
        s.readerFace = face(4)
        let cardRight = TourLayout.point(Aim(anchor: .readerCard), at: s, panel: panel)
        XCTAssertEqual(face(of: cardRight).maxX, face(4).minX - 16, "no room right of a card in the right column")
        XCTAssertEqual(cardRight.notch, .right(at: 18))

        let stackLow = TourLayout.point(Aim(anchor: .belowStack), at: surfaces(stack: 19), panel: panel)
        XCTAssertEqual(face(of: stackLow).maxX, face(19).minX - 16, "no room below a stack in the bottom row")
        XCTAssertGreaterThanOrEqual(face(of: stackLow).minY, 70)
    }

    func testUnderHideAllOnlyHideAndShowKeepsARingOnTheRibbon() {
        var s = surfaces(hidden: true)
        s.controls = [.spread: CGRect(x: 1260, y: 967, width: 20, height: 18), .hideShow: CGRect(x: 1240, y: 967, width: 18, height: 18)]

        XCTAssertEqual(TourLayout.point(Aim(anchor: .control(.spread), ring: .control(.spread)), at: s, panel: panel).rings, [])
        XCTAssertEqual(TourLayout.point(Aim(anchor: .control(.hideShow), ring: .control(.hideShow)), at: s, panel: panel).rings,
                       [RingShape(rect: s.controls[.hideShow]!.insetBy(dx: -5, dy: -5), radius: 9)])
        XCTAssertEqual(TourLayout.point(Aim(anchor: .readerCard, ring: .hoverCorner), at: s, panel: panel).rings, [],
                       "the hover row's card is ordered out")
    }

    func testOnlyAnAimThatLightsCellsDrawsThem() {
        var s = surfaces()
        s.litFaces = [face(0), face(1)]

        XCTAssertEqual(TourLayout.point(Aim(anchor: .control(.spread), litCells: true), at: s, panel: panel).lit, [face(0), face(1)])
        XCTAssertEqual(TourLayout.point(Aim(anchor: .control(.spread)), at: s, panel: panel).lit, [])
    }

    // MARK: What the layout reads from the world

    private func world(_ visibility: Visibility = .all) -> TourWorld {
        TourWorld(desk: Desk(notes: [:], saved: SavedDesk()), grid: grid, visibility: visibility,
                  shortcut: ShortcutReading(display: "⌃⌥I", works: true), spreadCells: .standard, now: Date())
    }

    func testTheStackComesFromTheGridAndShrinksToItsRibbonUnderHideAll() {
        let shown = Surfaces(world(), aim: Aim(anchor: .stack), measure: { _ in nil })
        let hidden = Surfaces(world(.hideAll), aim: Aim(anchor: .stack), measure: { _ in nil })

        XCTAssertEqual(shown.screen, grid.area)
        XCTAssertEqual(shown.stack, face(4))
        XCTAssertEqual(hidden.stack, CGRect(x: 1203, y: 957, width: 294, height: 40))
        XCTAssertTrue(hidden.allHidden)
    }

    func testAStackBeingDraggedIsWhereItsWindowIsNotWhereTheGridSays() {
        let dragged = CGRect(x: 640, y: 380, width: 300, height: 250)
        let controls: [RibbonControl: CGRect] = [.new: CGRect(x: 660, y: 597, width: 18, height: 18)]
        let s = Surfaces(world(), aim: Aim(anchor: .control(.new)), measure: { what in
            switch what {
            case .stack: dragged
            case .control(let control): controls[control]
            default: nil
            }
        })

        XCTAssertEqual(s.stack, dragged.insetBy(dx: 3, dy: 3), "the window's face, inside its 3 pt gap")
        XCTAssertEqual(s.controls, controls)
    }

    func testTheMenuBarIconIsMeasuredForItsRing() {
        let icon = CGRect(x: 1320, y: 1000, width: 30, height: 24)
        let s = Surfaces(world(), aim: Aim(anchor: .stackTop, ring: .menuBarIcon), measure: { $0 == .menuBarIcon ? icon : nil })

        XCTAssertEqual(s.menuBarIcon, icon)
    }
}
