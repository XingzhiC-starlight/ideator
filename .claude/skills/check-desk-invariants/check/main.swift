// desk-check: runs the real Cards/Desk.swift (with Grid.swift and Note.swift) through every
// command sequence up to a depth, from a set of starting desks, and checks the desk's promises
// after every step. Breadth-first, with states already seen skipped, so a pass means: no sequence
// of at most DEPTH commands from these commands and starting desks breaks a property.
//
//   desk-check [DEPTH]      default 5. Exit 0 = every property held; 1 = counterexample printed.
//
// Built and run by ../run.sh, never by hand. See ../SKILL.md.
import Foundation

// MARK: - The small world the check explores

let now = Date(timeIntervalSince1970: 1_700_000_000)

func note(_ header: String, _ body: String...) -> Note {
    Note(header: header, body: body.map { Line(runs: [Run(text: $0)]) })
}

func cid(_ name: String) -> CardID { CardID(rawValue: name) }

/// The notes a Spread click may delete: no character shows. This list, not `Note.isBlank`, is the
/// oracle, so a wrong rule in `Note` is caught. It holds only what the search writes; `NoteTests`
/// covers the other shapes.
let blankNotes: [Note] = [
    .blank, note("\u{3000}", "  "), Note(header: "", body: [Line(kind: .todo(done: true), runs: [])]),
]

func setIsBlank(_ desk: Desk) -> Bool {
    guard let set = desk.spreadSet else { return false }
    return desk.allCards.filter { set.contains($0.id) }.allSatisfy { blankNotes.contains($0.note) }
}

/// What a Spread click deletes: the whole set, when the click is plain, a card of the set is on the
/// desktop and no card of the set shows a character. A fresh click never deletes.
func deletedBySpread(_ desk: Desk, fresh: Bool) -> Set<CardID> {
    guard !fresh, let set = desk.spreadSet, desk.popped.contains(where: { set.contains($0.card.id) }),
          setIsBlank(desk) else { return [] }
    return Set(set.homes.keys)
}

/// Starting desks, each through `Desk(notes:saved:)` as a launch builds it. `notes` and `saved` are
/// kept so the check can compare what the load kept with what the sidecar held.
let seeds: [(name: String, notes: [CardID: Note], saved: SavedDesk, desk: Desk)] = {
    let few = ["a": note("A", "one"), "b": note("B", "one", "two"), "c": note("C")]
    let fewNotes = Dictionary(uniqueKeysWithValues: few.map { (cid($0.key), $0.value) })

    // 17 snapped cards and one free card over slot 0, which a snapped card holds too: two slots
    // stay untaken while 18 cards are out, so Pop's 19-card ceiling is reachable in two steps.
    let snapped = Slot.all.filter { $0 != Slot.stackHome && $0.index != 18 && $0.index != 19 }.prefix(17)
    var pileNotes = fewNotes
    var placements: [SavedPlacement] = []
    for slot in snapped {
        pileNotes[cid("p\(slot.index)")] = note("P\(slot.index)")
        placements.append(SavedPlacement(slot: slot.index, card: cid("p\(slot.index)")))
    }
    pileNotes[cid("f")] = note("F")
    placements.append(SavedPlacement(free: Slot.all[0].center, card: cid("f")))

    let stacked = SavedDesk(stack: [cid("b"), cid("a"), cid("c")])
    let mixed = SavedDesk(
        clarity: true, stackFree: GridPoint(x: 0.5, y: 0.6),
        placements: [SavedPlacement(slot: 0, card: cid("a")),
                     SavedPlacement(free: GridPoint(x: 0.31, y: 0.12), card: cid("b"))],
        stack: [cid("c")])
    let full = SavedDesk(placements: placements, stack: [cid("a"), cid("b")])

    // Card a's summary was written by the current prompt, card b's by another one, and both describe
    // the card's current text, so only the prompt tells a load to keep one and drop the other.
    let otherPrompt = Digest(rawValue: "another prompt")
    precondition(otherPrompt != Summary.prompt)
    let summarized = SavedDesk(
        stack: [cid("a"), cid("b"), cid("c")],
        summaries: [SavedSummary(card: cid("a"), source: few["a"]!.digest, text: "kept", prompt: Summary.prompt),
                    SavedSummary(card: cid("b"), source: few["b"]!.digest, text: "dropped", prompt: otherPrompt)])

    // A gathered Spread set with one card out again. Clarity is on, so putting set cards back must
    // leave it on. Card a sits in slot 6, which s3 remembers; s4 was popped by hand to slot 12 while
    // it still remembers slot 7, the stale home a Gather must overwrite. The load must drop a ghost
    // id, a second entry for s1 and an out-of-range slot for c.
    let spreadNotes = fewNotes.merging(["s1", "s2", "s3", "s4"].map { (cid($0), note($0.uppercased())) }) { $1 }
    let spreadSaved = SavedDesk(
        clarity: true,
        placements: [SavedPlacement(slot: 6, card: cid("a")), SavedPlacement(slot: 12, card: cid("s4"))],
        stack: [cid("b"), cid("s1"), cid("s2"), cid("s3"), cid("c")],
        spread: SavedSpread(cells: [0, 1, 2, 5, 6, 7], members: [
            SavedPlacement(slot: 2, card: cid("s1")),
            SavedPlacement(free: GridPoint(x: 0.31, y: 0.12), card: cid("s2")),   // over cell 1
            SavedPlacement(slot: 6, card: cid("s3")),
            SavedPlacement(slot: 7, card: cid("s4")),
            SavedPlacement(slot: 3, card: cid("ghost")),
            SavedPlacement(slot: 9, card: cid("s1")),
            SavedPlacement(slot: 25, card: cid("c")),
        ]))

    // A Spread set with nothing written, one of its cards in the stack between two others, and then the
    // same set with text only on that stacked card. Clarity is on, so a deletion must leave it on. x2
    // is a free card over cell 1.
    func blankSetNotes(stacked x3: Note) -> [CardID: Note] {
        fewNotes.merging([(cid("x1"), blankNotes[0]), (cid("x2"), blankNotes[1]), (cid("x3"), x3)]) { $1 }
    }
    let blankSetSaved = SavedDesk(
        clarity: true,
        placements: [SavedPlacement(slot: 0, card: cid("x1")), SavedPlacement(free: GridPoint(x: 0.31, y: 0.12), card: cid("x2"))],
        stack: [cid("a"), cid("x3"), cid("b")],
        spread: SavedSpread(cells: [0, 1, 2], members: [
            SavedPlacement(slot: 0, card: cid("x1")),
            SavedPlacement(free: GridPoint(x: 0.31, y: 0.12), card: cid("x2")),
            SavedPlacement(slot: 2, card: cid("x3")),
        ]))

    let desks: [(String, [CardID: Note], SavedDesk)] = [
        ("empty", [:], SavedDesk()), ("three stacked", fewNotes, stacked), ("mixed", fewNotes, mixed),
        ("near full", pileNotes, full), ("summaries under two prompts", fewNotes, summarized),
        ("a Spread set, one card out", spreadNotes, spreadSaved),
        ("a blank set, one card stacked", blankSetNotes(stacked: blankNotes[2]), blankSetSaved),
        ("a set with text only in the stack", blankSetNotes(stacked: note("X3", "written")), blankSetSaved),
    ]
    return desks.map { name, notes, saved in (name, notes, saved, Desk(notes: notes, saved: saved)) }
}()

