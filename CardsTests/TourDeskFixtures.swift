import Foundation
@testable import Ideator

/// Desks and worlds for the tour's tests, built the way a launch loads them: from notes and a
/// sidecar, so the desk's own rules decide everything a test reads back.
enum TourDeskFixtures {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// A screen big enough that the 5 x 4 grid has room for any card.
    static let grid = Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 900))

    static func id(_ name: String) -> CardID { CardID(rawValue: name) }

    static func slot(_ index: Int) -> Place { .slot(Slot(index: index)!) }

    static func cells(_ indices: Int...) -> SpreadCells { SpreadCells(indices: indices) }

    /// `popped` cards on the desktop at their places, `stack` top first, and, with `set`, a Spread
    /// set laid out for those cells that remembers each member's home. A name in `blank` has no text.
    static func desk(popped: [(String, Place)] = [], stack: [String] = [], stackSlot: Int? = nil,
                     set: (cells: SpreadCells, homes: [(String, Place)])? = nil,
                     blank: Set<String> = []) -> Desk {
        let names = popped.map(\.0) + stack
        func placement(_ name: String, _ place: Place) -> SavedPlacement {
            switch place {
            case .slot(let slot): SavedPlacement(slot: slot.index, card: id(name))
            case .free(let point): SavedPlacement(free: point, card: id(name))
            }
        }
        return Desk(
            notes: Dictionary(uniqueKeysWithValues: names.map { name in
                (id(name), blank.contains(name) ? Note.blank : Note(header: name, body: []))
            }),
            saved: SavedDesk(stackSlot: stackSlot,
                             placements: popped.map { placement($0.0, $0.1) },
                             stack: stack.map { id($0) },
                             spread: set.map { set in
                                 SavedSpread(cells: set.cells.indices, members: set.homes.map { placement($0.0, $0.1) })
                             }))
    }

    /// Every cell but the stack's taken by a card, so New and Pop make nothing: "Desktop full".
    static func fullDesk(stack: [String] = ["s"]) -> Desk {
        desk(popped: Slot.all.filter { $0 != Slot.stackHome }.map { ("p\($0.index)", Place.slot($0)) }, stack: stack)
    }

    static let shortcut = ShortcutReading(display: "⌃⌥I", works: true)

    /// A look at `desk`. The flow tells a world which card is the reader's; a test that builds a
    /// world without a flow says it with `reader`.
    static func world(_ desk: Desk, visibility: Visibility = .all, shortcut: ShortcutReading = shortcut,
                      cells: SpreadCells = .standard, reader: String? = nil) -> TourWorld {
        let world = TourWorld(desk: desk, grid: grid, visibility: visibility, shortcut: shortcut, spreadCells: cells, now: now)
        world.readerCard = reader.map { id($0) }
        return world
    }
}
