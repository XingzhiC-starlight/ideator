import Foundation

// The whole app state, as one pure value, and every rule that changes it.
// No AppKit, no files, no network: everything here is unit-testable with plain values.

// MARK: - Identity and per-card state

/// A card's identity: its Markdown file name without ".md" (for example "2026-10-21 153012").
/// Chosen once at creation and never changed, so it can key the sidecar for the card's whole
/// life. Files added by hand keep whatever name they have; the name is the identity.
struct CardID: RawRepresentable, Hashable, Comparable, Codable {
    let rawValue: String
    static func < (a: CardID, b: CardID) -> Bool { a.rawValue < b.rawValue }
}

/// Everything about one card. A `Card` value lives in exactly one place, the desktop or the
/// stack, and moves between them whole. Its summary therefore travels with it and can never be
/// orphaned or attached to the wrong card.
struct Card: Equatable {
    let id: CardID
    var note: Note { didSet { digest = note.digest } }
    /// Fingerprint of `note`. Kept in step by `note`'s observer, never assigned anywhere else.
    private(set) var digest: Digest
    /// The latest summary attempt. It describes the current note only while
    /// `summary.source == digest`; a stale one is simply ignored, never cleared.
    var summary: Summary?

    init(id: CardID, note: Note, summary: Summary? = nil) {
        self.id = id
        self.note = note
        self.digest = note.digest
        self.summary = summary
    }
}

/// One summary attempt for one version of a note. A failure is kept like a success, so the card
/// shows "Summary unavailable" until the note changes, the user presses refresh, or the key
/// changes. Only `.text` outcomes are persisted (see `SavedSummary`), so a relaunch retries
/// failures. Within one run every summary came from the current prompt, so a summary does not
/// record it; the sidecar does (`SavedSummary.prompt`).
struct Summary: Equatable {
    let source: Digest
    let outcome: Outcome

    enum Outcome: Equatable {
        case text(String)
        case failed(reason: String)
    }
}

extension Summary {
    /// The system prompt for the summary model.
    static let instructions = """
        You write the summary shown on a collapsed note card. It reminds the user what the card is.

        Write the whole summary in the language the note is written in. A note in English gets a \
        summary in English, and a note in Chinese, Japanese or any other language gets one in that \
        language. Names and terms from another language inside a note do not change its language. \
        Never translate, and never take the language from the examples in these instructions.

        The note's first line is its title, which the card already shows above your summary (it may \
        be empty). Don't just repeat the title. Name the topic in your own words.

        Start with what kind of card it is and what it is about, then add at most two points of its \
        gist, if they fit within the length limit below, like "Meeting notes on the office move: lease \
        signed, movers booked for May". Never add a third point, even when the note has more and it \
        would fit. Choose the kind yourself, in the note's language. For a note \
        in English, choose a kind such as to-do list, thoughts, plan, meeting notes, draft, question, \
        links or ideas, and if none fits, write "Notes on" and the topic. For a note in Chinese, \
        choose a kind such as 待办清单, 想法, 计划 or 会议记录, and if none fits, write "笔记：" and \
        the topic. A note in any other language gets a kind in that language.

        Only lines starting with "[ ]" or "[x]" make a to-do list: "[ ]" lines are open to-dos and \
        "[x]" lines done ones. For a to-do list, say how many are done and name only the open items, \
        like "To-do list for the Tokyo trip, 2 of 5 done: hotel, charger, visa". If every item is \
        done, say only that, like "To-do list for the party, all 4 done", and name none of them. A \
        numbered or bulleted list without those marks is not a to-do list. Call it a plan, a list or \
        whatever kind fits, and give its one or two main points, never every item, even when every \
        item would fit.

        If the note has little content, keep the summary short, at most half the length limit: about 8 \
        words, or 30 characters in Chinese, Japanese or Korean, like "Question about a resizable \
        sidebar". Infer what the card is for, but never invent details the note does not contain, and \
        never pad the summary to make it longer.

        The length limit is a hard ceiling, not a target. Write a single sentence, never a second one \
        for a next step or an aside. Never write more than 120 characters, which is about 18 words, \
        and aim for 12 to 16 words. For a note in Chinese, Japanese or Korean, never write more than 60 \
        characters, and aim for 40 to 50. English names and terms use that up fast, because each of \
        their letters counts as one character, so in such a note name at most two of them and leave \
        out the rest, such as key prefixes, version numbers, IDs and links. Only a to-do list names \
        every open item. Write one paragraph with no line breaks.

        Reply with the summary itself and nothing else. Never explain your choices, and never comment \
        on the title or on these instructions. No preamble, no quotation marks, no Markdown.
        """

    /// Which prompt wrote a saved summary. Editing `instructions` changes it, and every saved
    /// summary stamped with another one is regenerated.
    static let prompt = Digest(of: instructions)
}

enum Direction: Equatable {
    case previous, next
}