/// Every command the check tries from `desk`. Per-card commands name the first two and the last
/// card on the desktop (the near-full desk has 18), the shown stacked card and the top one, plus an
/// id that does not exist.
func commands(_ desk: Desk) -> [Command] {
    let allPopped = desk.popped.map(\.card.id)
    let popped = Array(allPopped.prefix(2)) + (allPopped.count > 2 ? [allPopped.last!] : [])
    var cards = popped + [desk.selectedCard?.id, desk.stack.first?.id].compactMap { $0 }
    cards = cards.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    let ghost = cid("ghost")

    var list: [Command] = [.new(at: now), .pop, .flipStack(.next), .flipStack(.previous),
                           .writeBlank(note("W", "typed"), at: now), .writeBlank(.blank, at: now),
                           .setClarity(true), .setClarity(false), .forgetFailedSummaries, .delete(ghost), .returnToStack(ghost)]
    for id in popped { list.append(.returnToStack(id)) }

    // The arranger. Move the shown card (the bottom one while the blank page shows) to the top, the
    // middle, the bottom and past both ends; the top card to the bottom, which leaves another card
    // shown; show the top and the bottom card. A card that does not exist, and one on the desktop,
    // must change nothing.
    let stacked = desk.stack.count
    if let mover = desk.selectedCard?.id ?? desk.stack.last?.id {
        for index in Set([0, stacked / 2, stacked - 1, -1, stacked + 5]).sorted() { list.append(.arrange(mover, at: index)) }
    }
    if let top = desk.stack.first?.id { list.append(.arrange(top, at: stacked - 1)) }
    for id in [desk.stack.first?.id, desk.stack.last?.id].compactMap({ $0 }) { list.append(.showStacked(id)) }
    list += [.arrange(ghost, at: 0), .showStacked(ghost)]
    if let out = allPopped.first { list += [.arrange(out, at: 0), .showStacked(out)] }

    // Drops, for the stack and the first desktop card: onto the other one's slot when it is
    // snapped (a swap), the first free slot, a fixed slot, a free point, a free point past the
    // right edge, and the mover's own place.
    let movers = [Movable.stack] + allPopped.prefix(1).map(Movable.card)
    for item in movers {
        var targets: [Place] = [.slot(Slot.all[12]), .free(GridPoint(x: 0.42, y: 0.55)), .free(GridPoint(x: 1.05, y: 0.9))]
        if let own = desk.place(of: item) { targets.append(own) }
        if let free = desk.firstFreeSlot { targets.append(.slot(free)) }
        for other in movers where other != item {
            if let place = desk.place(of: other), case .slot = place { targets.append(place) }
        }
        for target in Set(targets) { list.append(.move(item, to: target)) }
    }

    for id in cards {
        guard let card = desk.allCards.first(where: { $0.id == id }) else { continue }
        list += [.delete(id), .edit(id, note("E", "edited", "twice")),
                 .refreshSummary(id),
                 .storeSummary(id, Summary(source: card.digest, outcome: .text("fresh"))),
                 .storeSummary(id, Summary(source: Digest(rawValue: "stale"), outcome: .text("stale"))),
                 .storeSummary(id, Summary(source: card.digest, outcome: .failed(reason: "down")))]
    }

    // Folder rescans: unchanged, one file gone (the shown card, or the first card), one file added,
    // one file edited outside.
    var files = Dictionary(uniqueKeysWithValues: desk.allCards.map { ($0.id, $0.note) })
    list.append(.syncFiles(files))
    if let gone = desk.selectedCard?.id ?? desk.allCards.first?.id {
        var less = files
        less[gone] = nil
        list.append(.syncFiles(less))
    }
    if let edited = desk.allCards.last?.id {
        var changed = files
        changed[edited] = note("Outside", "edit")
        list.append(.syncFiles(changed))
    }
    files[cid("zz added")] = note("Added", "by hand")
    list.append(.syncFiles(files))

    // A card from an AI tool: Top while the user types in the stacked card, Top, Bottom. Last, so the
    // older mutants keep the counterexample they had, and Top while typing first, so a card that
    // misses the top fails P4 before the page it shows fails P3.
    list += [.addFromTool(note("Tool typing", "x"), at: now, to: .top, typing: true),
             .addFromTool(note("Tool top", "x"), at: now, to: .top, typing: false),
             .addFromTool(note("Tool bottom", "x"), at: now, to: .bottom, typing: false)]

    // Spread with the factory cells, cells that include the stack's home and slot 12, no cells, and
    // three cells at the bottom right (the near-full desk has room for one of them). Then fresh,
    // once with cells and once with none: only a fresh click changes its copy before it learns that
    // nothing will come out, so only it can show a refusal that is not atomic.
    for cells in [SpreadCells.standard, SpreadCells(indices: [0, 4, 12]), .empty, SpreadCells(indices: [11, 18, 19])] {
        list.append(.spread(cells, fresh: false, at: now))
    }
    list += [.spread(.standard, fresh: true, at: now), .spread(.empty, fresh: true, at: now)]

    // Clearing a card of the Spread set by hand to each empty note, and the one edit that is not a
    // clearing, text below an empty header. Only a card of the set can change what a click does.
    // Last, so the older mutants keep the counterexample they had.
    for id in cards where desk.spreadSet?.contains(id) ?? false {
        list += blankNotes.map { Command.edit(id, $0) } + [.edit(id, note("", "text"))]
    }
    return list
}

