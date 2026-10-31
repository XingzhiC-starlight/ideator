import Foundation

// Where everything goes: the prototype's formulas, in AppKit screen points. Pure: no AppKit.

/// Rects the layout needs, in AppKit screen points (bottom-left origin). The measured ones come
/// from the live windows; the rest are computed from the world.
struct Surfaces: Equatable {
    /// The grid's area: the screen below the menu bar.
    var screen: CGRect
    /// The stack's face: the full cell's, or the ribbon-only strip's under Hide all.
    var stack: CGRect
    /// Hide all is on: of the ribbon's buttons only Hide/Show keeps its ring, as in the prototype.
    var allHidden: Bool
    /// Measured against the stack window's destination frame, so a slide in progress never misleads.
    var controls: [RibbonControl: CGRect]
    var readerFace: CGRect?
    /// The reader's live hover row; nil while its window is ordered out (Hide all).
    var hoverCorner: CGRect?
    var menuBarIcon: CGRect?
    /// Faces of `world.spreadPreview`'s cells, when the aim lights them.
    var litFaces: [CGRect]

    /// The pure half comes from the world, the AppKit half from `measure`. A window's live frame wins
    /// over the grid's, so the panel follows a stack or card the reader is dragging. Only what `aim`
    /// uses is read: the reader's card and the Spread dry run cost a look at the desk each.
    init(_ world: TourWorld, aim: Aim, measure: (Measure) -> CGRect?) {
        let grid = world.grid
        screen = grid.area
        allHidden = world.visibility.isHidden
        let stackCell = grid.frame(of: world.desk.stackPlace)
        let stackWindow = measure(.stack)
            ?? (world.visibility.showsStackCard ? stackCell : StackWindow.ribbonOnlyFrame(in: stackCell))
        stack = Self.face(of: stackWindow)
        var controls: [RibbonControl: CGRect] = [:]
        for control in RibbonControl.allCases { controls[control] = measure(.control(control)) }
        self.controls = controls
        let reader = aim.anchor == .readerCard || aim.ring == .hoverCorner ? world.readerCard : nil
        readerFace = reader.flatMap { id in
            (measure(.card(id)) ?? world.desk.place(of: .card(id)).map { grid.frame(of: $0) }).map { Self.face(of: $0) }
        }
        hoverCorner = aim.ring == .hoverCorner ? reader.flatMap { measure(.hoverCorner($0)) } : nil
        menuBarIcon = aim.ring == .menuBarIcon ? measure(.menuBarIcon) : nil
        litFaces = aim.litCells ? world.spreadPreview.map { Self.face(of: grid.frame(of: $0)) } : []
    }

    init(screen: CGRect, stack: CGRect, allHidden: Bool = false, controls: [RibbonControl: CGRect],
         readerFace: CGRect? = nil, hoverCorner: CGRect? = nil, menuBarIcon: CGRect? = nil, litFaces: [CGRect] = []) {
        self.screen = screen
        self.stack = stack
        self.allHidden = allHidden
        self.controls = controls
        self.readerFace = readerFace
        self.hoverCorner = hoverCorner
        self.menuBarIcon = menuBarIcon
        self.litFaces = litFaces
    }

    /// A card window's or cell's visible face: inside the gap every card keeps around it.
    static func face(of frame: CGRect) -> CGRect { frame.insetBy(dx: CardShape.gap, dy: CardShape.gap) }
}

/// The things only a live window or the status item can say. `stack` and `card` are the windows'
/// frames, live while the reader drags them, and not the grid's.
enum Measure: Equatable { case control(RibbonControl), hoverCorner(CardID), menuBarIcon, stack, card(CardID) }

/// `at`: the offset along the panel's edge, from its leading end.
enum Notch: Equatable { case left(at: CGFloat), right(at: CGFloat), top(at: CGFloat) }

/// `rect` is already padded.
struct RingShape: Equatable {
    var rect: CGRect
    var radius: CGFloat
}

/// Everything the overlay and the panel need to be placed, in AppKit screen points. The overlay
/// draws the notch over the panel's edge, so the panel stays a plain card.
struct Pointing: Equatable {
    /// The panel window: the face plus `CardShape.gap` on every side.
    var panel: CGRect
    var notch: Notch?
    var rings: [RingShape]
    /// Faces of the lit cells.
    var lit: [CGRect]
    /// A menu bar ring is drawn above the menu bar.
    var needsMenuBarLevel: Bool
}

enum TourLayout {
    /// The panel's distance from what it points at, and its margins: the prototype's numbers.
    private static let reach: CGFloat = 16
    private static let screenMargin: CGFloat = 8
    private static let belowMenuBar: CGFloat = 10
    /// Room kept above the bottom edge, for the Dock.
    private static let aboveBottom: CGFloat = 70
    /// The notch stays this far from the panel's corners.
    private static let notchInset: CGFloat = 18

    /// 316 on a screen 1300 pt or wider, else max(240, min(316, cellWidth - 28)).
    static func faceWidth(screenWidth: CGFloat) -> CGFloat {
        if screenWidth >= 1300 { return 316 }
        let cellWidth = (screenWidth / CGFloat(Slot.columns)).rounded()
        return max(240, min(316, cellWidth - 28))
    }

