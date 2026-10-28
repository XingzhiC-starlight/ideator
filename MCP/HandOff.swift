import Darwin
import Foundation

/// The helper's half of the hand-off: give the card to the Ideator instance on `endpoint` and wait for
/// its answer, which comes once the card is saved. "Is Ideator running?" is whether the endpoint
/// answers. When it does not, `launch` starts the instance (nil when it started, else why not) and
/// the endpoint is tried until `startup` runs out.
nonisolated struct HandOff: Sendable {
    let endpoint: Endpoint
    let launch: @Sendable () -> String?
    var startup: Duration = .seconds(15)
    /// How long after the call the helper waits for the app's answer: past the welcome wait, so the
    /// app's own answer comes first, and short of the minute after which AI tools give up.
    var answer: Duration = .seconds(50)

    /// Set by the helper in the app it starts: the app then does not activate itself.
    static let backgroundVariable = "IDEATOR_BACKGROUND"

    func send(_ card: AddCard) -> ToolReply {
        let called = ContinuousClock.now
        let fd: Int32
        switch reach() {
        case .success(let reached): fd = reached
        case .failure(let refusal): return refusal.reply
        }
        defer { close(fd) }
        let request = HandOffRequest(card: card, wait: HandOffRequest.longestWait - (ContinuousClock.now - called))
        guard let line = request.line, Socket.write(line: line, to: fd) else { return .lost }
        guard Socket.waitForInput(on: fd, until: called + answer) else { return .noAnswer(within: answer) }
        var reader = LineReader(fd: fd, limit: 1 << 20)
        guard case .line(let answer)? = reader.next(), let reply = ToolReply(line: answer) else { return .lost }
        return reply
    }

    private struct NotStarted: Error {
        let reply: ToolReply
    }

    private func reach() -> Result<Int32, NotStarted> {
        if let fd = Socket.connect(to: endpoint.path) { return .success(fd) }
        if let why = launch() { return .failure(NotStarted(reply: .notStarted(why))) }
        let deadline = ContinuousClock.now + startup
        repeat {
            if let fd = Socket.connect(to: endpoint.path) { return .success(fd) }
            Thread.sleep(forTimeInterval: 0.1)
        } while ContinuousClock.now < deadline
        return .failure(NotStarted(reply: .notStarted("it opened no connection for AI tools within \(startup).")))
    }

    /// The app bundle the helper ships in, `Ideator.app/Contents/Helpers/ideator-mcp`: the one it
    /// starts, by its location, never by bundle id, since the owner's Ideator shares the id.
    static func app(containing executable: URL) -> URL? {
        let helpers = executable.deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents",
              app.pathExtension == "app" else { return nil }
        return app
    }
}

/// What the helper hands the app: the card, and how much longer it may wait for Continue. The wait
/// counts from the AI tool's call, so the time a launch took is already spent.
nonisolated struct HandOffRequest: Equatable, Sendable {
    /// CARDS-SPEC.md's longest wait for Continue, from the call to the reply.
    static let longestWait: Duration = .seconds(40)

    let card: AddCard
    let wait: Duration

    init(card: AddCard, wait: Duration) {
        self.card = card
        self.wait = min(max(wait, .zero), Self.longestWait)
    }

    var line: Data? {
        var object = card.arguments
        object["waitMs"] = Int(wait / .milliseconds(1))
        return try? JSONSerialization.data(withJSONObject: object)
    }

    /// The card is read like a tool call, so the app takes only what the helper would pass. A line
    /// with no wait gets the longest.
    static func parse(_ object: [String: Any]) -> Result<HandOffRequest, AddCard.Refusal> {
        AddCard.parse(object).map { card in
            HandOffRequest(card: card, wait: (object["waitMs"] as? Int).map { .milliseconds($0) } ?? longestWait)
        }
    }
}
