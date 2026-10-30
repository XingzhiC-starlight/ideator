import Foundation

/// An SF Symbol the reader sees on a control. The tour draws the same symbol as an inline chip, so
/// the ribbon and the hover row take their symbol names from here too, and a chip cannot drift from
/// its button.
enum Glyph: String, CaseIterable {
    case plus
    case hide = "chevron.up"
    case show = "chevron.down"
    case returnToStack = "arrow.uturn.backward"
    case trash
    case spread = "square.grid.2x2"
    /// The Spread symbol in the accent color: the button while a set is out, which gathers it.
    case spreadOn
    case clarity = "line.3.horizontal.decrease.circle"
    case more = "ellipsis.circle"

    var symbolName: String {
        switch self {
        case .spreadOn: Glyph.spread.rawValue
        default: rawValue
        }
    }

    /// The control's accessibility name, which VoiceOver reads for a chip inside a sentence.
    var spoken: String {
        switch self {
        case .plus: "New"
        case .hide: "Hide all"
        case .show: "Show all"
        case .returnToStack: "Return to stack"
        case .trash: "Delete this card"
        case .spread, .spreadOn: "Spread"
        case .clarity: "Clarity"
        case .more: "Settings and quit"
        }
    }
}
