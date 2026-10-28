import CoreFoundation
import Foundation

// Compiled into the app and the helper (`ideator-mcp`): pure values, no AppKit.

/// What Ideator's MCP server tells an AI tool when a session starts (MCP's server `instructions`).
nonisolated struct Instruction: Equatable, Sendable {
    /// CARDS-SPEC.md's default text.
    static let standard = "Ideator keeps sticky-note cards on the user's Mac desktop, for ideas, to-dos and "
        + "things to remember later. A card has a title, then lines, bullets or checkboxes (up to 3 levels). Cards "
        + "scroll, so length is fine, but the first few lines are what the user sees at a glance: lead with what "
        + "matters, and keep one topic per card. Create a card only when the user asks; you may offer when something "
        + "looks worth saving."

    /// No key means the standard text, so a later build's standard text reaches everyone who never edited it.
    static let preferenceKey = "AIToolsInstruction"

    /// The longest text there is, in bytes of UTF-8. The helper reads it as JSON, which writes a control
    /// character as six bytes, so a text this long is at worst about 600,000 bytes: within the 1 MiB
    /// `InstructionSource` reads. Past that the reply would be dropped and the helper would serve the
    /// standard text without a word.
    static let byteLimit = 100_000

    /// What the user typed, or nil while the standard text stands. Typing the standard text is no edit.
    /// Whatever the source, a text past `byteLimit` is cut to it.
    private(set) var edited: String?

    init(edited: String? = nil) {
        let kept = edited.map(Self.clipped)
        self.edited = kept == Self.standard ? nil : kept
    }

    /// Cut between characters, so no character loses a byte.
    private static func clipped(_ text: String) -> String {
        guard text.utf8.count > byteLimit else { return text }
        var kept = ""
        var size = 0
        for character in text {
            size += character.utf8.count
            guard size <= byteLimit else { break }
            kept.append(character)
        }
        return kept
    }

    var text: String { edited ?? Self.standard }

    var isStandard: Bool { edited == nil }

    /// Nil when blank: a user who clears the editor wants no instruction.
    var forSession: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    mutating func edit(to text: String) { self = Instruction(edited: text) }

    mutating func reset() { self = Instruction() }

    /// Read without the app running.
    static func saved(inDomain domain: String) -> Instruction {
        Instruction(edited: CFPreferencesCopyAppValue(preferenceKey as CFString, domain as CFString) as? String)
    }
}
