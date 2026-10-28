import Foundation

/// Keeps exactly one pending request for every card whose summary is stale, and none for any
/// other card. The wanted set is derived from the cards on every `sync`, so calling it after
/// every command is cheap and harmless: launch, typing, refresh, a new API key and an outside
/// file edit all go through the same call. The summarizer stores no summaries and no status;
/// results go back through `deliver` (→ `Command.storeSummary`), and the UI derives spinner and
/// failure states from the desk (`Desk.summaryFace`).
final class Summarizer {
    /// "A few seconds after typing stops."
    static let quietPeriod: Duration = .seconds(3)

    private let apiKey: () -> String?
    private let deliver: (CardID, Summary) -> Void
    private let summarize: (Note, String) async -> Summary.Outcome
    private var jobs: [CardID: Job] = [:]

    /// A request for one version of one note under one key: waiting out the quiet period, then in flight.
    private struct Job {
        let source: Digest
        let key: String
        let task: Task<Void, Never>
    }

    /// `summarize` is the request itself, given the key it is sent with, which also says which
    /// company it goes to; tests answer it by hand.
    init(apiKey: @escaping () -> String?, deliver: @escaping (CardID, Summary) -> Void,
         summarize: @escaping (Note, String) async -> Summary.Outcome = { note, key in
             await Provider(key: key).summarize(note, apiKey: key)
         }) {
        self.apiKey = apiKey
        self.deliver = deliver
        self.summarize = summarize
    }

    /// Reconciles jobs with `cards` (every card, stacked or popped). A card wants a job when a key
    /// exists, its body wants a summary, and its latest attempt (success or failure) is for an
    /// older version of the note. `typing` is the card just edited: its job (re)starts the quiet
    /// period. Any other wanted card without a job starts at once. A job whose card no longer
    /// wants it, or that was started under another key, is cancelled (the second case starts
    /// again at once under the current key), and a cancelled job never delivers. No key → nothing
    /// is requested.
    func sync(_ cards: [Card], typing: CardID?) {
        guard let key = apiKey() else {
            for job in jobs.values { job.task.cancel() }
            jobs = [:]
            return
        }
        let wanted = cards.filter { $0.note.wantsSummary && $0.summary?.source != $0.digest }
        let wantedDigests = Dictionary(wanted.map { ($0.id, $0.digest) }, uniquingKeysWith: { first, _ in first })
        for (id, job) in jobs where wantedDigests[id] != job.source || job.key != key || id == typing {
            job.task.cancel()
            jobs[id] = nil
        }
        for card in wanted where jobs[card.id] == nil {
            let delay: Duration = card.id == typing ? Self.quietPeriod : .zero
            let (id, note, source, summarize) = (card.id, card.note, card.digest, summarize)
            jobs[id] = Job(source: source, key: key, task: Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                let outcome = await summarize(note, key)
                guard !Task.isCancelled, let self else { return }
                self.jobs[id] = nil
                self.deliver(id, Summary(source: source, outcome: outcome))
            })
        }
    }
}

/// Whose key it is. A key that starts with `sk-ant-` is Anthropic's and any other key is
/// OpenAI's: this is the one place that reads a key's start. The only things that cross this
/// boundary are a `Note` in and a `Summary.Outcome` out; the wire formats are `Anthropic` and
/// `OpenAI`.
enum Provider: Equatable {
    case anthropic, openAI

    init(key: String) {
        self = key.hasPrefix("sk-ant-") ? .anthropic : .openAI
    }

    var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        }
    }

    func request(for note: Note, apiKey: String) throws -> URLRequest {
        switch self {
        case .anthropic: try Anthropic.request(for: note, apiKey: apiKey)
        case .openAI: try OpenAI.request(for: note, apiKey: apiKey)
        }
    }

    func outcome(status: Int, data: Data) -> Summary.Outcome {
        switch self {
        case .anthropic: Anthropic.outcome(status: status, data: data)
        case .openAI: OpenAI.outcome(status: status, data: data)
        }
    }

    /// Never throws: every failure becomes `.failed(reason:)`, whose reason is the hover text
    /// under "Summary unavailable".
    func summarize(_ note: Note, apiKey: String) async -> Summary.Outcome {
        do {
            let (data, response) = try await URLSession.shared.data(for: request(for: note, apiKey: apiKey))
            return outcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }
}

enum Anthropic {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-haiku-5-5"