/// Something that can be dragged around the desktop.
enum Movable: Hashable {
    case stack
    case card(CardID)
}

/// Where a card from an AI tool joins the stack: Settings' "Cards from AI tools go to".
enum Landing: Equatable {
    case top, bottom
}

/// A card on the desktop and where it is.
struct PoppedCard: Equatable {
    var card: Card
    var place: Place
}

/// What a click on the stack ribbon's Spread button does now. Derived from the desk on every render
/// (`Desk.spreadIsOut`), never stored, so it can't drift from where the set's cards are.
enum SpreadButton: Equatable {
    /// Lay the set out, or make one ("Spread cards").
    case spread
    /// A card of the set is on the desktop, so a click gathers ("Gather cards").
    case gather
}

/// The Spread button's batch of cards: which cards are in it, where each goes back to, and the
/// cells it was last laid out for. A card stays in it wherever it goes (moved, ↩ Stack, popped by
/// hand, rearranged) until it is deleted, a fresh set replaces the set, or a layout onto fewer cells
/// lets it go. Never empty: the desk holds nil instead, so "no set" has one spelling, and "every
/// card in the set was deleted" and "never spread" are the same state.
///
/// Only this file can build or change one; tests build one through `Desk(notes:saved:)` with a
/// `SavedSpread`, as the desk check's seeds do.
struct SpreadSet: Equatable {
    /// The ticked cells the last layout carried, all of them, not only those that got a card, so an
    /// unchanged Settings never moves the set. A click carrying other cells moves the set onto them.
    let cells: SpreadCells
    /// Every card of the set and where Spread puts it back. For a stacked card it is where the card
    /// last was on the desktop (or the cell a layout gave it, if it has not been out since). For a
    /// card on the desktop it is never read: every way off the desktop goes through
    /// `Desk.removePopped`, which writes it first, and a click with a set card out gathers instead
    /// of laying out.
    private(set) var homes: [CardID: Place]

    fileprivate init?(cells: SpreadCells, homes: [CardID: Place]) {
        guard !homes.isEmpty else { return nil }
        self.cells = cells
        self.homes = homes
    }

    func contains(_ id: CardID) -> Bool { homes[id] != nil }

    /// The set's cards in Spread's reading order of their homes.
    var inReadingOrder: [(id: CardID, home: Place)] {
        Desk.inReadingOrder(homes.map { (id: $0.key, home: $0.value) }, place: \.home, id: \.id)
    }

    /// A card of the set leaving the desktop from `place`. Nothing for a card not in the set, so
    /// `removePopped` can call it for every card.
    fileprivate mutating func remember(_ id: CardID, at place: Place) {
        if homes[id] != nil { homes[id] = place }
    }

    /// The set without `id`; nil when that was its last card.
    fileprivate func removing(_ id: CardID) -> SpreadSet? {
        var rest = homes
        rest[id] = nil
        return SpreadSet(cells: cells, homes: rest)
    }
}

// MARK: - Commands

