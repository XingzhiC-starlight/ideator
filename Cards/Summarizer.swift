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

    /// A request for one version of one note: waiting out the quiet period, then in flight.
    private struct Job {
        let source: Digest
        let task: Task<Void, Never>
    }

    /// `summarize` is the request itself, given the key it is sent with; tests answer it by hand.
    init(apiKey: @escaping () -> String?, deliver: @escaping (CardID, Summary) -> Void,
         summarize: @escaping (Note, String) async -> Summary.Outcome = Anthropic.summarize) {
        self.apiKey = apiKey
        self.deliver = deliver
        self.summarize = summarize
    }

    /// Reconciles jobs with `cards` (every card, stacked or popped). A card wants a job when a key
    /// exists, its body wants a summary, and its latest attempt (success or failure) is for an
    /// older version of the note. `typing` is the card just edited: its job (re)starts the quiet
    /// period. Any other wanted card without a job starts at once. A job whose card no longer
    /// wants it is cancelled, and a cancelled job never delivers. No key → nothing is requested.
    func sync(_ cards: [Card], typing: CardID?) {
        guard let key = apiKey() else {
            for job in jobs.values { job.task.cancel() }
            jobs = [:]
            return
        }
        let wanted = cards.filter { $0.note.wantsSummary && $0.summary?.source != $0.digest }
        let wantedDigests = Dictionary(wanted.map { ($0.id, $0.digest) }, uniquingKeysWith: { first, _ in first })
        for (id, job) in jobs where wantedDigests[id] != job.source || id == typing {
            job.task.cancel()
            jobs[id] = nil
        }
        for card in wanted where jobs[card.id] == nil {
            let delay: Duration = card.id == typing ? Self.quietPeriod : .zero
            let (id, note, source, summarize) = (card.id, card.note, card.digest, summarize)
            jobs[id] = Job(source: source, task: Task { [weak self] in
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

/// The one Anthropic call: Messages API over URLSession, no SDK. Wire types are private; the
/// only things that cross this boundary are a `Note` in and a `Summary.Outcome` out.
enum Anthropic {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-haiku-5-5"

    /// Never throws: every failure becomes `.failed(reason:)`, whose reason is the hover text
    /// under "Summary unavailable".
    ///
    /// Haiku 5.5 thinks adaptively by default and thinking counts toward `max_tokens`, so the cap
    /// leaves room for it and `effort: "low"` keeps it short. The answer is read from the `text`
    /// blocks by type, never as `content[0]`, because a response can begin with `thinking` blocks.
    static func summarize(_ note: Note, apiKey: String) async -> Summary.Outcome {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body = RequestBody(model: model, max_tokens: 1024, output_config: .init(effort: "low"),
                               system: Summary.instructions,
                               messages: [.init(role: "user", content: note.plainText)])
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
                return .failed(reason: "HTTP \(status): \(message ?? "request failed")")
            }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            if reply.stop_reason == "refusal" {
                return .failed(reason: "The model declined to summarize this card.")
            }
            let text = reply.content.filter { $0.type == "text" }.compactMap(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .failed(reason: "The response had no text.") : .text(text)
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

    private struct ErrorBody: Decodable {
        let error: Detail

        struct Detail: Decodable {
            let type: String
            let message: String
        }
    }
}
