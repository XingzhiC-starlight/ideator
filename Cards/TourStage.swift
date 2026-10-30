import AppKit

// The tour's windows: AppKit only, no decisions.

/// The real `TourScreen`: a hint panel and a click-through overlay.
final class TourStage: TourScreen {
    var onInput: (TourInput) -> Void = { _ in }

    func size(of card: HintCard, faceWidth: CGFloat) -> CGSize { fatalError("not implemented") }

    func show(_ scene: TourScene, takesKey: Bool) { fatalError("not implemented") }

    func hide() { fatalError("not implemented") }
}

/// The hint: a 316 pt face (322 pt window) in the card look with the tour's tint. Non-activating, so
/// a click on it never activates Ideator (page 5 would read that as "Back in front"); floating, so it
/// stays readable when the cards drop behind another app; key only when the reader clicks into it,
/// so a click on Next ends a card's editing like any click elsewhere.
final class HintPanel: NSPanel {
    var onInput: (TourInput) -> Void = { _ in }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        hidesOnDeactivate = false
        // The "couldn't read your notes" alert can be up as page 1 appears.
        worksWhenModal = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        title = "Ideator tour"   // a borderless window never draws it; VoiceOver and the verify harness read it
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func apply(_ card: HintCard) { fatalError("not implemented") }
}

extension TourLine {
    /// Chips and key caps as measured attachments, text in `font` and `ink`.
    func attributed(font: NSFont, ink: NSColor) -> NSAttributedString { fatalError("not implemented") }
}

/// One borderless, clear, click-through window the size of the grid's screen. Draws, from a
/// `Pointing`, the lit cells, each ring and the panel's notch.
final class GuideOverlay: NSWindow {
    func apply(_ pointing: Pointing) { fatalError("not implemented") }
}