/// Every way the state can change. Views, the summarizer and the folder rescan all send these to
/// `DeskController.send`; nothing else mutates a `Desk`.
enum Command {
    /// Stack toolbar "New": a blank card, popped straight out and focused. Clarity turns off, so
    /// the card opens expanded. On a full desktop it creates nothing and changes nothing else; the
    /// stack shows its blank page instead.
    case new(at: Date)
    /// The stacked card's "↗ Pop" button: the selected card comes out. Nothing while the blank page shows.
    case pop
    /// Per-card "↩ Stack" button: the card goes to the top of the stack, and the stack shows it.
    case returnToStack(CardID)
    /// Click in one of the stack's edge bands or a two-finger swipe: move around the stack's loop.
    case flipStack(Direction)
    /// The arranger moved a stacked card: it goes to `index` in the stack (0 is the top; past an
    /// end lands at that end). The other cards keep their order and the stack keeps showing the
    /// card, or the blank page, it showed. A card that is not stacked is ignored.
    case arrange(CardID, at: Int)
    /// The arranger's row: the stack shows this stacked card. A card that is not stacked is ignored.
    case showStacked(CardID)
    /// The first character typed on the stack's blank page, which turns Clarity off like New.
    /// Only meaningful while it shows.
    case writeBlank(Note, at: Date)
    /// A card's header or the stack's ribbon was dragged and released (`Place.dropped(at:)`).
    /// Onto a slot held by another snapped item, the two swap.
    case move(Movable, to: Place)
    /// Trash button, after the user confirmed "Delete this card?".
    case delete(CardID)
    /// Every text change in a card's editor.
    case edit(CardID, Note)
    /// The stack ribbon's Clarity button, or a click on a collapsed card's body (`false`). Every
    /// card, popped or stacked, follows it.
    case setClarity(Bool)
    /// Per-card refresh button: forget the summary so a new one is requested now.
    case refreshSummary(CardID)
    /// Settings saved or removed the key: forget every failed summary so each card tries again.
    case forgetFailedSummaries
    /// A summary request finished. Dropped if the note changed while it was in flight.
    case storeSummary(CardID, Summary)
    /// A rescan of the folder found this set of notes (files added, removed or edited outside).
    case syncFiles([CardID: Note])
    /// An AI tool's `add_card`: a new card joins the stack, never the desktop, and shows as Clarity says.
    /// Top puts it on top and shows it, unless `typing` (the user is typing in the stacked card, which
    /// the controller reads from the windows), which keeps the page. Bottom keeps the page.
    case addFromTool(Note, at: Date, to: Landing, typing: Bool)
    /// The stack ribbon's Spread button. `fresh` is Option-click, or New Spread in the ribbon's menu.
    /// `cells` are the cells ticked in Settings when it was pressed: the desk can't read Preferences,
    /// so they travel here, as `addFromTool`'s `Landing` does.
    /// - Not fresh, with any card of the set on the desktop: Gather. Those cards go to the bottom of
    ///   the stack in reading order of their places, each remembering its place, and the stack keeps
    ///   its page. `cells` is not read, so a Settings change waits for the next Spread.
    /// - Otherwise the set is laid out on `cells`. Fresh first sends the old set's desktop cards to
    ///   the bottom of the stack as ordinary cards and drops the set. A set laid out for these same
    ///   cells puts each card back at its home. With other cells, or no set, the card in the first
    ///   old home gets the first cell and so on, cards past the last cell leave the set, and cells
    ///   past the last card get new blank cards that join it. A card comes out only where Pop's rule
    ///   finds its cell untaken and under the 19-card ceiling; one that can't stays stacked, still in
    ///   the set. New blank cards turn Clarity off, as New does; putting set cards back does not.
    /// - A layout that would put no card on the desktop changes nothing at all, the fresh sweep
    ///   included. The controller beeps on exactly that: the desk is `==` to what it was.
    case spread(SpreadCells, fresh: Bool, at: Date)

    /// The card being typed into, for the summarizer's quiet period.
    var typedCard: CardID? {
        if case .edit(let id, _) = self { id } else { nil }
    }
}

// MARK: - Desk

/// The single source of truth: where each popped card and the stack are, the stack order, which
/// stack page shows, Clarity, and (inside each `Card`) content and summary.
///
/// Invariants, all kept by construction in this file:
/// - every card is in exactly one place (one desktop entry or one stack position);
/// - no two snapped items (cards or the stack) share a slot; free ones may overlap anything;
/// - at most `Slot.count - 1` cards are on the desktop;
/// - `selection` is in `0...stack.count`;
/// - every card of `spreadSet` is a card on the desk, and the set is never empty (nil instead).
struct Desk: Equatable {
    /// The cards on the desktop, in the order they arrived.
    private(set) var popped: [PoppedCard]
    /// Where the stack window is. Top-right (`Slot.stackHome`) until moved.
    private(set) var stackPlace: Place
    /// Top card first. Its order changes when a card enters or leaves and when the arranger moves
    /// one (`Command.arrange`), never on a flip.
    private(set) var stack: [Card]
    /// The stack's loop position: the stacked card that shows, or `stack.count` for the blank
    /// page that closes the loop. Not persisted: a launch shows the top card (the blank page
    /// when the stack is empty). Every insert into or removal from `stack` goes through
    /// `insertCard` / `removeCard`, which keep it on the same page; `arrange` keeps it on the
    /// same card.
    private(set) var selection: Int
    /// Whether every card, popped or stacked, shows its summary in place of its body (the stack's
    /// Clarity button). The only collapse state there is: a card has none of its own.
    private(set) var clarity: Bool
    /// The Spread button's batch. Nil before the first Spread and again once its last card is
    /// deleted, so the next click makes a fresh set. Saved in the sidecar (`SavedDesk.spread`).
    private(set) var spreadSet: SpreadSet?

