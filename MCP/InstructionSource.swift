import Darwin
import Foundation

/// How the helper learns the instruction at a session start, without ever starting Ideator:
/// - a running Ideator is asked over the socket cards use, and its answer stands, since a scratch run
///   keeps its edit nowhere else;
/// - otherwise the saved preferences are read, except by a scratch run's helper, which saves nothing;
/// - otherwise the standard text.
nonisolated struct InstructionSource: Sendable {
    private let endpoint: Endpoint
    private let appDomain: String?
    private let patience: Duration

    /// `patience` bounds the ask: a busy Ideator must not hold up a session start, and the saved text answers then.
    init(scratchFolder: URL?, appDomain: String?, directory: URL = Endpoint.userTemporaryDirectory,
         patience: Duration = .seconds(2)) {
        endpoint = Endpoint(scratchFolder: scratchFolder, directory: directory)
        self.appDomain = scratchFolder == nil ? appDomain : nil
        self.patience = patience
    }

    func current() -> String? {
        (running() ?? appDomain.map(Instruction.saved(inDomain:)) ?? Instruction()).forSession
    }

    static let request = Data(#"{"request":"instruction"}"#.utf8)

    static func isRequest(_ line: [String: Any]) -> Bool { line["request"] as? String == "instruction" }

    /// An app from before the ask reads it as a card with no title and replies with an error; that is nil too.
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
