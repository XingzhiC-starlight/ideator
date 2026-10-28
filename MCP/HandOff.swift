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

    /// Set by the helper in the app it starts: the app then does not activate itself.
    static let backgroundVariable = "IDEATOR_BACKGROUND"

    func send(_ card: AddCard) -> ToolReply {
        let fd: Int32
        switch reach() {
        case .success(let reached): fd = reached
        case .failure(let refusal): return refusal.reply
        }
        defer { close(fd) }
        guard let line = try? JSONSerialization.data(withJSONObject: card.arguments),
              Socket.write(line: line, to: fd) else { return .lost }
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