// MARK: - The properties

struct Violation: Error {
    let property: String
    let detail: String
}

func ids(_ desk: Desk) -> [CardID] { desk.allCards.map(\.id) }

func shown(_ desk: Desk) -> CardID? { desk.selectedCard?.id }

func describe(_ id: CardID?) -> String { id.map { "\"\($0.rawValue)\"" } ?? "the blank page" }

/// The promises about one step: `before`, then `command`, gave `after` and returned `arrived`.
func checkStep(_ before: Desk, _ command: Command, _ after: Desk, arrived: CardID?) throws {
    func fail(_ property: String, _ detail: String) throws -> Never {
        throw Violation(property: property, detail: detail)
    }
    let beforeIDs = Set(ids(before)), afterIDs = Set(ids(after))

    // P1 No card is lost, duplicated or changed by a command that is not about it. A card missing
    // from the desk is a file the next save moves to the Trash. Spread never removes a card, except a
    // plain click on a set with no text, which removes exactly that set. Duplicates
    // first: everything below keys cards by id.
    if ids(after).count != afterIDs.count { try fail("P1 conservation", "a card is in two places: \(ids(after).map(\.rawValue))") }
    let beforeNotes = Dictionary(uniqueKeysWithValues: before.allCards.map { ($0.id, $0.note) })
    let afterNotes = Dictionary(uniqueKeysWithValues: after.allCards.map { ($0.id, $0.note) })
    let added = afterIDs.subtracting(beforeIDs)
    let expected: Set<CardID>
    switch command {
    case .new, .writeBlank:
        if added.count > 1 { try fail("P1 conservation", "one command added \(added.count) cards") }
        expected = beforeIDs.union(added)
    case .addFromTool:
        if added.count != 1 { try fail("P1 conservation", "a card from an AI tool added \(added.count) cards") }
        expected = beforeIDs.union(added)
    case .spread(let cells, let fresh, _):
        let deleted = deletedBySpread(before, fresh: fresh)
        if added.count > cells.count { try fail("P1 conservation", "a Spread made \(added.count) cards for \(cells.count) cells") }
        if !deleted.isEmpty && !added.isEmpty { try fail("P1 conservation", "a Spread that deleted a set also made \(added.count) cards") }
        expected = beforeIDs.subtracting(deleted).union(added)
    case .delete(let id): expected = beforeIDs.subtracting([id])
    case .syncFiles(let files): expected = Set(files.keys)
    case .pop, .returnToStack, .flipStack, .arrange, .showStacked, .move, .edit, .setClarity,
         .refreshSummary, .forgetFailedSummaries, .storeSummary:
        expected = beforeIDs
    }
    if afterIDs != expected {
        try fail("P1 conservation", "cards lost: \(expected.subtracting(afterIDs).map(\.rawValue).sorted()), "
                 + "cards appeared: \(afterIDs.subtracting(expected).map(\.rawValue).sorted())")
    }
    for (id, note) in afterNotes {
        let want: Note? = switch command {
        case .edit(let edited, let new) where edited == id: new
        case .syncFiles(let files): files[id]
        case .new where added.contains(id), .spread where added.contains(id): .blank
        case .writeBlank(let typed, _) where added.contains(id): typed
        case .addFromTool(let given, _, _, _) where added.contains(id): given
        default: beforeNotes[id]
        }
        if note != want { try fail("P1 conservation", "card \"\(id.rawValue)\" has text it was never given") }
    }

    // P3 The stack keeps showing the same page unless the command is meant to change it: a flip
    // moves one page around the loop; Return shows the returned card; the arranger's row shows
    // its card, while its move keeps the same card (or the blank page) showing wherever it lands,
    // which is the default below; typing on the blank page shows the new card; New on a full
    // desktop shows the blank page; and when the shown card leaves (Pop, delete, a file removed),
    // the next surviving card under it shows.
    let pages = before.stack.count + 1
    let underneath = before.stack.dropFirst(before.selection + 1).map(\.id).first { id in after.stack.contains { $0.id == id } }
    let want: CardID?
    switch command {
    case .flipStack(let direction):
        let page = direction == .next ? (before.selection + 1) % pages : (before.selection + pages - 1) % pages
        if after.selection != page || after.stack.map(\.id) != before.stack.map(\.id) {
            try fail("P3 stack page", "flip \(direction) from page \(before.selection) of \(pages) went to page \(after.selection)")
        }
        want = shown(after)
    case .returnToStack(let id) where before.popped.contains(where: { $0.card.id == id }): want = id
    case .showStacked(let id) where before.stack.contains(where: { $0.id == id }): want = id
    case .writeBlank where !added.isEmpty: want = added.first
    case .addFromTool(_, _, .top, false): want = added.first
    case .new where arrived == nil: want = nil
    default:
        if let was = shown(before), !after.stack.contains(where: { $0.id == was }) { want = underneath }
        else { want = shown(before) }
    }
    if shown(after) != want {
        try fail("P3 stack page", "the stack shows \(describe(shown(after))) where it should show \(describe(want))")
    }
    if command.isWriteBlank, !added.isEmpty, after.selection != after.stack.count - 1 {
        try fail("P3 stack page", "no blank page right after the card typed on the blank page")
    }

    // P4 The stack's order changes only by cards entering or leaving, and by the arranger's move:
    // the cards that stay keep their order, Return puts its card on top, new cards join at the
    // bottom, and a move lands its card at the clamped index with the others in their old order.
    if case .addFromTool = command, after.popped != before.popped || after.stackPlace != before.stackPlace {
        try fail("P4 stack order", "a card from an AI tool changed the desktop")
    }
    let kept = before.stack.map(\.id).filter { id in after.stack.contains { $0.id == id } }
    let afterKept = after.stack.map(\.id).filter { id in before.stack.contains { $0.id == id } }
    if case .arrange(let id, let index) = command {
        let was = before.stack.map(\.id), now = after.stack.map(\.id)
        if was.contains(id) {
            let landing = min(max(index, 0), was.count - 1)
            if now.firstIndex(of: id) != landing {
                try fail("P4 stack order", "\"\(id.rawValue)\" moved to \(index) of \(was.count) but is at \(now.firstIndex(of: id).map(String.init) ?? "nowhere")")
            }
            if now.filter({ $0 != id }) != was.filter({ $0 != id }) {
                try fail("P4 stack order", "a move reordered the other cards: \(was.map(\.rawValue)) became \(now.map(\.rawValue))")
            }
        } else if now != was {
            try fail("P4 stack order", "moving a card that is not stacked changed the stack")
        }
        if after.popped != before.popped || after.stackPlace != before.stackPlace {
            try fail("P4 stack order", "the arranger's move changed the desktop")
        }
    } else if kept != afterKept {
        try fail("P4 stack order", "stacked cards reordered: \(kept.map(\.rawValue)) became \(afterKept.map(\.rawValue))")
    }
    let entered = after.stack.map(\.id).filter { id in !before.stack.contains { $0.id == id } }
    switch command {
    case .returnToStack(let id) where !entered.isEmpty:
        if entered != [id] || after.stack.first?.id != id { try fail("P4 stack order", "Return to stack did not put \"\(id.rawValue)\" on top") }
    case .addFromTool(_, _, .top, _):
        if entered.count != 1 || after.stack.first?.id != entered.first {
            try fail("P4 stack order", "a card from an AI tool with Top did not join at the top: \(after.stack.map(\.id.rawValue))")
        }
    default:
        if let first = entered.first, let i = after.stack.firstIndex(where: { $0.id == first }),
           after.stack.count - i != entered.count {
            try fail("P4 stack order", "new cards \(entered.map(\.rawValue)) did not join at the bottom")
        }
    }

    // P6 Clarity: it moves only when the ribbon's button sets it or New, typing on the blank page
    // and a Spread that makes cards turn it off. Whether every face shows collapsed is a promise
    // about one desk (`checkState`).
    switch command {
    case .setClarity(let on):
        if after.clarity != on { try fail("P6 clarity", "setClarity(\(on)) left Clarity \(after.clarity ? "on" : "off")") }
    case .new where arrived != nil, .writeBlank where !added.isEmpty, .spread where !added.isEmpty:
        if after.clarity { try fail("P6 clarity", "a new card opened while Clarity stayed on") }
    default:
        if after.clarity != before.clarity { try fail("P6 clarity", "Clarity changed without being pressed") }
    }

    // P7 A summary attaches only to the version of the card it describes.
    if case .storeSummary(let id, let summary) = command, let card = after.allCards.first(where: { $0.id == id }),
       let old = before.allCards.first(where: { $0.id == id }) {
        let should = summary.source == card.digest ? summary : old.summary
        if card.summary != should { try fail("P7 summaries", "a summary for another version of \"\(id.rawValue)\" was attached") }
    }

    // P8 Spread. The set is the Spread button's batch: a card stays in it until it is deleted, a
    // fresh set replaces the set, or a layout onto fewer cells lets it go.
    let homes = before.spreadSet?.homes ?? [:], homesAfter = after.spreadSet?.homes ?? [:]
    func setIs(_ want: [CardID: Place], cells: SpreadCells?, after what: String) throws {
        if homesAfter != want || (!want.isEmpty && after.spreadSet?.cells != cells) {
            try fail("P8 spread", "after \(what) the set is \(describe(after.spreadSet)) where it should be "
                     + describe(cells.map { ($0, want) }))
        }
    }
    switch command {
    case .spread(let cells, let fresh, _):
        let out = before.popped.filter { homes[$0.card.id] != nil }.map { (id: $0.card.id, place: $0.place) }
        if !deletedBySpread(before, fresh: fresh).isEmpty {
            // No card of the set shows a character: every card of it is deleted, wherever it is, and with
            // them the set. Nothing else moves, no card is made and none gets the cursor.
            if after.spreadSet != nil { try fail("P8 spread", "deleting an empty set left the set \(describe(after.spreadSet))") }
            if after.stack.map(\.id) != before.stack.map(\.id).filter({ homes[$0] == nil }) {
                try fail("P8 spread", "deleting an empty set left the stack \(after.stack.map(\.id.rawValue))")
            }
            if after.popped != before.popped.filter({ homes[$0.card.id] == nil }) || after.stackPlace != before.stackPlace {
                try fail("P8 spread", "deleting an empty set moved the stack or a card that is not the set's")
            }
            if arrived != nil { try fail("P8 spread", "deleting an empty set returned a card to focus") }
        } else if !fresh && !out.isEmpty {
            // Gather: exactly the set's desktop cards, to the bottom in reading order of their places,
            // each remembering that place. Nothing else moves and no card is made.
            let order = out.sorted(by: readsBefore).map(\.id)
            if after.stack.map(\.id) != before.stack.map(\.id) + order {
                try fail("P8 spread", "Gather left the stack \(after.stack.map(\.id.rawValue)) where it should be "
                         + "\((before.stack.map(\.id) + order).map(\.rawValue))")
            }
            if after.popped != before.popped.filter({ homes[$0.card.id] == nil }) || after.stackPlace != before.stackPlace {
                try fail("P8 spread", "Gather moved the stack or a card that is not the set's")
            }
            try setIs(homes.merging(out.map { ($0.id, $0.place) }) { $1 }, cells: before.spreadSet?.cells, after: "Gather")
        } else {
            try checkLayout(before, after, arrived: arrived, cells: cells, plan: spreadPlan(before, cells, fresh: fresh))
        }
    case .returnToStack(let id) where homes[id] != nil && before.place(of: .card(id)) != nil:
        try setIs(homes.merging([(id, before.place(of: .card(id))!)]) { $1 }, cells: before.spreadSet?.cells,
                  after: "Return to stack on \"\(id.rawValue)\"")
    case .delete(let id):
        try setIs(homes.filter { $0.key != id }, cells: before.spreadSet?.cells, after: "deleting \"\(id.rawValue)\"")
    case .syncFiles(let files):
        try setIs(homes.filter { files[$0.key] != nil }, cells: before.spreadSet?.cells, after: "a rescan")
    default:
        if after.spreadSet != before.spreadSet {
            try fail("P8 spread", "the set changed without Spread, Return to stack or a delete: \(describe(before.spreadSet)) "
                     + "became \(describe(after.spreadSet))")
        }
    }
}

