import Foundation

// The nine pages as data. Pure: no AppKit.

// MARK: Copy with inline chips

/// Text with inline control chips and key caps:
/// `"Click \(glyph: .plus) on the stack"`, `"\(key: shortcut) does the same from any app."`.
/// The shell draws each chip as the control's SF Symbol.
struct TourLine: Equatable, ExpressibleByStringInterpolation {
    enum Run: Equatable {
        case text(String)
        case chip(Glyph)
        case key(String)
    }

    /// Normalized: no empty text and no two neighbouring text runs, so equal copy compares equal
    /// however it was put together.
    let runs: [Run]

    init(stringLiteral value: String) { self.init(runs: [.text(value)]) }

    init(stringInterpolation: StringInterpolation) { self.init(runs: stringInterpolation.runs) }

    struct StringInterpolation: StringInterpolationProtocol {
        var runs: [Run] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { runs.append(.text(literal)) }
        mutating func appendInterpolation(glyph: Glyph) { runs.append(.chip(glyph)) }
        mutating func appendInterpolation(key: String) { runs.append(.key(key)) }
        mutating func appendInterpolation(_ number: Int) { runs.append(.text(String(number))) }
    }

    static func + (a: TourLine, b: TourLine) -> TourLine { TourLine(runs: a.runs + b.runs) }

    private init(runs: [Run]) {
        var merged: [Run] = []
        for run in runs {
            if case .text(let text) = run {
                if text.isEmpty { continue }
                if case .text(let previous)? = merged.last {
                    merged[merged.count - 1] = .text(previous + text)
                    continue
                }
            }
            merged.append(run)
        }
        self.runs = merged
    }

    /// The flattened string for VoiceOver and for width tests: a chip reads as its control's name, a
    /// key cap as its text. An attachment alone would read as U+FFFC. A chip drawn right before its
    /// own name ("[grid] Spread", "[filter] Clarity") is read once, not "Spread Spread".
    var spoken: String {
        var text = ""
        var dropSpaces = false
        for (i, run) in runs.enumerated() {
            switch run {
            case .text(let part):
                text += dropSpaces ? String(part.drop(while: { $0 == " " })) : part
            case .key(let key):
                text += key
            case .chip(let glyph):
                let next: String? = if i + 1 < runs.count, case .text(let following) = runs[i + 1] { following } else { nil }
                if next?.drop(while: { $0 == " " }).hasPrefix(glyph.spoken) == true {
                    dropSpaces = true
                    continue
                }
                text += glyph.spoken
            }
            dropSpaces = false
        }
        return text
    }
}

// MARK: Where a page points

/// The ribbon's buttons, left to right, then ⋯.
enum RibbonControl: CaseIterable { case new, hideShow, spread, clarity, more }

/// Where the hint panel sits. `.control(c)` and `.stack` put it left of the stack at that control's
/// height (the ribbon's for `.stack`); `.stackTop` is page 9's top-aligned variant; `.readerCard` puts
/// it right of the reader's card and falls back to `.stack` when there is none; `.belowStack` puts it
/// under the stack, notch on top.
enum Anchor: Equatable { case stack, stackTop, control(RibbonControl), readerCard, belowStack }

/// What gets the accent ring. Pad and radius belong to the target: button 5/9, stack 5/15, hover
/// corner 5/9, menu bar icon 3/7.
enum RingTarget: Equatable { case stack, control(RibbonControl), hoverCorner, menuBarIcon }

struct Aim: Equatable {
    var anchor: Anchor
    var ring: RingTarget? = nil
    /// Page 6: the ticked cells that are free right now are drawn lit.
    var litCells = false
    /// Page 4: the reader's card shows its hover buttons while this phase asks for them.
    var showsHoverButtons = false
}

// MARK: Position vocabulary

/// Everything a page may wait for or react to. The first eight are derived from two successive
/// `TourFacts`; the last three arrive from the system through `TourInput.happened`.
enum TourEvent: Equatable {
    case new, hidden, shown, returned, deleted
    /// A set came onto the desktop: new blank cards, or a gathered set coming back out of the stack.
    case spreadOut
    /// The set left the desktop and is still a set: its cards went into the stack.
    case gathered
    /// The set left the desktop by being deleted (an all-blank Gather).
    case vanished
    case space, appFront, cardsFront
}