    /// Rebuilds the desk from disk. `notes` decides which cards exist; `saved` only places them.
    /// Total over any input: unknown ids, invalid or doubly-used slots and duplicates are dropped,
    /// and cards the sidecar never heard of join the bottom of the stack in id (that is, creation)
    /// order. A missing sidecar (`SavedDesk()`), or one older than this build's version, puts every
    /// card in the stack and the stack top-right. A saved summary from another prompt is dropped, so
    /// `Summarizer` asks for it again.
    init(notes: [CardID: Note], saved: SavedDesk) {
        let saved = saved.version < SavedDesk().version ? SavedDesk() : saved
        var summaries: [CardID: Summary] = [:]
        for s in saved.summaries where s.prompt == Summary.prompt {
            summaries[s.card] = Summary(source: s.source, outcome: .text(s.text))
        }
        func card(_ id: CardID) -> Card? {
            notes[id].map { Card(id: id, note: $0, summary: summaries[id]) }
        }

        func place(slot: Int?, free: GridPoint?) -> Place? {
            if let free { return .free(free) }
            return slot.flatMap { Slot(index: $0) }.map(Place.slot)
        }
        let stackPlace = place(slot: saved.stackSlot, free: saved.stackFree) ?? .slot(Slot.stackHome)
        var snapped: Set<Slot> = if case .slot(let slot) = stackPlace { [slot] } else { [] }
        var placed = Set<CardID>()
        var popped: [PoppedCard] = []
        for p in saved.placements {
            guard popped.count < Slot.count - 1, let at = place(slot: p.slot, free: p.free),
                  !placed.contains(p.card), let c = card(p.card) else { continue }
            if case .slot(let slot) = at {
                guard !snapped.contains(slot) else { continue }
                snapped.insert(slot)
            }
            popped.append(PoppedCard(card: c, place: at))
            placed.insert(p.card)
        }
        var stack: [Card] = []
        for id in saved.stack + notes.keys.sorted() where !placed.contains(id) {
            guard let c = card(id) else { continue }
            stack.append(c)
            placed.insert(id)
        }
        // The set: an entry must name a card and a valid place, and the first such entry per card
        // wins. Never dropped for being occupied: a home is a wish, checked only when Spread runs.
        var homes: [CardID: Place] = [:]
        for m in saved.spread?.members ?? [] where homes[m.card] == nil && notes[m.card] != nil {
            if let at = place(slot: m.slot, free: m.free) { homes[m.card] = at }
        }
        self.popped = popped
        self.stackPlace = stackPlace
        self.stack = stack
        self.selection = 0
        self.clarity = saved.clarity
        self.spreadSet = saved.spread.flatMap { SpreadSet(cells: SpreadCells(indices: $0.cells), homes: homes) }
    }

    // MARK: Queries

    /// Pop order: the first slot (left → right, top → bottom) that no card and not the stack
    /// takes, snapped or covering it most. Nil = "Desktop full", which also holds at 19 popped
    /// cards, since free cards piled into one slot leave others untaken.
    var firstFreeSlot: Slot? {
        let room = Occupancy(self)
        return Slot.all.first(where: room.admits)
    }

    /// Whether any card of the set is on the desktop. Both the Spread button's face and the Gather
    /// branch of `Command.spread` ask this, so the tooltip and the click never disagree.
    var spreadIsOut: Bool {
        guard let set = spreadSet else { return false }
        return popped.contains { set.contains($0.card.id) }
    }

    var allCards: [Card] { poppedCards + stack }

    /// The stacked card that shows. Nil while the blank page shows.
    var selectedCard: Card? { stack.indices.contains(selection) ? stack[selection] : nil }

    var poppedCards: [Card] { popped.map(\.card) }

    /// Where `item` is; nil for a card that is not on the desktop.
    func place(of item: Movable) -> Place? {
        switch item {
        case .stack: stackPlace
        case .card(let id): popped.first { $0.card.id == id }?.place
        }
    }

    /// A file stem for a new card: "yyyy-MM-dd HHmmss", with " 2", " 3"… if already taken.
    func freshID(at date: Date) -> CardID {
        let base = Desk.idFormat.string(from: date)
        let taken = Set(allCards.map(\.id.rawValue))
        var candidate = base
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return CardID(rawValue: candidate)
    }

    // MARK: The one mutation entry point

    /// Applies `command` and returns the card that just arrived on the desktop (the new card, the
    /// popped card, or the first new card a Spread made), if any.
    /// Every branch is total: a command naming a card that no longer exists is a no-op.
    @discardableResult
    mutating func apply(_ command: Command) -> CardID? {
        switch command {
        case .new(let date): return newCard(at: date)
        case .pop: return pop()
        case .returnToStack(let id): returnToStack(id)
        case .flipStack(let direction): flipStack(direction)
        case .arrange(let id, let index): arrange(id, at: index)
        case .showStacked(let id): showStacked(id)
        case .writeBlank(let note, let date): writeBlank(note, at: date)
        case .move(let item, let place): move(item, to: place)
        case .delete(let id): delete(id)
        case .edit(let id, let note): update(id) { $0.note = note }
        case .setClarity(let on): clarity = on
        case .refreshSummary(let id): update(id) { $0.summary = nil }
        case .forgetFailedSummaries: forgetFailedSummaries()
        case .storeSummary(let id, let summary):
            update(id) { card in if summary.source == card.digest { card.summary = summary } }
        case .syncFiles(let notes): syncFiles(notes)
        case .addFromTool(let note, let date, let landing, let typing): addFromTool(note, at: date, to: landing, typing: typing)
        case .spread(let cells, let fresh, let date): return pressSpread(cells, fresh: fresh, at: date)
        }
        return nil
    }

    // MARK: Transitions (private: `apply` is the only way in)