// MARK: - Spread, in the spec's words

/// Spread's reading order: the cell a place covers most, then its point top to bottom and left to
/// right (`Place.readingKey`), then the id.
func readsBefore(_ a: (id: CardID, place: Place), _ b: (id: CardID, place: Place)) -> Bool {
    a.place.readingKey != b.place.readingKey ? a.place.readingKey < b.place.readingKey : a.id < b.id
}

/// What a Spread click that does not gather should do, from `before` alone: which set cards go
/// where, which leave the set, which ticked cells get new blank cards, and (fresh) which desktop
/// cards are swept to the stack first.
struct SpreadPlan {
    /// Set cards that stay in the set, and where each goes. Old cards past the last cell are not
    /// here: they leave the set and stay stacked as ordinary cards.
    var kept: [(id: CardID, target: Place)] = []
    var extras: [Slot] = []
    var swept: [CardID] = []
}

func spreadPlan(_ before: Desk, _ cells: SpreadCells, fresh: Bool) -> SpreadPlan {
    var plan = SpreadPlan()
    let set = before.spreadSet
    if fresh {
        // The old set is dropped first: its desktop cards go to the stack, and every cell is new.
        plan.swept = before.popped.filter { set?.contains($0.card.id) ?? false }
            .map { (id: $0.card.id, place: $0.place) }.sorted(by: readsBefore).map(\.id)
        plan.extras = cells.inReadingOrder
        return plan
    }
    let old = (set?.homes ?? [:]).map { (id: $0.key, place: $0.value) }.sorted(by: readsBefore)
    if let set, set.cells == cells {
        plan.kept = old.map { (id: $0.id, target: $0.place) }
    } else {
        // The card in the first old home gets the first cell, and so on.
        let order = cells.inReadingOrder
        plan.kept = zip(old, order).map { (id: $0.id, target: .slot($1)) }
        plan.extras = Array(order.dropFirst(old.count))
    }
    return plan
}

