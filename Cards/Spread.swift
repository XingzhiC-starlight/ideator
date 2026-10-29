import Foundation

/// Settings › Spread's ticked cells for this run: read once from `Preferences`, written back on every
/// change. A scratch run's preferences write nowhere, so there a change lasts until the run quits.
/// The controller reads it only when the button is pressed, which is why a Settings change moves the
/// set at the next Spread, never at once.
final class SpreadChoice {
    private let preferences: Preferences
    var cells: SpreadCells { didSet { preferences.spreadCells = cells } }

    init(preferences: Preferences) {
        self.preferences = preferences
        cells = preferences.spreadCells
    }
}

/// Why the last Spread click changed nothing. Presentation only: the controller holds it beside
/// `visibility`, it is never saved, and it stays until a Spread or Gather click changes something.
enum SpreadRefusal: Equatable {
    /// No cell is ticked in Settings.
    case noCells
    /// Every cell the click would fill is taken.
    case taken

    /// What a Spread click that carried `cells` means: nil when it changed the desk. Relies on the
    /// desk's promise (desk check P8) that a click that puts nothing out changes nothing.
    init?(cells: SpreadCells, changedDesk: Bool) {
        guard !changedDesk else { return nil }
        self = cells.isEmpty ? .noCells : .taken
    }
}

extension SpreadButton {
    /// The Spread button's tooltip. A refusal is about spreading, so it shows only while a click
    /// would spread.
    func help(after refusal: SpreadRefusal?) -> String {
        switch (self, refusal) {
        case (.gather, _): "Gather cards"
        case (.spread, .noCells?): "Pick Spread cells in Settings"
        case (.spread, .taken?): "Your Spread cells are taken"
        case (.spread, nil): "Spread cards"
        }
    }
}
