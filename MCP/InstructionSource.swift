import Darwin
import Foundation

/// How the helper learns the instruction at a session start, without ever starting Ideator:
/// - a running Ideator on the helper's endpoint is asked, over the socket cards use, and its answer
///   stands, since it holds an edit that a scratch run keeps nowhere else;
/// - otherwise the text the app saved in its preferences is read, for the owner's Ideator;
/// - otherwise the standard text. A scratch run saves nothing, so its helper never reads preferences.
nonisolated struct InstructionSource: Sendable {
    private let endpoint: Endpoint
    private let appDomain: String?
    private let patience: Duration

    /// `appDomain` is the preferences domain of the app that contains the helper. `patience` bounds the
    /// ask: an Ideator that is busy must not hold up a session start, and the saved text is the answer then.
    init(scratchFolder: URL?, appDomain: String?, directory: URL = Endpoint.userTemporaryDirectory,
         patience: Duration = .seconds(2)) {
        endpoint = Endpoint(scratchFolder: scratchFolder, directory: directory)
        self.appDomain = scratchFolder == nil ? appDomain : nil
        self.patience = patience
    }

    /// What the next session is given; nil for none.
    func current() -> String? {
        (running() ?? appDomain.map(Instruction.saved(inDomain:)) ?? Instruction()).forSession
    }

    /// The line the helper sends the app, and how the app tells it from a card.
    static let request = Data(#"{"request":"instruction"}"#.utf8)

    static func isRequest(_ line: [String: Any]) -> Bool { line["request"] as? String == "instruction" }

    /// Nil when nothing answers, the answer is late, or the app does not know the ask, as an app from
    /// before the ask reads it as a card with no title and says so with an error.
    private func running() -> Instruction? {
        guard let fd = Socket.connect(to: endpoint.path) else { return nil }
        defer { close(fd) }
        let (seconds, attoseconds) = patience.components
        var timeout = timeval(tv_sec: Int(seconds), tv_usec: Int32(attoseconds / 1_000_000_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard Socket.write(line: Self.request, to: fd) else { return nil }
        var reader = LineReader(fd: fd, limit: 1 << 20)
        guard case .line(let answer)? = reader.next(), let reply = ToolReply(line: answer), !reply.isError else { return nil }
        return Instruction(edited: reply.text)
    }
}