/// A layout, in Pop's terms. It starts from `before` less the fresh sweep. Walking the plan (kept
/// cards in reading order, then the extra cells), each item comes out exactly when its cell is not
/// taken by the starting desk or by an item that came out before it; one that stays had its cell
/// taken, or the desktop was at the ceiling. The ceiling itself is P2's: this never says too many
/// came out. A click that puts nothing out changes nothing, the fresh sweep included.
func checkLayout(_ before: Desk, _ after: Desk, arrived: CardID?, cells: SpreadCells, plan: SpreadPlan) throws {
    func fail(_ detail: String) throws -> Never { throw Violation(property: "P8 spread", detail: detail) }
    let swept = Set(plan.swept)
    let start = before.popped.filter { !swept.contains($0.card.id) }
    var taken = Set(start.map(\.place.slot) + [before.stackPlace.slot])
    let items = plan.kept.map { (id: Optional($0.id), place: $0.target) } + plan.extras.map { (id: CardID?.none, place: Place.slot($0)) }
    func name(_ item: (id: CardID?, place: Place)) -> String {
        item.id.map { "\"\($0.rawValue)\"" } ?? "a new card for cell \(item.place.slot.index)"
    }
    if after == before {
        if let free = items.first(where: { !taken.contains($0.place.slot) }), start.count < Slot.count - 1 {
            try fail("a Spread changed nothing though \(name(free)) had cell \(free.place.slot.index) free")
        }
        return
    }

    let startStack = before.stack.map(\.id) + plan.swept
    let beforeIDs = Set(before.allCards.map(\.id))
    if Array(after.popped.prefix(start.count)) != start || after.stackPlace != before.stackPlace {
        try fail("a Spread moved the stack or a card that was on the desktop")
    }
    let came = Array(after.popped.dropFirst(start.count))
    if came.isEmpty { try fail("a Spread that put no card out changed the desk") }
    var next = 0
    var made: [(id: CardID, cell: Slot)] = []
    for item in items {
        let what = name(item)
        let arrival = next < came.count ? came[next] : nil
        // A set card is known by its id, a new card by the cell it came out on.
        let isIt = arrival.map { a in item.id.map { a.card.id == $0 } ?? (!beforeIDs.contains(a.card.id) && a.place == item.place) } ?? false
        if isIt, let arrival {
            if taken.contains(item.place.slot) { try fail("\(what) came out on cell \(item.place.slot.index), which was taken") }
            if arrival.place != item.place { try fail("\(what) came out at \(arrival.place) where it should be at \(item.place)") }
            if item.id == nil { made.append((arrival.card.id, item.place.slot)) }
            taken.insert(item.place.slot)
            next += 1
        } else if let id = item.id, came.contains(where: { $0.card.id == id }) {
            try fail("\(what) came out out of reading order")
        } else if !taken.contains(item.place.slot) && start.count + next < Slot.count - 1 {
            try fail("\(what) stayed in the stack though cell \(item.place.slot.index) was free")
        }
    }
    if next < came.count { try fail("\"\(came[next].card.id.rawValue)\" came out, which the layout does not put out") }
    let cameOut = Set(came.map(\.card.id))
    if after.stack.map(\.id) != startStack.filter({ !cameOut.contains($0) }) {
        try fail("the stack is \(after.stack.map(\.id.rawValue)) where it should be \(startStack.filter { !cameOut.contains($0) }.map(\.rawValue))")
    }
    let want = Dictionary(uniqueKeysWithValues: plan.kept.map { ($0.id, $0.target) } + made.map { ($0.id, Place.slot($0.cell)) })
    if after.spreadSet?.homes != want || after.spreadSet?.cells != cells {
        try fail("the set is \(describe(after.spreadSet)) where it should be \(describe((cells, want)))")
    }
    if arrived != made.first?.id {
        try fail("the Spread returned \(arrived.map { "\"\($0.rawValue)\"" } ?? "no card") to focus, not its first new card")
    }
}