    /// `panelSize` is the measured window size (the shell fits the card at `faceWidth + 2 * gap`).
    ///
    /// The prototype's `renderGuide`, with two additions for what its fixed stack never met: the
    /// panel changes sides when its side has no room (the stack in the left column, the reader's card
    /// in the right one, the stack in the bottom row for `.belowStack`), so it never covers what it
    /// points at; and the notch is aimed after the screen clamps, so a clamped panel still points at
    /// its target.
    static func point(_ aim: Aim, at s: Surfaces, panel panelSize: CGSize) -> Pointing {
        let face = CGSize(width: panelSize.width - 2 * CardShape.gap, height: panelSize.height - 2 * CardShape.gap)
        var spot = place(aim.anchor, at: s, face: face)
        spot.x = min(max(spot.x, s.screen.minX + screenMargin), s.screen.maxX - face.width - screenMargin)
        spot.top = max(spot.top, s.screen.minY + aboveBottom + face.height)
        let panel = CGRect(x: spot.x, y: spot.top - face.height, width: face.width, height: face.height)

        let ringed = aim.ring.flatMap { ring(for: $0, at: s) }
        return Pointing(panel: panel.insetBy(dx: -CardShape.gap, dy: -CardShape.gap),
                        notch: spot.notch(on: panel),
                        rings: ringed.map { [$0] } ?? [],
                        lit: aim.litCells ? s.litFaces : [],
                        needsMenuBarLevel: aim.ring == .menuBarIcon && ringed != nil)
    }

    /// Where the face goes before the screen clamps, and what its notch points at.
    private struct Spot {
        enum Side { case left, right, top }
        var x: CGFloat
        /// The face's top edge.
        var top: CGFloat
        var side: Side
        /// The y (left and right sides) or x (top) the notch points at.
        var target: CGFloat

        func notch(on face: CGRect) -> Notch {
            switch side {
            case .left: .left(at: clamp(face.maxY - target, within: face.height))
            case .right: .right(at: clamp(face.maxY - target, within: face.height))
            case .top: .top(at: clamp(target - face.minX, within: face.width))
            }
        }

        private func clamp(_ offset: CGFloat, within length: CGFloat) -> CGFloat {
            min(max(offset, TourLayout.notchInset), length - TourLayout.notchInset)
        }
    }

    private static func place(_ anchor: Anchor, at s: Surfaces, face: CGSize) -> Spot {
        let highest = s.screen.maxY - belowMenuBar
        switch anchor {
        case .readerCard:
            guard let card = s.readerFace else { return place(.stack, at: s, face: face) }
            let top = min(highest, card.maxY - 2)
            let target = card.maxY - 17
            let right = card.maxX + reach
            if right + face.width <= s.screen.maxX - screenMargin {
                return Spot(x: right, top: top, side: .left, target: target)
            }
            let left = card.minX - reach - face.width
            return left >= s.screen.minX + screenMargin
                ? Spot(x: left, top: top, side: .right, target: target)
                : Spot(x: right, top: top, side: .left, target: target)
        case .belowStack:
            let top = s.stack.minY - reach
            guard top - face.height >= s.screen.minY + aboveBottom else { return place(.stack, at: s, face: face) }
            return Spot(x: s.stack.maxX - face.width, top: top, side: .top, target: s.stack.midX)
        case .stack, .stackTop, .control:
            var target = s.stack.maxY - 23
            if case .control(let control) = anchor, let rect = s.controls[control] { target = rect.midY }
            var top = min(highest, target + 28)
            if anchor == .stackTop {
                top = s.stack.maxY - 2
                target = top - 28
            }
            let left = s.stack.minX - reach - face.width
            if left >= s.screen.minX + screenMargin {
                return Spot(x: left, top: top, side: .right, target: target)
            }
            let right = s.stack.maxX + reach
            return right + face.width <= s.screen.maxX - screenMargin
                ? Spot(x: right, top: top, side: .left, target: target)
                : Spot(x: left, top: top, side: .right, target: target)
        }
    }

    /// A ribbon button in the prototype: an 18 pt square around its 13 pt icon.
    private static let buttonSide: CGFloat = 18

    /// The prototype's pads and radii: the whole stack 5 and 15, a button or the hover row 5 and 9,
    /// the menu bar icon 3 and 7. A ribbon button is ringed by its 18 pt square: the ribbon widens
    /// each button's hit area to space the icons by their ink, and a ring around that would crowd
    /// the icons beside it. Under Hide all only Hide/Show keeps its ring among the ribbon's buttons;
    /// the hover row has none, since its card is ordered out.
    private static func ring(for target: RingTarget, at s: Surfaces) -> RingShape? {
        func padded(_ rect: CGRect?, _ pad: CGFloat, _ radius: CGFloat) -> RingShape? {
            rect.map { RingShape(rect: $0.insetBy(dx: -pad, dy: -pad), radius: radius) }
        }
        switch target {
        case .stack: return padded(s.stack, 5, 15)
        case .control(let control):
            guard !s.allHidden || control == .hideShow, let button = s.controls[control] else { return nil }
            let square = CGRect(x: button.midX - buttonSide / 2, y: button.midY - buttonSide / 2,
                                width: buttonSide, height: buttonSide)
            return padded(square, 5, 9)
        case .hoverCorner: return padded(s.hoverCorner, 5, 9)
        case .menuBarIcon: return padded(s.menuBarIcon, 3, 7)
        }
    }
}
