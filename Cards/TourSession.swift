import AppKit

/// Everything the session needs from outside, as closures. Nothing here sends a `Command`: the tour
/// can look, measure, hold one card's hover buttons open and open Finder, and that is the whole
/// "never creates, moves or deletes cards" guarantee, in the type.
struct TourSources {
    /// A fresh look at everything the pages read.
    var world: () -> TourWorld
    /// A live window's or the status item's rect, in AppKit screen points; nil when it is not on screen.
    var measure: (Measure) -> CGRect?
    /// Keep this card's hover buttons shown whatever the pointer does (page 4); nil releases.
    var holdHover: (CardID?) -> Void
    /// Whether Ideator is the active app. Page 9's panel takes key only then, once per showing, so a
    /// background start never takes a Return typed in the AI tool.
    var isActive: () -> Bool
    /// One subscription for everything the outside can say: the controller's `onSettle`
    /// (`.deskSettled`) and the Space, resign-active and become-active notifications (`.happened`).
    /// Returns the way to stop listening to all four.
    var watch: (_ send: @escaping (TourInput) -> Void) -> () -> Void
    /// Page 9: the run's notes folder, never `WelcomeCopy.folder`.
    var openNotesFolder: () -> Void
    /// Back from page 1: the app shows the welcome again, wired to start the tour only.
    var backToWelcome: () -> Void
}

extension TourSources {
    /// The only place the app's pieces are named for the tour.
    static func live(controller: DeskController, hotKey: HotKey, spread: SpreadChoice, statusItem: NSStatusItem?,
                     notesFolder: URL, backToWelcome: @escaping () -> Void) -> TourSources {
        fatalError("not implemented")
    }
}

/// What the session draws through: `TourStage` is the real one, a recorder is a test's.
protocol TourScreen: AnyObject {
    /// Called with the reader's button presses.
    var onInput: (TourInput) -> Void { get set }
    /// The panel window size this card needs at `faceWidth`: wrapping makes height depend on width.
    func size(of card: HintCard, faceWidth: CGFloat) -> CGSize
    /// `takesKey`: the panel is made key so Return reaches page 9's button.
    func show(_ scene: TourScene, takesKey: Bool)
    func hide()
}

struct TourScene: Equatable {
    var card: HintCard
    var pointing: Pointing
    var heldHover: CardID?
}

/// The one shell object: everything that touches the app goes through it.
final class TourSession {
    private(set) var flow = TourFlow()

    init(sources: TourSources, screen: TourScreen) { fatalError("not implemented") }

    var isRunning: Bool { flow.stop != nil }

    /// Starts, or restarts, the tour. "Show the Tour" and the welcome's buttons both come here.
    func start(_ start: TourStart) { receive(.begin(start)) }

    /// The one door: the panel's buttons, the desk's settle and the system's notifications.
    func receive(_ input: TourInput) { fatalError("not implemented") }
}