func describe(_ set: SpreadSet?) -> String { set.map { describe(($0.cells, $0.homes)) } ?? "none" }

func describe(_ set: (cells: SpreadCells, homes: [CardID: Place])?) -> String {
    guard let set, !set.homes.isEmpty else { return "none" }
    return ("\(set.cells.indices) " + set.homes.sorted { $0.key < $1.key }.map { "\($0.key.rawValue)@\($0.value)" }.joined(separator: " "))
        .replacingOccurrences(of: "main.", with: "")
}

/// The promises about a single desk. Checked once per desk the search reaches, the starting desks
/// included.
func checkState(_ after: Desk) throws {
    func fail(_ property: String, _ detail: String) throws -> Never {
        throw Violation(property: property, detail: detail)
    }
    let notes = Dictionary(uniqueKeysWithValues: after.allCards.map { ($0.id, $0.note) })

    // P2 Places stay valid: no two snapped items (cards or the stack) in one slot, at most 19 cards
    // on the desktop, and the stack's position is a page that exists.
    var slots: [Slot: String] = [:]
    for (name, place) in [("the stack", after.stackPlace)] + after.popped.map({ ("\"\($0.card.id.rawValue)\"", $0.place) }) {
        guard case .slot(let slot) = place else { continue }
        if let other = slots[slot] { try fail("P2 places", "\(other) and \(name) are both snapped to slot \(slot.index)") }
        slots[slot] = name
    }
    if after.popped.count > Slot.count - 1 { try fail("P2 places", "\(after.popped.count) cards on the desktop; the ceiling is 19") }
    if !(0...after.stack.count).contains(after.selection) {
        try fail("P2 places", "stack position \(after.selection) with \(after.stack.count) stacked cards")
    }

    // P5 Saving and relaunching restores the desk: the notes as Markdown and the sidecar as JSON,
    // read back the way `Library.load` reads them, give the same places, stack, clarity and text
    // summaries (the stack page and failed summaries are deliberately not saved).
    // Every summary is written under the current prompt, so each must survive the reload.
    let files = notes.mapValues { Note(markdown: $0.markdown) }
    let sidecar = try! JSONDecoder().decode(SavedDesk.self, from: try! JSONEncoder().encode(after.saved))
    let reloaded = Desk(notes: files, saved: sidecar)
    if files != notes { try fail("P5 save and reload", "a card's text changes when written to Markdown and read back") }
    func layout(_ d: Desk) -> String {
        func card(_ c: Card) -> String {
            let summary: String = if let s = c.summary, case .text(let t) = s.outcome { "\(s.source.rawValue.prefix(8)):\(t)" } else { "-" }
            return "\(c.id.rawValue)/\(summary)"
        }
        return ("popped \(d.popped.map { "\(card($0.card))@\($0.place)" }) stack@\(d.stackPlace) "
            + "\(d.stack.map(card)) clarity \(d.clarity) spread \(describe(d.spreadSet))").replacingOccurrences(of: "main.", with: "")
    }
    if layout(reloaded) != layout(after) || reloaded.saved != after.saved {
        try fail("P5 save and reload", "after saving, a relaunch shows\n      \(layout(reloaded))\n    instead of\n      \(layout(after))")
    }

    // P6 Clarity, the other half: every card's face, the desktop's and the stack's, shows collapsed
    // exactly when Clarity is on, and the ribbon's button shows the same. A card has no collapse
    // state of its own, so a card from an AI tool or a rescan follows Clarity by being a card.
    let faces = after.cardFaces(hasKey: false).map(\.face) + [after.stackFace(hasKey: false).selected].compactMap { $0 }
    if let face = faces.first(where: { $0.collapsed != after.clarity }) {
        try fail("P6 clarity", "\"\(face.id.rawValue)\" shows \(face.collapsed ? "collapsed" : "expanded") while Clarity is \(after.clarity ? "on" : "off")")
    }
    if after.stackFace(hasKey: false).clarity != after.clarity {
        try fail("P6 clarity", "the ribbon's Clarity button disagrees with Clarity (\(after.clarity ? "on" : "off"))")
    }

    // P8 Spread, the other half: every card of the set is a card on the desk, and the ribbon's Spread
    // button says Gather exactly when a card of the set is on the desktop, and then that the click
    // deletes exactly when no card of the set shows a character.
    if let ghost = after.spreadSet?.homes.keys.first(where: { notes[$0] == nil }) {
        try fail("P8 spread", "\"\(ghost.rawValue)\" is in the set but not on the desk")
    }
    let out = after.popped.contains { after.spreadSet?.contains($0.card.id) ?? false }
    let deletes = setIsBlank(after)
    if after.stackFace(hasKey: false).spreadButton != (out ? .gather(deletes: deletes) : .spread) {
        try fail("P8 spread", "the Spread button says \(after.stackFace(hasKey: false).spreadButton) while "
                 + "\(out ? "a card" : "no card") of the set is on the desktop and \(deletes ? "none" : "a card") of it has text")
    }
}