    private mutating func newCard(at date: Date) -> CardID? {
        guard let slot = firstFreeSlot else {
            selection = stack.count   // New refuses when the desktop is full; the blank page takes over
            return nil
        }
        clarity = false   // a new card opens expanded, so every card does
        let card = Card(id: freshID(at: date), note: .blank)
        popped.append(PoppedCard(card: card, place: .slot(slot)))
        return card.id
    }

    /// Pops the selected card into the first free slot, state intact. The page under it shows next.
    private mutating func pop() -> CardID? {
        guard let slot = firstFreeSlot, selection < stack.count else { return nil }
        let card = removeCard(at: selection)
        popped.append(PoppedCard(card: card, place: .slot(slot)))
        return card.id
    }

    /// An ordinary card forgets where it was: a later Pop takes the first free slot. A card of the
    /// Spread set remembers it for the next Spread, and stays in the set.
    private mutating func returnToStack(_ id: CardID) {
        guard let i = popped.firstIndex(where: { $0.card.id == id }) else { return }
        insertCard(removePopped(at: i), at: 0)
        selection = 0
    }

    /// The stack is a loop of its cards and one blank page after the last: `.next` moves down it
    /// and wraps from the blank page to the top card, `.previous` is the reverse. Each undoes the
    /// other, and `stack.count + 1` flips in one direction come back to the start.
    private mutating func flipStack(_ direction: Direction) {
        let pages = stack.count + 1
        selection = switch direction {
        case .next: (selection + 1) % pages
        case .previous: (selection + pages - 1) % pages
        }
    }

    /// Not built from `removeCard` / `insertCard`: those keep the *page*, so moving the shown card
    /// would advance the stack to the card under it. A move keeps the shown *card*.
    private mutating func arrange(_ id: CardID, at index: Int) {
        guard let from = stack.firstIndex(where: { card in card.id == id }) else { return }
        let to = min(max(index, 0), stack.count - 1)
        let shown = selectedCard?.id
        stack.insert(stack.remove(at: from), at: to)
        if let shown, let i = stack.firstIndex(where: { card in card.id == shown }) { selection = i }
    }

    private mutating func showStacked(_ id: CardID) {
        if let i = stack.firstIndex(where: { card in card.id == id }) { selection = i }
    }

    /// The first character typed on the blank page: it becomes a card at the bottom, in the same
    /// place in the loop, so the selection stays on it and a fresh blank page follows. Clarity turns
    /// off, as for New, so the card being typed in is expanded.
    private mutating func writeBlank(_ note: Note, at date: Date) {
        guard selection == stack.count, note != .blank else { return }
        clarity = false
        insertCard(Card(id: freshID(at: date), note: note), at: selection)
        selection -= 1
    }

    /// Drag released: `item` goes to `target`. A snapped item already in that slot takes the
    /// mover's old place, a slot or an exact free point; free items over the slot stay put.
    private mutating func move(_ item: Movable, to target: Place) {
        guard let from = place(of: item), from != target else { return }
        if case .slot = target, let occupant = snapped(at: target), occupant != item {
            setPlace(of: occupant, to: from)
        }
        setPlace(of: item, to: target)
    }

    private func snapped(at slot: Place) -> Movable? {
        if stackPlace == slot { return .stack }
        return popped.first { $0.place == slot }.map { .card($0.card.id) }
    }

    private mutating func setPlace(of item: Movable, to place: Place) {
        switch item {
        case .stack: stackPlace = place
        case .card(let id):
            if let i = popped.firstIndex(where: { $0.card.id == id }) { popped[i].place = place }
        }
    }

    /// Deleting the selected stacked card shows the one under it (the blank page after the last).
    /// The only way a card leaves the Spread set, other than Spread itself; `syncFiles` comes here
    /// for a file that vanished.
    private mutating func delete(_ id: CardID) {
        spreadSet = spreadSet?.removing(id)
        if let i = popped.firstIndex(where: { $0.card.id == id }) {
            popped.remove(at: i)
        } else if let i = stack.firstIndex(where: { $0.id == id }) {
            removeCard(at: i)
        }
    }

    /// Clears the summary of every card, popped and stacked, whose latest attempt failed.
    private mutating func forgetFailedSummaries() {
        func forget(_ card: inout Card) {
            if case .failed? = card.summary?.outcome { card.summary = nil }
        }
        for i in popped.indices { forget(&popped[i].card) }
        for i in stack.indices { forget(&stack[i]) }
    }

    /// Makes the card set equal a fresh read of the folder. Gone files remove their card (and
    /// its window), edited files replace the note, new files join the bottom of the stack in id
    /// order. Running it twice with the same input changes nothing the second time.
    private mutating func syncFiles(_ notes: [CardID: Note]) {
        for card in allCards where notes[card.id] == nil { delete(card.id) }
        for (id, note) in notes { update(id) { if $0.note != note { $0.note = note } } }
        let known = Set(allCards.map(\.id))
        for (id, note) in notes.sorted(by: { $0.key < $1.key }) where !known.contains(id) {
            insertCard(Card(id: id, note: note), at: stack.count)
        }
    }