    /// Haiku 5.5 thinks adaptively by default and thinking counts toward `max_tokens`, so the cap
    /// leaves room for it and `effort: "low"` keeps it short.
    static func request(for note: Note, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model, max_tokens: 1024, output_config: .init(effort: "low"), system: Summary.instructions,
            messages: [.init(role: "user", content: note.plainText)]))
        return request
    }

    /// The answer is read from the `text` blocks by type, never as `content[0]`, because a
    /// response can begin with `thinking` blocks.
    static func outcome(status: Int, data: Data) -> Summary.Outcome {
        guard (200..<300).contains(status) else { return httpFailure(status: status, data: data) }
        do {
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            if reply.stop_reason == "refusal" { return declined }
            return summary(from: reply.content.filter { $0.type == "text" }.compactMap(\.text).joined())
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    // Wire types, matching the JSON field for field.

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let output_config: OutputConfig
        let system: String
        let messages: [Message]

        struct OutputConfig: Encodable { let effort: String }
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct Reply: Decodable {
        let content: [Block]
        let stop_reason: String?

        struct Block: Decodable {
            let type: String
            let text: String?
        }
    }
}

/// Request and reply shapes: https://developers.openai.com/api/reference/resources/responses/methods/create
enum OpenAI {
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    static let model = "gpt-6-luna"

    /// `gpt-6-luna` reasons, and reasoning tokens count toward `max_output_tokens`, so the cap
    /// leaves room for them and `effort: "low"` keeps them few. `temperature` and `top_p` are left
    /// out because a reasoning model may refuse them. `store: false` because OpenAI keeps a stored
    /// response for 30 days and the app never reads one back.
    static func request(for note: Note, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model, instructions: Summary.instructions, input: note.plainText, max_output_tokens: 4096,
            reasoning: .init(effort: "low"), store: false))
        return request
    }

    /// The answer is read from the `output_text` parts of the `message` items by type, never as
    /// `output[0]`, because the output can begin with a `reasoning` item. A response that stopped
    /// early is a failure: its text, if any, is a summary cut short.
    static func outcome(status: Int, data: Data) -> Summary.Outcome {
        guard (200..<300).contains(status) else { return httpFailure(status: status, data: data) }
        do {
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            if reply.status == "failed" { return .failed(reason: reply.error?.message ?? "The request failed.") }
            if reply.status == "incomplete" {
                return .failed(reason: "The response was cut off" + (reply.incomplete_details?.reason.map { " (\($0))" } ?? "") + ".")
            }
            let parts = (reply.output ?? []).flatMap(\.content)
            if parts.contains(where: { $0.type == "refusal" }) { return declined }
            return summary(from: parts.filter { $0.type == "output_text" }.compactMap(\.text).joined())
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    // Wire types, matching the JSON field for field.

    private struct RequestBody: Encodable {
        let model: String
        let instructions: String
        let input: String
        let max_output_tokens: Int
        let reasoning: Reasoning
        let store: Bool

        struct Reasoning: Encodable { let effort: String }
    }

    private struct Reply: Decodable {
        let status: String?
        let incomplete_details: Incomplete?
        let error: Failure?
        let output: [Item]?

        struct Incomplete: Decodable { let reason: String? }
        struct Failure: Decodable { let message: String? }

        /// Only a `message` item has parts worth reading; the other item types differ in shape.
        struct Item: Decodable {
            let content: [Part]

            private enum Keys: String, CodingKey { case type, content }

            init(from decoder: Decoder) throws {
                let keys = try decoder.container(keyedBy: Keys.self)
                let isMessage = try keys.decode(String.self, forKey: .type) == "message"
                content = isMessage ? try keys.decode([Part].self, forKey: .content) : []
            }
        }

        struct Part: Decodable {
            let type: String
            let text: String?
        }
    }
}

private let declined = Summary.Outcome.failed(reason: "The model declined to summarize this card.")

private func summary(from text: String) -> Summary.Outcome {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? .failed(reason: "The response had no text.") : .text(trimmed)
}

/// Both APIs answer a refused request with `{"error": {"message": …}}`.
private func httpFailure(status: Int, data: Data) -> Summary.Outcome {
    struct ErrorBody: Decodable {
        let error: Detail

        struct Detail: Decodable { let message: String }
    }
    let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
    return .failed(reason: "HTTP \(status): \(message ?? "request failed")")
}
