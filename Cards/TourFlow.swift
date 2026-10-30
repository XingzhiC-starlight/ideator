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
    /// own rule on a copy, so the free-cell rule lives in `Desk.swift` alone. `fresh` leaves a set
    /// waiting in the stack out of the count, as the prototype counts the ticked cells that are not
    /// taken; with no set card on the desktop it sweeps nothing, so only the small `popped` array
    /// is copied. Empty while a set card is out: the button then gathers, and there is nothing to light.
    lazy var spreadPreview: [Slot] = {
        guard !desk.spreadButton.isOut else { return [] }
        var trial = desk
        _ = trial.apply(.spread(spreadCells, fresh: true, at: now))
        let before = Set(desk.popped.map(\.card.id))
        return trial.popped.filter { !before.contains($0.card.id) }.map(\.place.slot)
    }()

    var freeSpreadCells: Int { spreadPreview.count }

    /// Page 6: a click would act, or there is a set out to gather.
    var spreadCanAct: Bool { desk.spreadButton.isOut || !spreadPreview.isEmpty }

    /// What the tour remembers of this look. The loose cards are sorted by `Place.readingKey`, then
    /// by id: the tie-break of `Desk.inReadingOrder`, which is private to the desk.
    lazy var facts: TourFacts = {
        let set = desk.spreadSet
        let loose = desk.popped
            .filter { !(set?.contains($0.card.id) ?? false) }
            .sorted { a, b in
                let (keyA, keyB) = (a.place.readingKey, b.place.readingKey)
                return keyA != keyB ? keyA < keyB : a.card.id < b.card.id
            }
        return TourFacts(isHidden: visibility.isHidden, loose: loose.map(\.card.id),
                         total: desk.stack.count + desk.popped.count, setOut: desk.spreadButton.isOut)
    }()
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

    /// The events between two looks, found by comparing, the way `render()` compares the desk with
    /// its windows. Equal facts give none, so a second look at the same world, a refused Spread, a
    /// Hide all while hidden and typing are all silent.
    ///
    /// Only the reader's card (the old `loose.first`) can return or delete. A new card is one more
    /// card in total that is loose now and was not before: a Pop keeps the total, an AI tool's card
    /// lands in the stack and never in `loose`, and a Spread's blank cards belong to the set.
    static func events(from old: TourFacts, to new: TourFacts) -> [TourEvent] {
        var events: [TourEvent] = []
        if old.isHidden != new.isHidden { events.append(new.isHidden ? .hidden : .shown) }
        if let reader = old.loose.first, !new.loose.contains(reader) {
            events.append(new.total < old.total ? .deleted : .returned)
        }
        if new.total == old.total + 1, new.loose.contains(where: { !old.loose.contains($0) }) { events.append(.new) }
        if !old.setOut && new.setOut { events.append(.spreadOut) }
        if old.setOut && !new.setOut { events.append(new.total < old.total ? .vanished : .gathered) }
        return events
    }
}

// MARK: The position

/// Where the tour is: the phase says whether it waits (from the script), the reading says why the
/// text is what it is.
struct Stop: Equatable {
    var phase: TourPhase
    var reading: Reading

    /// What the hint panel says: the reaction if there is one, else the phase's title and body.
    func card(in world: TourWorld) -> HintCard {
        let script = phase.script
        let context = TourContext(world: world, reading: reading)
        var title = script.title(context)
        var body = script.body(context)
        if case .reacted(let event) = reading, let reaction = script.reactions[event] {
            title = reaction.title
            body = reaction.body
        }
        return HintCard(progress: "\(phase.page) of \(TourPhase.pageCount)", isOptional: script.isOptional,
                        canSkip: phase.page < TourPhase.pageCount, title: title, body: body, footer: script.footer)
    }
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
    ///
    /// - begin: the first page or the last; what is already on the desk is not news, so `seen`
    ///   starts as this look.
    /// - next: the next page's opening, with its neutral text. A phase that waits has no Next, so
    ///   the input is ignored there, as the footer's missing button is.
    /// - back: page 1 ends the tour for the welcome; any other page lands on the previous page's
    ///   finished phase, neutral text, whatever phase it left.
    /// - skip: the last page. finish: only the last page's button, and it ends the tour.
    /// - happened and deskSettled: every event ends the wait that names it, or is answered in
    ///   place by a page that reacts to it, and is otherwise ignored.
    ///
    /// After every input a phase sitting on its fresh opening is chosen again from the live world
    /// (Settings changes Spread's cells with no notification). A finished wait never asks a gate.
    mutating func apply(_ input: TourInput, in world: TourWorld) -> TourEffect? {
        if case .begin(let start) = input {
            let page = start == .firstPage ? 1 : TourPhase.pageCount
            stop = Stop(phase: TourScript.entry(of: page, in: world), reading: .fresh)
            seen = world.facts
            return nil
        }
        guard let current = stop else { return nil }
        switch input {
        case .begin:
            break
        case .next:
            if current.phase.script.waitsFor.isEmpty, let next = TourScript.following(current.phase, in: world) {
                stop = Stop(phase: next, reading: .fresh)
            }
        case .back:
            if current.phase.page == 1 {
                self = TourFlow()
                return .showWelcome
            }
            stop = Stop(phase: TourScript.landing(of: current.phase.page - 1, in: world), reading: .fresh)
        case .skip:
            stop = Stop(phase: TourScript.entry(of: TourPhase.pageCount, in: world), reading: .fresh)
        case .finish:
            if current.phase.script.footer == .backAndStartUsing {
                self = TourFlow()
                return .openNotesFolder
            }
        case .happened(let event):
            handle(event)
        case .deskSettled:
            let now = world.facts
            if let before = seen {
                for event in TourFacts.events(from: before, to: now) { handle(event) }
            }
            seen = now
        }
        follow(world)
        return nil
    }

    private mutating func handle(_ event: TourEvent) {
        guard let current = stop else { return }
        let script = current.phase.script
        if script.waitsFor.contains(event) {
            stop = Stop(phase: TourScript.after(current.phase), reading: .after(event))
        } else if script.reactions[event] != nil {
            stop?.reading = .reacted(event)
        }
    }

    private mutating func follow(_ world: TourWorld) {
        guard let current = stop, current.reading == .fresh, current.phase.script.followsWorld else { return }
        stop?.phase = TourScript.entry(of: current.phase.page, in: world)
    }
}