    private mutating func addFromTool(_ note: Note, at date: Date, to landing: Landing, typing: Bool) {
        let card = Card(id: freshID(at: date), note: note)
        switch landing {
        case .top:
            insertCard(card, at: 0)
            if !typing { selection = 0 }
        case .bottom:
            insertCard(card, at: stack.count)
        }
    }

    /// See `Command.spread`. Lays out on a copy, so a layout that puts nothing out leaves the desk
    /// exactly as it was, the fresh sweep included.
    private mutating func pressSpread(_ cells: SpreadCells, fresh: Bool, at date: Date) -> CardID? {
        if !fresh, spreadIsOut, let set = spreadSet {
            stackAtBottom(popped.map(\.card.id).filter(set.contains))
            return nil
        }
        var next = self
        if fresh { next.dropSpreadSet() }
        guard let laid = next.layOut(cells, at: date) else { return nil }
        self = next
        return laid.firstNew
    }

    /// What a layout did, when it put at least one card out.
    private struct LaidOut {
        /// The first new blank card, for the controller to focus. Nil when the layout only put set
        /// cards back.
        let firstNew: CardID?
    }

    /// Lays the set out on `cells`, with no card of the set on the desktop (the caller gathered
    /// instead, or a fresh sweep dropped the set). Nil when no card came out: the caller then throws
    /// this copy away.
    private mutating func layOut(_ cells: SpreadCells, at date: Date) -> LaidOut? {
        let old = spreadSet?.inReadingOrder ?? []
        let homes: [(id: CardID, home: Place)]
        let extras: [Slot]
        if let set = spreadSet, set.cells == cells {
            homes = old
            extras = []
        } else {
            let order = cells.inReadingOrder
            homes = zip(old, order).map { (id: $0.id, home: .slot($1)) }
            extras = Array(order.dropFirst(old.count))
        }

        // Set cards first, since they hold what the user wrote, then new blank cards.
        var room = Occupancy(self)
        var cameOut = 0
        for (id, home) in homes {
            guard room.admits(home.slot),
                  let i = stack.firstIndex(where: { $0.id == id }) else { continue }
            popped.append(PoppedCard(card: removeCard(at: i), place: home))
            room.take(home.slot)
            cameOut += 1
        }
        var made: [(id: CardID, home: Place)] = []
        for cell in extras where room.admits(cell) {
            clarity = false   // Spread's new blank cards open expanded, as New's do
            let blank = Card(id: freshID(at: date), note: .blank)
            popped.append(PoppedCard(card: blank, place: .slot(cell)))
            room.take(cell)
            made.append((id: blank.id, home: .slot(cell)))
        }
        guard cameOut + made.count > 0 else { return nil }

        spreadSet = SpreadSet(cells: cells, homes: Dictionary(uniqueKeysWithValues: (homes + made).map { ($0.id, $0.home) }))
        return LaidOut(firstNew: made.first?.id)
    }

    /// Fresh: the old set's desktop cards go to the bottom of the stack as ordinary cards, its
    /// stacked cards stay where they are as ordinary cards, and the set is gone.
    private mutating func dropSpreadSet() {
        guard let set = spreadSet else { return }
        spreadSet = nil   // first, so the sweep remembers nothing
        stackAtBottom(popped.map(\.card.id).filter(set.contains))
    }

    /// These desktop cards go to the bottom of the stack in reading order of their places, through
    /// `insertCard`, so the stack keeps its page. Gather and the fresh sweep both use it.
    private mutating func stackAtBottom(_ ids: [CardID]) {
        let leaving = Desk.inReadingOrder(popped.filter { ids.contains($0.card.id) }, place: \.place, id: \.card.id)
        for one in leaving {
            guard let i = popped.firstIndex(where: { $0.card.id == one.card.id }) else { continue }
            insertCard(removePopped(at: i), at: stack.count)
        }
    }

    /// The only way a card goes from the desktop to the stack: ↩ Stack, Gather and the fresh sweep.
    /// A card of the set remembers where it was, which is where the next Spread puts it back.
    private mutating func removePopped(at i: Int) -> Card {
        let leaving = popped.remove(at: i)
        spreadSet?.remember(leaving.card.id, at: leaving.place)
        return leaving.card
    }

    /// Spread's reading order: by `Place.readingKey`, then by id, so two cards remembering the very
    /// same place still have an order. Gather, the fresh sweep, the put-back and the remap all sort
    /// with this.
    fileprivate static func inReadingOrder<T>(_ items: [T], place: (T) -> Place, id: (T) -> CardID) -> [T] {
        items.sorted { a, b in
            let (ka, kb) = (place(a).readingKey, place(b).readingKey)
            return ka != kb ? ka < kb : id(a) < id(b)
        }
    }