/// P5, the other direction: a load keeps exactly the text summaries the current prompt wrote. The
/// desks the search reaches only ever hold summaries stamped with the current prompt, so a sidecar
/// that holds another prompt's summary has to be a starting desk.
func checkLoad(notes: [CardID: Note], saved: SavedDesk, desk: Desk) throws {
    let kept = Dictionary(
        saved.summaries.filter { $0.prompt == Summary.prompt && notes[$0.card] != nil }
            .map { ($0.card, Summary(source: $0.source, outcome: .text($0.text))) },
        uniquingKeysWith: { $1 })
    for card in desk.allCards where card.summary != kept[card.id] {
        let held = saved.summaries.first { $0.card == card.id }
            .map { "a summary stamped with \($0.prompt == Summary.prompt ? "the current prompt" : "another prompt")" } ?? "no summary"
        let got = card.summary == nil ? "no summary" : "a summary"
        throw Violation(property: "P5 save and reload",
                        detail: "the sidecar held \(held) for \"\(card.id.rawValue)\", and a load gave it \(got)")
    }

    // The set: the entries that name a card and a valid place, the first such entry per card, with
    // the sidecar's cells less junk; none when no entry is left. A home is never dropped for being
    // occupied.
    var homes: [CardID: Place] = [:]
    for m in saved.spread?.members ?? [] where homes[m.card] == nil && notes[m.card] != nil {
        if let free = m.free { homes[m.card] = .free(free) } else if let slot = m.slot.flatMap(Slot.init(index:)) { homes[m.card] = .slot(slot) }
    }
    let cells = SpreadCells(indices: saved.spread?.cells ?? [])
    if (desk.spreadSet?.homes ?? [:]) != homes || (!homes.isEmpty && desk.spreadSet?.cells != cells) {
        throw Violation(property: "P5 save and reload",
                        detail: "the sidecar's set loaded as \(describe(desk.spreadSet)) where it should be \(describe((cells, homes)))")
    }
}

extension Command {
    var isWriteBlank: Bool { if case .writeBlank = self { true } else { false } }
}

// MARK: - Breadth-first search over every sequence

