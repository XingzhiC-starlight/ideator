import Foundation

// Compiled into both the app and the helper (`ideator-mcp`), so the two halves of the hand-off read
// cards and replies with the same code. Pure values: no AppKit, no files.

/// One `add_card` call, as it crosses into Ideator twice: from the AI tool into the helper, and from
/// the helper into the app. Both read it with `parse`, so the app takes exactly the cards the helper
/// passes, and nothing a stray local process sends that the helper would refuse.
nonisolated struct AddCard: Equatable, Sendable {
    /// The card's header: one line, trimmed, never empty.
    let title: String
    /// The body in the card file's Markdown, as the AI tool wrote it.
    let body: String

    /// The backstop against runaway input, like the limit on pasted HTML in `Clipboard`.
    static let byteLimit = 1_000_000

    enum Refusal: Error, Equatable {
        /// No `title`, one that is not a string, or one with nothing but spaces.
        case noTitle
        case bodyNotText
        /// Title and body together pass `byteLimit` bytes of UTF-8.
        case tooLong
    }

    /// Reads the tool call's `arguments`. A header is one line, so each line break in the title
    /// becomes a space. A missing or null body is an empty one.
    static func parse(_ arguments: [String: Any]) -> Result<AddCard, Refusal> {
        guard let title = arguments["title"] as? String else { return .failure(.noTitle) }
        let body: String
        switch arguments["body"] {
        case nil, is NSNull: body = ""
        case let text as String: body = text
        default: return .failure(.bodyNotText)
        }
        guard title.utf8.count + body.utf8.count <= byteLimit else { return .failure(.tooLong) }
        let line = title.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !line.isEmpty else { return .failure(.noTitle) }
        return .success(AddCard(title: line, body: body))
    }

    /// What the helper sends the app; `parse` reads it back to the same card.
    var arguments: [String: Any] { ["title": title, "body": body] }

    private init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// What `add_card` answers: the text the AI tool reads, and whether the call failed (MCP's `isError`,
/// which tells the model to fix its call or tell the user).
nonisolated struct ToolReply: Equatable, Sendable {
    let text: String
    let isError: Bool

    static func done(_ text: String) -> ToolReply { ToolReply(text: text, isError: false) }
    static func failed(_ text: String) -> ToolReply { ToolReply(text: text, isError: true) }

    /// The app's answer as one line to the helper.
    var line: Data { (try? JSONSerialization.data(withJSONObject: ["text": text, "isError": isError])) ?? Data() }

    init?(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let text = object["text"] as? String, let isError = object["isError"] as? Bool else { return nil }
        self.init(text: text, isError: isError)
    }

    private init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}

nonisolated extension ToolReply {
    /// The app closed the connection without an answer: it quit, or was quit, before it saved.
    static let lost = failed("Ideator quit before it saved the card. Nothing was saved.")
    /// A line the app could not read as a card.
    static let unreadable = failed("Ideator couldn't read the card it was sent. Nothing was saved.")

    static func notStarted(_ why: String) -> ToolReply {
        failed("Ideator isn't running and didn't start: \(why) Nothing was saved. Open Ideator, then ask again.")
    }
}

nonisolated extension AddCard.Refusal {
    var reply: ToolReply {
        switch self {
        case .noTitle: .failed("A card needs a title: pass title as a string with some text in it. Nothing was saved.")
        case .bodyNotText: .failed("The body must be a string of Markdown. Nothing was saved.")
        case .tooLong: .failed("The card is too long: its title and body together pass Ideator's limit of 1 MB. "
            + "Nothing was saved.")
        }
    }
}