    /// The only way a card enters `stack`. `selection` keeps pointing at the page it pointed at.
    private mutating func insertCard(_ card: Card, at i: Int) {
        stack.insert(card, at: i)
        if i <= selection { selection += 1 }
    }

    /// The only way a card leaves `stack`. Removing the selected page leaves `selection` where it
    /// is, which is now the page that was under it.
    @discardableResult
    private mutating func removeCard(at i: Int) -> Card {
        if i < selection { selection -= 1 }
        return stack.remove(at: i)
    }

    private mutating func update(_ id: CardID, _ change: (inout Card) -> Void) {
        if let i = popped.firstIndex(where: { $0.card.id == id }) {
            change(&popped[i].card)
        } else if let i = stack.firstIndex(where: { $0.id == id }) {
            change(&stack[i])
        }
    }

    private static let idFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmmss"
        return f
    }()
}

/// Pop's rule for one more card on the desktop: not onto a cell that a card or the stack takes,
/// snapped or covering it most, and never a 20th card. The one copy of that rule, used by
/// `firstFreeSlot` (Pop, New, "Desktop full") and by Spread, which takes cells one by one as it
/// places cards.
private struct Occupancy {
    private var taken: Set<Slot>
    private var count: Int

    init(_ desk: Desk) {
        taken = Set(desk.popped.map(\.place.slot) + [desk.stackPlace.slot])
        count = desk.popped.count
    }

    func admits(_ cell: Slot) -> Bool { count < Slot.count - 1 && !taken.contains(cell) }

    mutating func take(_ cell: Slot) {
        taken.insert(cell)
        count += 1
    }
}

// MARK: - What the windows show (pure derivations)

/// Everything one card view displays. Derived; never stored.
struct CardFace: Equatable {
    let id: CardID
    let note: Note
    /// `Desk.clarity`, the same for every card.
    let collapsed: Bool
    let summary: SummaryFace
}

/// What a collapsed card shows in place of its body.
enum SummaryFace: Equatable {
    /// Empty or one-line body: no summary is ever requested; show the body itself, lighter.
    case body(String)
    /// Waiting for the quiet period to pass, or a request is in flight: spinner.
    case loading
    case text(String)
    /// "Summary unavailable"; the reason is the hover tooltip.
    case unavailable(reason: String)
}

/// One line of the stack arranger: a stacked card and the title its row shows.
struct StackRow: Equatable {
    let id: CardID
    /// `Note.title`: the header, or "Untitled" when it is empty.
    let title: String
}

struct StackFace: Equatable {
    /// The stacked cards, top first. Real cards only, never the blank page.
    let stacked: [StackRow]
    /// What the badge shows. Derived, so it can never disagree with the arranger's rows.
    var count: Int { stacked.count }
    /// The card the stack shows; nil is the blank page.
    let selected: CardFace?
    let clarity: Bool
    /// Derived from `firstFreeSlot`, so there is no "full" flag to set or clear.
    let desktopFull: Bool
    /// What the Spread button does on a click. Derived from `spreadIsOut`.
    var spreadButton = SpreadButton.spread
}

extension Desk {
    /// The popped cards and where they are, in the order they arrived.
    func cardFaces(hasKey: Bool) -> [(place: Place, face: CardFace)] {
        popped.map { ($0.place, face(of: $0.card, hasKey: hasKey)) }
    }

    func stackFace(hasKey: Bool) -> StackFace {
        StackFace(stacked: stack.map { StackRow(id: $0.id, title: $0.note.title) },
                  selected: selectedCard.map { face(of: $0, hasKey: hasKey) },
                  clarity: clarity, desktopFull: firstFreeSlot == nil,
                  spreadButton: spreadIsOut ? .gather : .spread)
    }

    private func face(of card: Card, hasKey: Bool) -> CardFace {
        CardFace(id: card.id, note: card.note, collapsed: clarity,
                 summary: Desk.summaryFace(of: card, hasKey: hasKey))
    }

    /// The whole summary lifecycle as seen by the UI, from two facts: the card's latest attempt
    /// and whether a key exists. "Loading" needs no flag: a stale or missing summary always has a
    /// request waiting or in flight (see `Summarizer.sync`).
    static func summaryFace(of card: Card, hasKey: Bool) -> SummaryFace {
        guard card.note.wantsSummary else { return .body(card.note.shortBody) }
        guard let summary = card.summary, summary.source == card.digest else {
            return hasKey ? .loading : .unavailable(reason: "No API key. Add one in Settings.")
        }
        switch summary.outcome {
        case .text(let text): return .text(text)
        case .failed(let reason): return .unavailable(reason: reason)
        }
    }
}

// MARK: - Hide all