/// Why the current phase reads the way it does.
enum Reading: Equatable {
    /// Arrived by Next, Skip, Back or a start: the neutral text.
    case fresh
    /// The previous phase's wait ended with this event.
    case after(TourEvent)
    /// A page that has a Next answers an event in place (page 5).
    case reacted(TourEvent)
}

/// What a phase's copy may read: the live world and why the phase reads as it does.
struct TourContext {
    var world: TourWorld
    var reading: Reading
}

/// Page 5's reaction: title and body swap in place.
struct Reaction {
    var title: TourLine
    var body: TourLine
}

/// When a phase may be walked onto by Next, Back or a start. Evaluated on arrival, and kept
/// evaluated while the reader sits on a phase marked `followsWorld`; never when a wait ends, so a
/// finished wait always proceeds.
enum Gate: Equatable {
    case open
    /// Page 4's ask: skipped when none of the reader's cards is on the desktop.
    case readerCardOut
    /// Page 6: a Spread click would put cards out, or a set is out to gather.
    case spreadCanAct
    /// Page 6's single page: no ticked cell is free and no set is out.
    case spreadBlocked

    func admits(_ world: TourWorld) -> Bool {
        switch self {
        case .open: true
        case .readerCardOut: world.readerCard != nil
        case .spreadCanAct: world.spreadCanAct
        case .spreadBlocked: !world.spreadCanAct
        }
    }
}

/// One entry of the table. A page is the run of consecutive phases with the same `page`; a phase
/// that `waitsFor` something has no Next, and the control it names is the real one.
struct PhaseScript {
    let page: Int
    var gate: Gate = .open
    /// While the reader sits here with nothing happened, the opening is chosen again from the live
    /// world (page 6's "Click Spread" or "Spread needs free cells").
    var followsWorld = false
    var isOptional = false
    var aim: Aim
    /// Non-empty means waiting: the footer has no Next.
    var waitsFor: Set<TourEvent> = []
    var reactions: [TourEvent: Reaction] = [:]
    var title: (TourContext) -> TourLine
    var body: (TourContext) -> TourLine
}

extension PhaseScript {
    enum Footer: Equatable { case backAndNext, backOnly, backAndStartUsing }

    /// Waiting phases have no Next; the last page's button opens the notes folder.
    var footer: Footer {
        if !waitsFor.isEmpty { return .backOnly }
        return page == TourPhase.pageCount ? .backAndStartUsing : .backAndNext
    }
}

/// Every phase of every page, in the prototype's order. The declaration order is the walking order,
/// and `TourScript.make` switches over it exhaustively, so a phase without an entry does not compile.
enum TourPhase: CaseIterable {
    case stack
    case clickNew, typeIn
    case clickHide, clickShow, allBack
    case clickReturn, afterReturn
    case follow
    case spreadOff, clickSpread, clickGather, afterGather
    case clarity
    case aiTool
    case done

    var script: PhaseScript { TourScript.table[self]! }
    var page: Int { script.page }
    /// The count of distinct pages, so "n of 9" is never typed.
    static var pageCount: Int { Set(allCases.map(\.page)).count }
}

// MARK: The table and the walks

enum TourScript {
    static let table: [TourPhase: PhaseScript] = Dictionary(uniqueKeysWithValues: TourPhase.allCases.map { ($0, make($0)) })

    private static func phases(of page: Int) -> [TourPhase] { TourPhase.allCases.filter { $0.page == page } }

    /// The first admitted phase of `page`. A page always admits one: a test pins it in every world.
    static func entry(of page: Int, in world: TourWorld) -> TourPhase {
        let phases = phases(of: page)
        return phases.first { $0.script.gate.admits(world) } ?? phases[0]
    }

    /// Back's landing: the last admitted phase of `page`, its finished, non-waiting phase.
    static func landing(of page: Int, in world: TourWorld) -> TourPhase {
        let phases = phases(of: page)
        return phases.last { $0.script.gate.admits(world) } ?? phases[0]
    }

