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
    /// The only place the app's pieces are named for the tour. The shortcut "works" as today's
    /// welcome reads it: `HotKey.problem == nil`.
    static func live(controller: DeskController, hotKey: HotKey, spread: SpreadChoice, statusItem: NSStatusItem?,
                     notesFolder: URL, backToWelcome: @escaping () -> Void) -> TourSources {
        TourSources(
            world: {
                TourWorld(desk: controller.desk, grid: controller.grid, visibility: controller.visibility,
                          shortcut: ShortcutReading(display: hotKey.shortcut.display, works: hotKey.problem == nil),
                          spreadCells: spread.cells, now: Date())
            },
            measure: { measure in
                switch measure {
                case .control(let control): controller.rect(of: control)
                case .hoverCorner(let id): controller.hoverCorner(of: id)
                case .menuBarIcon: statusItem?.button?.window?.frame
                case .stack: controller.stackFrame
                case .card(let id): controller.cardFrame(of: id)
                }
            },
            holdHover: { controller.heldHover = $0 },
            isActive: { NSApp.isActive },
            watch: { send in
                controller.onSettle = { send(.deskSettled) }
                let space = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { send(.happened(.space)) }
                }
                let resign = NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { send(.happened(.appFront)) }
                }
                let become = NotificationCenter.default.addObserver(
                    forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { send(.happened(.cardsFront)) }
                }
                return {
                    controller.onSettle = nil
                    NSWorkspace.shared.notificationCenter.removeObserver(space)
                    NotificationCenter.default.removeObserver(resign)
                    NotificationCenter.default.removeObserver(become)
                }
            },
            openNotesFolder: { NSWorkspace.shared.open(notesFolder) },
            backToWelcome: backToWelcome)
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
    /// Where the panel and the rings go for an aim in a world. `measure` answers for what only a
    /// live window can say, `panel` for the window size the screen needs at a face width. A seam so a
    /// test can run the session without a screen; `TourSession.layout` is the real one.
    typealias Pointer = (_ aim: Aim, _ world: TourWorld, _ measure: (Measure) -> CGRect?,
                         _ panel: (_ faceWidth: CGFloat) -> CGSize) -> Pointing

    static let layout: Pointer = { aim, world, measure, panel in
        let surfaces = Surfaces(world, aim: aim, measure: measure)
        let size = panel(TourLayout.faceWidth(screenWidth: surfaces.screen.width))
        return TourLayout.point(aim, at: surfaces, panel: size)
    }

    private(set) var flow = TourFlow()
    private let sources: TourSources
    private let screen: TourScreen
    private let pointer: Pointer
    private var stopWatching: (() -> Void)?
    private var lastScene: TourScene?
    private var heldHover: CardID?
    /// The last page's panel took key since it was last on screen as a new page.
    private var tookKey = false

    init(sources: TourSources, screen: TourScreen, pointer: @escaping Pointer = TourSession.layout) {
        self.sources = sources
        self.screen = screen
        self.pointer = pointer
        screen.onInput = { [weak self] in self?.receive($0) }
    }

    var isRunning: Bool { flow.stop != nil }

    /// Starts, or restarts, the tour. "Show the Tour" and the welcome's buttons both come here.
    func start(_ start: TourStart) { receive(.begin(start)) }

    /// The one door: the panel's buttons, the desk's settle and the system's notifications.
    /// Subscribes at the first start and unsubscribes when the tour ends, so a desk with no tour
    /// running costs the controller one nil check.
    func receive(_ input: TourInput) {
        if case .begin = input {
            stopWatching = stopWatching ?? sources.watch { [weak self] in self?.receive($0) }
        } else if !isRunning {
            return
        }
        let world = sources.world()
        switch flow.apply(input, in: world) {
        case .showWelcome?:
            // Ordered out, not covered: two "Skip the tour" buttons must never be on screen at once.
            end()
            sources.backToWelcome()
        case .openNotesFolder?:
            end()
            sources.openNotesFolder()
        case nil:
            redraw(world)
        }
    }

    /// Card, then surfaces, then layout, then scene. Shows nothing new when the scene equals the last,
    /// so a keystroke that moved no window costs a world and a comparison.
    private func redraw(_ world: TourWorld) {
        guard let stop = flow.stop else { return end() }
        let card = stop.card(in: world)
        let aim = stop.phase.script.aim
        let held = aim.showsHoverButtons ? world.readerCard : nil
        if held != heldHover {
            heldHover = held
            sources.holdHover(held)
        }
        let pointing = pointer(aim, world, sources.measure) { [screen] width in
            screen.size(of: card, faceWidth: width)
        }
        let scene = TourScene(card: card, pointing: pointing, heldHover: held)
        guard scene != lastScene else { return }
        lastScene = scene
        screen.show(scene, takesKey: takesKey(on: stop.phase))
    }

    /// Page 9 is where Return should press "Start using Ideator", so its panel takes key, once per
    /// showing and only while Ideator is the active app: a start by the AI tools' helper leaves it
    /// inactive, and a Return typed in the tool must stay there.
    private func takesKey(on phase: TourPhase) -> Bool {
        guard phase == .done else {
            tookKey = false
            return false
        }
        guard !tookKey, sources.isActive() else { return false }
        tookKey = true
        return true
    }

    /// Orders every tour window out, releases the held hover and stops listening. Safe to call twice.
    private func end() {
        stopWatching?()
        stopWatching = nil
        if heldHover != nil {
            heldHover = nil
            sources.holdHover(nil)
        }
        lastScene = nil
        tookKey = false
        screen.hide()
    }
}