/// What makes two desks different, for skipping desks already explored. A note counts by its digest,
/// since two empty notes can differ only in what shows nothing; a summary counts by whether it is current, since that is all the app shows.
func key(_ desk: Desk) -> String {
    func card(_ c: Card) -> String {
        let summary: String = switch c.summary {
        case nil: "-"
        case let s? where s.source != c.digest: "old"
        case let s?: if case .text = s.outcome { "t" } else { "f" }
        }
        return "\(c.id.rawValue):\(c.digest.rawValue.prefix(8)):\(summary)"
    }
    func place(_ p: Place) -> String {
        switch p {
        case .slot(let s): "s\(s.index)"
        case .free(let g): "f\(g.x),\(g.y)"
        }
    }
    let spread = desk.spreadSet.map { set in
        "\(set.cells.indices) " + set.homes.sorted { $0.key < $1.key }.map { "\($0.key.rawValue)@\(place($0.value))" }.joined(separator: " ")
    }
    return desk.popped.map { card($0.card) + "@" + place($0.place) }.joined(separator: " ")
        + " | " + place(desk.stackPlace) + " " + desk.stack.map(card).joined(separator: " ")
        + " | \(desk.selection) \(desk.clarity) | " + (spread ?? "-")
}

let depth = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 5 : 5
var explored = 0
var transitions = 0
let started = Date()

func label(_ command: Command) -> String {
    switch command {
    case .new: ".new"
    case .writeBlank(let note, _): ".writeBlank(\(note == .blank ? "blank" : "\"\(note.header)\""))"
    case .syncFiles(let files): ".syncFiles(\(files.keys.map(\.rawValue).sorted()))"
    case .edit(let id, let note): ".edit(\"\(id.rawValue)\", \(note.markdown.debugDescription))"
    case .storeSummary(let id, let s): ".storeSummary(\"\(id.rawValue)\", \(s.outcome), source \(s.source.rawValue.prefix(8)))"
    case .addFromTool(_, _, let landing, let typing): ".addFromTool(\(landing)\(typing ? ", typing in the stacked card" : ""))"
    case .spread(let cells, let fresh, _): ".spread(\(cells.indices)\(fresh ? ", fresh" : ""))"
    default: "\(command)".replacingOccurrences(of: "main.", with: "")
    }
}

func report(_ v: Violation, seed: String, path: [Command]) -> Never {
    print("FAIL \(v.property)")
    print("  starting desk: \(seed)")
    if path.isEmpty { print("  (the starting desk itself)") }
    for (i, step) in path.enumerated() { print("  \(i + 1). \(label(step))") }
    print("  \(v.detail)")
    exit(1)
}

/// One level of the search, spread over the cores: every command from every frontier desk, each
/// step checked, and each desk not seen before checked and returned.
func expand(_ frontier: [(desk: Desk, path: [Command])], seen: Set<String>, seed: String)
    -> (next: [(key: String, desk: Desk, path: [Command])], steps: Int) {
    let workers = max(1, ProcessInfo.processInfo.activeProcessorCount)
    let chunk = (frontier.count + workers - 1) / workers
    var results = [[(key: String, desk: Desk, path: [Command])]](repeating: [], count: workers)
    var steps = [Int](repeating: 0, count: workers)
    var failures = [(Violation, [Command])?](repeating: nil, count: workers)
    results.withUnsafeMutableBufferPointer { results in
        steps.withUnsafeMutableBufferPointer { steps in
            failures.withUnsafeMutableBufferPointer { failures in
                DispatchQueue.concurrentPerform(iterations: workers) { w in
                    var local: Set<String> = []
                    for (desk, path) in frontier.dropFirst(w * chunk).prefix(chunk) {
                        for command in commands(desk) {
                            var after = desk
                            let arrived = after.apply(command)
                            steps[w] += 1
                            do {
                                try checkStep(desk, command, after, arrived: arrived)
                                let k = key(after)
                                guard !seen.contains(k), local.insert(k).inserted else { continue }
                                try checkState(after)
                                results[w].append((k, after, path + [command]))
                            } catch let v as Violation {
                                failures[w] = (v, path + [command])
                                return
                            } catch {}
                        }
                    }
                }
            }
        }
    }
    if let (v, path) = failures.compactMap({ $0 }).min(by: { $0.1.count < $1.1.count }) {
        report(v, seed: seed, path: path)
    }
    return (results.flatMap { $0 }, steps.reduce(0, +))
}

for (name, notes, saved, seed) in seeds {
    do { try checkLoad(notes: notes, saved: saved, desk: seed); try checkState(seed) } catch let v as Violation { report(v, seed: name, path: []) } catch {}
    var seen: Set<String> = [key(seed)]
    var frontier: [(desk: Desk, path: [Command])] = [(seed, [])]
    for _ in 0..<depth {
        let t = Date()
        let (candidates, steps) = expand(frontier, seen: seen, seed: name)
        if ProcessInfo.processInfo.environment["DESK_CHECK_TIMING"] != nil { print("   \(name) level: \(steps) steps \(Date().timeIntervalSince(t))s") }
        transitions += steps
        frontier = []
        for c in candidates where seen.insert(c.key).inserted { frontier.append((c.desk, c.path)) }
        explored += frontier.count
    }
    let loaded = saved.summaries.isEmpty ? "" : " (sidecar held \(saved.summaries.count) summaries, "
        + "\(saved.summaries.filter { $0.prompt != Summary.prompt }.count) under another prompt; the load kept "
        + "\(seed.allCards.filter { $0.summary != nil }.count))"
    print("ok  \(name): \(seen.count) desks\(loaded)")
}
print(String(format: "PASS P1–P8, depth %d, %d desks, %d steps checked, %.1fs", depth, explored, transitions, Date().timeIntervalSince(started)))