    /// Next: the first admitted phase of a later page; nil after the last. Next leaves the page: the
    /// phases after a finished one on its own page are waits it never walks, or page 6's other
    /// opening, which `followsWorld` chooses between and Next must not step into.
    static func following(_ phase: TourPhase, in world: TourWorld) -> TourPhase? {
        TourPhase.allCases.first { $0.page > phase.page && $0.script.gate.admits(world) }
    }

    /// A wait ended: the next declared phase, unconditionally, so a finished wait always proceeds
    /// whatever the world has become. The last phase has no wait; it answers itself.
    static func after(_ phase: TourPhase) -> TourPhase {
        let all = TourPhase.allCases
        guard let index = all.firstIndex(of: phase), index + 1 < all.count else { return phase }
        return all[index + 1]
    }

    // The prototype's STEPS copy, exact. Straight apostrophes; curly quotes only where the prototype
    // has them (pages 7 and 8).
    private static func make(_ phase: TourPhase) -> PhaseScript {
        switch phase {
        case .stack:
            PhaseScript(page: 1, aim: Aim(anchor: .stack, ring: .stack),
                title: { _ in "The stack holds your cards" },
                body: { _ in "The tan strip is its ribbon, with the buttons. Below it, one stacked card shows at a time." })

        case .clickNew:
            PhaseScript(page: 2, aim: Aim(anchor: .control(.new), ring: .control(.new)), waitsFor: [.new],
                title: { _ in "Click \(glyph: .plus) on the stack" },
                body: { _ in "One new card appears at the top left, ready to type. Paste a line from this chat, or type; the first line is its title." })
        case .typeIn:
            PhaseScript(page: 2, aim: Aim(anchor: .readerCard),
                title: { c in c.world.readerCard != nil ? "Type or paste into your card" : "Each \(glyph: .plus) makes one card" },
                body: { c in c.world.readerCard != nil
                    ? "The first line is the title. The card saves itself as a file while you write."
                    : "It appears at the top left, ready to type. The first line is its title." })

        case .clickHide:
            PhaseScript(page: 3, aim: Aim(anchor: .control(.hideShow), ring: .control(.hideShow)), waitsFor: [.hidden],
                title: { _ in "Click \(glyph: .hide) to hide every card" },
                body: { c in
                    let shortcut = c.world.shortcut
                    let tail: TourLine = shortcut.works
                        ? "\(key: shortcut.display) does the same from any app."
                        : "Ideator couldn't claim \(key: shortcut.display), so there is no shortcut yet; choose one in Settings."
                    return "Your card and the stack's page go away; only the ribbon stays. " + tail })
        case .clickShow:
            PhaseScript(page: 3, aim: Aim(anchor: .control(.hideShow), ring: .control(.hideShow)), waitsFor: [.shown],
                title: { _ in "Click \(glyph: .show) to bring them back" },
                body: { c in
                    let shortcut = c.world.shortcut
                    let tail: TourLine = shortcut.works ? " \(key: shortcut.display) works here too." : ""
                    return "Nothing was deleted; the cards are only hidden." + tail })
        case .allBack:
            PhaseScript(page: 3, aim: Aim(anchor: .control(.hideShow)),
                title: { _ in "Hidden, not deleted: all back" },
                body: { _ in "Use it whenever the cards are in your way." })

        case .clickReturn:
            PhaseScript(page: 4, gate: .readerCardOut,
                aim: Aim(anchor: .readerCard, ring: .hoverCorner, showsHoverButtons: true), waitsFor: [.returned, .deleted],
                title: { _ in "Hover your card, click \(glyph: .returnToStack)" },
                body: { _ in "Its buttons appear on hover: \(glyph: .returnToStack) returns the card to the stack, \(glyph: .trash) deletes it. Return it now." })
        case .afterReturn:
            PhaseScript(page: 4, aim: Aim(anchor: .stack, ring: .stack),
                title: { c in
                    switch c.reading {
                    case .after(.deleted): "Your card is deleted"
                    case .after(.returned): "Your card is in the stack"
                    default: "The stack holds your cards"
                    } },
                body: { c in
                    let lead: TourLine = c.reading == .after(.deleted) ? "Cards you return instead stay in the stack. " : ""
                    return lead + "Flip through stacked cards at the stack's edges. Past the last one is a blank page: type on it to add a card." })

        case .follow:
            PhaseScript(page: 5, aim: Aim(anchor: .belowStack),
                reactions: [
                    .space: Reaction(title: "Still here on this Space",
                                     body: "The stack came along. Swipe back whenever you like."),
                    .appFront: Reaction(title: "Click any card to come forward",
                                        body: "Another app is in front now, so the cards are behind it. Click any card or the stack and they all come forward."),
                    .cardsFront: Reaction(title: "Back in front",
                                          body: "Clicking any card brings all of them forward."),
                ],
                title: { _ in "Your cards follow you" },
                body: { _ in "Swipe to another Space or open a full-screen app: the stack comes along. Click another app: cards go behind it. Click a card: they all come forward." })

        case .spreadOff:
            PhaseScript(page: 6, gate: .spreadBlocked, followsWorld: true,
                aim: Aim(anchor: .control(.spread), ring: .control(.spread), litCells: true),
                title: { c in c.world.spreadCells.isEmpty ? "Spread is off" : "Spread needs free cells" },
                body: { c in c.world.spreadCells.isEmpty
                    ? "\(glyph: .spread) Spread puts blank cards in cells you tick in Settings › Spread. None are ticked, so the button does nothing right now."
                    : "\(glyph: .spread) Spread puts blank cards in the lit cells, chosen in Settings. Every one of them is taken right now, so the button would do nothing." })
        case .clickSpread:
            PhaseScript(page: 6, gate: .spreadCanAct, followsWorld: true, isOptional: true,
                aim: Aim(anchor: .control(.spread), ring: .control(.spread), litCells: true), waitsFor: [.spreadOut],
                title: { c in "Click \(glyph: .spread) Spread: \(c.world.freeSpreadCells) blank cards" },
                body: { _ in "They appear in the lit cells, chosen in Settings. Clicked by mistake? Click it again before you type and they're gone." })
        case .clickGather:
            PhaseScript(page: 6, gate: .spreadCanAct,
                aim: Aim(anchor: .control(.spread), ring: .control(.spread)), waitsFor: [.gathered, .vanished],
                title: { _ in "Click \(glyph: .spreadOn) again to put them away" },
                body: { _ in "Blank cards vanish. Cards with text all go back into the stack at once, so your screen is clear and nothing is lost; one more click puts them back in their spots." })
        case .afterGather:
            PhaseScript(page: 6, gate: .spreadCanAct, aim: Aim(anchor: .control(.spread)),
                title: { c in
                    switch c.reading {
                    case .after(.gathered): "In the stack, back in one click"
                    case .after(.vanished): "Gone, nothing was kept"
                    default: "Spread, then Gather"
                    } },
                body: { c in
                    switch c.reading {
                    case .after(.gathered): "All of them are in the stack, text and all, and your screen is clear. One click on \(glyph: .spread) brings them back to their spots."
                    case .after(.vanished): "Blank cards leave nothing behind. Cards with text would have gone into the stack instead."
                    default: "A second click on \(glyph: .spread) removes an untouched set. A set with text goes into the stack instead, screen clear and nothing lost, and a third click brings it back."
                    } })

        case .clarity:
            PhaseScript(page: 7, isOptional: true, aim: Aim(anchor: .control(.clarity), ring: .control(.clarity)),
                title: { _ in "\(glyph: .clarity) Clarity: a summary per card" },
                body: { _ in "Every card shows its title and a one-line summary, so you can read a full desk at a glance; click a card to unfold. Summaries need your own API key in Settings, or they read “Summary unavailable”." })

        case .aiTool:
            PhaseScript(page: 8, isOptional: true, aim: Aim(anchor: .control(.more), ring: .control(.more)),
                title: { _ in "Your AI tool can add cards" },
                body: { _ in "In Claude Code or Claude Desktop, say “put this in Ideator” and the card lands on the stack. Turn it on in Settings › MCP, behind \(glyph: .more)." })

        case .done:
            PhaseScript(page: 9, aim: Aim(anchor: .stackTop, ring: .menuBarIcon),
                title: { _ in "Done: replay from the menu bar" },
                body: { _ in "Ideator has no Dock icon: the stacked-rectangles icon in the menu bar has the tour, Settings and Quit. Your notes are files in Documents › Ideator, and this button opens the folder." })
        }
    }
}
