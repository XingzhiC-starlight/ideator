import Foundation

// The world the tour reads, the events it derives, its position and the reducer. Pure: no AppKit.

// MARK: What the tour may read

struct ShortcutReading: Equatable {
    var display: String
    /// `HotKey.problem == nil`, as today's welcome reads it.
    var works: Bool
}

/// Everything outside the tour that its pages read, built fresh on every look and never cached
/// across looks: Settings changes the shortcut and the ticked cells with no notification. A class
/// only so `facts` and `spreadPreview` are computed at most once per look. It holds `Desk` by value
/// for one look and is then dropped; the tour keeps `TourFacts` between looks, never a world.
final class TourWorld {
    let desk: Desk
    let grid: Grid
    let visibility: Visibility
    let shortcut: ShortcutReading
    let spreadCells: SpreadCells
    let now: Date

    init(desk: Desk, grid: Grid, visibility: Visibility, shortcut: ShortcutReading, spreadCells: SpreadCells, now: Date) {
        self.desk = desk
        self.grid = grid
        self.visibility = visibility
        self.shortcut = shortcut
        self.spreadCells = spreadCells
        self.now = now
    }

    /// The reader's card: the first desktop card, in reading order, that is not in the Spread set.
    /// Hidden cards still count (Hide all orders windows out; the desk is unchanged).
    var readerCard: CardID? { facts.loose.first }

    /// The cells a Spread click would put blank cards into right now, from a dry run of the desk's
    /// own rule on a copy. Empty while a set card is out: the button then gathers.
    lazy var spreadPreview: [Slot] = { fatalError("not implemented") }()

    var freeSpreadCells: Int { spreadPreview.count }

    /// Page 6: a click would act, or there is a set out to gather.
    var spreadCanAct: Bool { desk.spreadButton.isOut || !spreadPreview.isEmpty }

    lazy var facts: TourFacts = { fatalError("not implemented") }()
}

/// What the tour remembers of the last look: just enough to tell what happened since.
struct TourFacts: Equatable {
    var isHidden: Bool
    /// Desktop cards outside the Spread set, in reading order. `first` is the reader's card.
    var loose: [CardID]
    /// Cards on the desktop plus cards in the stack. A card that leaves `loose` with this unchanged
    /// was returned to the stack; with it smaller, deleted.
    var total: Int
    /// Some card of the Spread set is on the desktop (`spreadButton.isOut`).
    var setOut: Bool

    /// The events between two looks, found by comparing. Equal facts give none.
    static func events(from old: TourFacts, to new: TourFacts) -> [TourEvent] { fatalError("not implemented") }
}

// MARK: The position

/// Where the tour is: the phase says whether it waits (from the script), the reading says why the
/// text is what it is.
struct Stop: Equatable {
    var phase: TourPhase
    var reading: Reading

    /// What the hint panel says: the reaction if there is one, else the phase's title and body.
    func card(in world: TourWorld) -> HintCard { fatalError("not implemented") }
}

/// What the hint panel shows, as plain data.
struct HintCard: Equatable {
    /// "3 of 9".
    var progress: String
    /// Draws "OPTIONAL" after the progress.
    var isOptional: Bool
    /// False on the last page.
    var canSkip: Bool
    var title: TourLine
    var body: TourLine
    var footer: PhaseScript.Footer
}

/// Everything that can change the tour's page.
enum TourInput: Equatable {
    /// A welcome button, or "Show the Tour" (always `.firstPage`).
    case begin(TourStart)
    /// The hint panel's buttons.
    case next, back, skip, finish
    /// The system: `.space`, `.appFront`, `.cardsFront`. A phase that has no use for it ignores it.
    case happened(TourEvent)
    /// The desk or a window moved: derive events from the last look, then follow the world.
    case deskSettled
}

/// What the shell must do that the flow cannot.
enum TourEffect: Equatable {
    /// Back from page 1: the tour is over until the welcome's button starts it again.
    case showWelcome
    /// Page 9's button: the tour is over.
    case openNotesFolder
}

/// The tour as a value. `apply` is the only mutation, and everything it needs comes in as
/// arguments, so a test drives it with hand-built worlds and no window.
struct TourFlow: Equatable {
    /// Nil: no tour is running.
    private(set) var stop: Stop?
    private var seen: TourFacts?

    /// Ignored while no tour runs, except `.begin`.
    mutating func apply(_ input: TourInput, in world: TourWorld) -> TourEffect? { fatalError("not implemented") }
}
