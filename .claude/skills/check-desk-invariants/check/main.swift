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
        stack: [cid("c")], collapsed: [cid("a")])
    let full = SavedDesk(placements: placements, stack: [cid("a"), cid("b")])

    // Card a's summary was written by the current prompt, card b's by another one, and both describe
    // the card's current text, so only the prompt tells a load to keep one and drop the other.
    let otherPrompt = Digest(rawValue: "another prompt")
    precondition(otherPrompt != Summary.prompt)
    let summarized = SavedDesk(
        stack: [cid("a"), cid("b"), cid("c")],
        summaries: [SavedSummary(card: cid("a"), source: few["a"]!.digest, text: "kept", prompt: Summary.prompt),
                    SavedSummary(card: cid("b"), source: few["b"]!.digest, text: "dropped", prompt: otherPrompt)])

    let desks: [(String, [CardID: Note], SavedDesk)] = [
        ("empty", [:], SavedDesk()), ("three stacked", fewNotes, stacked), ("mixed", fewNotes, mixed),
        ("near full", pileNotes, full), ("summaries under two prompts", fewNotes, summarized),
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
                           .toggleClarity, .forgetFailedSummaries, .delete(ghost), .returnToStack(ghost)]
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
        list += [.delete(id), .edit(id, note("E", "edited", "twice")), .setCollapsed(id, !card.collapsed),
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
    // from the desk is a file the next save moves to the Trash. Duplicates first: everything
    // below keys cards by id.
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
    case .delete(let id): expected = beforeIDs.subtracting([id])
    case .syncFiles(let files): expected = Set(files.keys)
    case .pop, .returnToStack, .flipStack, .arrange, .showStacked, .move, .edit, .setCollapsed,
         .toggleClarity, .refreshSummary, .forgetFailedSummaries, .storeSummary:
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
        case .new where added.contains(id): .blank
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
        if entered != [id] || after.stack.first?.id != id { try fail("P4 stack order", "↩ Stack did not put \"\(id.rawValue)\" on top") }
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

    // P6 Clarity: the global button sets every card; a per-card change never moves the button.
    switch command {
    case .toggleClarity:
        if after.clarity == before.clarity || after.allCards.contains(where: { $0.collapsed != after.clarity }) {
            try fail("P6 clarity", "Clarity \(after.clarity ? "on" : "off") left a card the other way")
        }
    case .setCollapsed(let id, let collapsed):
        if after.clarity != before.clarity { try fail("P6 clarity", "a per-card change moved the Clarity button") }
        if beforeIDs.contains(id), after.allCards.first(where: { $0.id == id })?.collapsed != collapsed {
            try fail("P6 clarity", "the per-card button did not change \"\(id.rawValue)\"")
        }
    case .addFromTool:
        if after.clarity != before.clarity { try fail("P6 clarity", "the Clarity button changed without being pressed") }
        if after.allCards.contains(where: { added.contains($0.id) && $0.collapsed != after.clarity }) {
            try fail("P6 clarity", "a card from an AI tool did not take Clarity's state (\(after.clarity ? "on" : "off"))")
        }
    default:
        if after.clarity != before.clarity { try fail("P6 clarity", "the Clarity button changed without being pressed") }
    }

    // P7 A summary attaches only to the version of the card it describes.
    if case .storeSummary(let id, let summary) = command, let card = after.allCards.first(where: { $0.id == id }),
       let old = before.allCards.first(where: { $0.id == id }) {
        let should = summary.source == card.digest ? summary : old.summary
        if card.summary != should { try fail("P7 summaries", "a summary for another version of \"\(id.rawValue)\" was attached") }
    }
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
    // read back the way `Library.load` reads them, give the same places, stack, clarity, collapsed
    // state and text summaries (the stack page and failed summaries are deliberately not saved).
    // Every summary is written under the current prompt, so each must survive the reload.
    let files = notes.mapValues { Note(markdown: $0.markdown) }
    let sidecar = try! JSONDecoder().decode(SavedDesk.self, from: try! JSONEncoder().encode(after.saved))
    let reloaded = Desk(notes: files, saved: sidecar)
    if files != notes { try fail("P5 save and reload", "a card's text changes when written to Markdown and read back") }
    func layout(_ d: Desk) -> String {
        func card(_ c: Card) -> String {
            let summary: String = if let s = c.summary, case .text(let t) = s.outcome { "\(s.source.rawValue.prefix(8)):\(t)" } else { "-" }
            return "\(c.id.rawValue)/\(c.collapsed)/\(summary)"
        }
        return ("popped \(d.popped.map { "\(card($0.card))@\($0.place)" }) stack@\(d.stackPlace) "
            + "\(d.stack.map(card)) clarity \(d.clarity)").replacingOccurrences(of: "main.", with: "")
    }
    if layout(reloaded) != layout(after) || reloaded.saved != after.saved {
        try fail("P5 save and reload", "after saving, a relaunch shows\n      \(layout(reloaded))\n    instead of\n      \(layout(after))")
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
}

extension Command {
    var isWriteBlank: Bool { if case .writeBlank = self { true } else { false } }
}

// MARK: - Breadth-first search over every sequence

/// What makes two desks different, for skipping desks already explored. Every note the check
/// writes has its own header, so header and line count stand for the text; a summary counts by
/// whether it is current, since that is all the app shows.
func key(_ desk: Desk) -> String {
    func card(_ c: Card) -> String {
        let summary: String = switch c.summary {
        case nil: "-"
        case let s? where s.source != c.digest: "old"
        case let s?: if case .text = s.outcome { "t" } else { "f" }
        }
        return "\(c.id.rawValue):\(c.note.header):\(c.note.body.count):\(c.collapsed ? 1 : 0):\(summary)"
    }
    func place(_ p: Place) -> String {
        switch p {
        case .slot(let s): "s\(s.index)"
        case .free(let g): "f\(g.x),\(g.y)"
        }
    }
    return desk.popped.map { card($0.card) + "@" + place($0.place) }.joined(separator: " ")
        + " | " + place(desk.stackPlace) + " " + desk.stack.map(card).joined(separator: " ")
        + " | \(desk.selection) \(desk.clarity)"
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
    case .edit(let id, _): ".edit(\"\(id.rawValue)\")"
    case .storeSummary(let id, let s): ".storeSummary(\"\(id.rawValue)\", \(s.outcome), source \(s.source.rawValue.prefix(8)))"
    case .addFromTool(_, _, let landing, let typing): ".addFromTool(\(landing)\(typing ? ", typing in the stacked card" : ""))"
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
print(String(format: "PASS P1–P7, depth %d, %d desks, %d steps checked, %.1fs", depth, explored, transitions, Date().timeIntervalSince(started)))