/// What "Hide all" has hidden. Presentation only: not part of the desk and never persisted, so
/// every launch starts with `.all`.
enum Visibility: Equatable {
    case all
    /// Hide all. `revealed`: popped cards that New or Pop has shown since; `stackCard`: New on a
    /// full desktop showed the stack's blank page.
    case hidden(revealed: Set<CardID>, stackCard: Bool)

    /// Hide all: every popped card and the stack's card area go; the stack's ribbon stays.
    static let hideAll = Visibility.hidden(revealed: [], stackCard: false)

    var isHidden: Bool { self != .all }

    func shows(_ id: CardID) -> Bool {
        switch self {
        case .all: true
        case .hidden(let revealed, _): revealed.contains(id)
        }
    }

    var showsStackCard: Bool {
        switch self {
        case .all: true
        case .hidden(_, let stackCard): stackCard
        }
    }

    mutating func reveal(_ id: CardID) {
        guard case .hidden(var revealed, let stackCard) = self else { return }
        revealed.insert(id)
        self = .hidden(revealed: revealed, stackCard: stackCard)
    }

    mutating func revealStackCard() {
        guard case .hidden(let revealed, _) = self else { return }
        self = .hidden(revealed: revealed, stackCard: true)
    }

    /// What `command`, just applied to `desk`, brings back while hidden. New and Pop reveal the
    /// card they brought out. New on a full desktop reveals the stack's blank page, and the
    /// arranger's row reveals the stack's card area, so the card it turned to can be seen. Moving
    /// cards in the arranger reveals nothing.
    mutating func reveal(after command: Command, arrived: CardID?, in desk: Desk) {
        if let arrived { reveal(arrived) }
        switch command {
        case .new where arrived == nil && desk.firstFreeSlot == nil: revealStackCard()
        case .showStacked(let id) where desk.selectedCard?.id == id: revealStackCard()
        default: break
        }
    }
}

// MARK: - What the sidecar remembers

/// The part of the desk that is not in the Markdown files. `Library` stores it as JSON in the
/// hidden sidecar; `Desk.init(notes:saved:)` is the only reader and validates everything.
struct SavedDesk: Codable, Equatable {
    /// 2: 20 slots with the stack in one of them, and free points. `Desk.init` reads an older
    /// sidecar as none; `Library` never writes over a newer one.
    var version = 2
    var clarity = false
    /// The stack's place: `stackFree` if set, else `stackSlot`, else `Slot.stackHome`.
    var stackSlot: Int?
    var stackFree: GridPoint?
    var placements: [SavedPlacement] = []
    var stack: [CardID] = []
    /// Successful summaries only: a failure has no `text`, so it cannot be written here. Each is
    /// kept on load only if the current prompt wrote it.
    var summaries: [SavedSummary] = []
    /// Optional, with no version bump: synthesized `Decodable` requires every non-Optional key, even
    /// one with a default, and `Library.load` would read a sidecar written before Spread as none.
    var spread: SavedSpread?
}

/// The Spread set. Its fields are required whenever the `spread` key is present.
struct SavedSpread: Codable, Equatable {
    /// `SpreadCells.indices`: the cells the set was last laid out for. Validated on load.
    var cells: [Int]
    /// Each card of the set and where it goes back to, sorted by id so the file is stable.
    var members: [SavedPlacement]
}

/// A popped card's place: `free` if set, else `slot`.
struct SavedPlacement: Codable, Equatable {
    /// `Slot.index`; validated on load, since the file is outside the type system.
    var slot: Int?
    var free: GridPoint?
    var card: CardID
}

struct SavedSummary: Codable, Equatable {
    var card: CardID
    var source: Digest
    var text: String
    /// `Summary.prompt` when written.
    var prompt: Digest
}

extension Desk {
    /// Derived on every save; never kept in sync by hand.
    var saved: SavedDesk {
        let cards = allCards
        return SavedDesk(
            clarity: clarity,
            stackSlot: stackPlace.savedSlot,
            stackFree: stackPlace.savedFree,
            placements: popped.map { SavedPlacement(slot: $0.place.savedSlot, free: $0.place.savedFree, card: $0.card.id) },
            stack: stack.map(\.id),
            summaries: cards.compactMap { card in
                guard let summary = card.summary, case .text(let text) = summary.outcome else { return nil }
                return SavedSummary(card: card.id, source: summary.source, text: text, prompt: Summary.prompt)
            },
            spread: spreadSet.map { SavedSpread($0) }
        )
    }
}

private extension SavedSpread {
    init(_ set: SpreadSet) {
        self.init(cells: set.cells.indices,
                  members: set.homes.sorted { $0.key < $1.key }
                      .map { SavedPlacement(slot: $0.value.savedSlot, free: $0.value.savedFree, card: $0.key) })
    }
}

private extension Place {
    var savedSlot: Int? { if case .slot(let slot) = self { slot.index } else { nil } }
    var savedFree: GridPoint? { if case .free(let point) = self { point } else { nil } }
}
