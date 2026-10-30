import Foundation

// Where everything goes: the prototype's formulas. Pure: no AppKit.

/// Rects the layout needs, in AppKit screen points (bottom-left origin). The measured ones come
/// from the live windows; the rest are computed from the world.
struct Surfaces: Equatable {
    /// The grid's screen. Its top is the menu bar's bottom edge.
    var screen: CGRect
    var menuBarHeight: CGFloat
    /// The stack's face: the full cell, or the ribbon-only strip under Hide all.
    var stack: CGRect
    /// Measured against the stack window's destination frame, so a slide in progress never misleads.
    var controls: [RibbonControl: CGRect]
    var readerFace: CGRect?
    /// The reader's live hover row; nil while its window is ordered out (Hide all).
    var hoverCorner: CGRect?
    var menuBarIcon: CGRect?
    /// Faces of `world.spreadPreview`'s cells, when the aim lights them.
    var litFaces: [CGRect]

    /// The pure half comes from the world, the AppKit half from `measure`.
    init(_ world: TourWorld, aim: Aim, measure: (Measure) -> CGRect?) { fatalError("not implemented") }
}

/// The three things only a live window or the status item can say.
enum Measure: Equatable { case control(RibbonControl), hoverCorner(CardID), menuBarIcon }

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
    /// 316 on a screen 1300 pt or wider, else max(240, min(316, cellWidth - 28)).
    static func faceWidth(screenWidth: CGFloat) -> CGFloat { fatalError("not implemented") }

    /// `panelSize` is the measured window size (the shell fits the card at `faceWidth + 2 * gap`).
    static func point(_ aim: Aim, at surfaces: Surfaces, panel panelSize: CGSize) -> Pointing { fatalError("not implemented") }
}
