import Darwin
import Foundation

// Ideator's side of cards from AI tools: the inbox on this instance's endpoint, the cards held while
// the welcome card waits, and the two settings. The helper's side and the shared types are in MCP/.

/// "Let AI tools add cards" and "Cards from AI tools go to".
struct AIToolSettings: Equatable {
    var enabled = true
    var landing = Landing.top
}

/// The settings for this run: read once from `Preferences`, written back on every change. A scratch
/// run's preferences write nowhere, so there a change lasts until the run quits.
final class AIToolsChoice {
    private let preferences: Preferences
    var value: AIToolSettings { didSet { preferences.aiTools = value } }

    init(preferences: Preferences) {
        self.preferences = preferences
        value = preferences.aiTools
    }
}

extension AddCard {
    /// The body is read by the card file's own reader, so a list, a checkbox or bold reads the same
    /// here as in a file, and any other line stays plain.
    var note: Note {
        var lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return Note(header: title, body: Note.bodyLines(lines))
    }
}

extension ToolReply {
    static func added(_ title: String, to landing: Landing) -> ToolReply {
        .done("Added \"\(title)\" to the \(landing == .top ? "top" : "bottom") of the stack.")
    }

    static let turnedOff = failed("Turned off in Ideator's Settings")

    static let waitingForContinue = failed("Ideator is showing its welcome card and saves no card until the user "
        + "presses Continue on it. Nothing was saved. Ask the user to press Continue in Ideator, then try again.")

    /// The card is on the desk, so a second call would add it twice.
    static func notSaved(_ title: String, folder: URL) -> ToolReply {
        failed("Ideator added \"\(title)\" to the stack but couldn't save it to \(folder.path). It saves the card "
            + "once the folder lets it, so don't add it again.")
    }
}

/// Cards that arrive while the welcome card waits for Continue. Each waits `patience` at most, then is
/// answered "press Continue" and dropped: the AI tool gets an answer before its own timeout, and a card
/// it was told is not saved never appears later.
final class HeldCards {
    private struct Held {
        let card: AddCard
        let reply: @Sendable (ToolReply) -> Void
        let deadline: ContinuousClock.Instant
    }

    private let patience: Duration
    private var held: [Held] = []

    init(patience: Duration = .seconds(40)) {
        self.patience = patience
    }

    func hold(_ card: AddCard, reply: @escaping @Sendable (ToolReply) -> Void) {
        held.append(Held(card: card, reply: reply, deadline: .now + patience))
        Task { [weak self, patience] in
            try? await Task.sleep(for: patience)
            self?.expire()
        }
    }

    /// The notes are open: each card is answered by `answer`, in the order it came, unless its
    /// patience ran out meanwhile, as it can while the Documents prompt holds the main thread.
    func release(_ answer: (AddCard) -> ToolReply) {
        expire()
        let ready = held
        held = []
        for item in ready { item.reply(answer(item.card)) }
    }

    private func expire() {
        let now = ContinuousClock.now
        let late = held.filter { $0.deadline <= now }
        held.removeAll { $0.deadline <= now }
        for item in late { item.reply(.waitingForContinue) }
    }
}

/// Ideator's half of the hand-off: listens on this instance's endpoint and reads one card per
/// connection. Any process of this user can connect, so each line is read like a tool call, by
/// `AddCard.parse`, and `receive` answers through the reply it is given, once, when it is ready.
/// `close` drops every connection still waiting, as quitting does, so each helper hears that
/// nothing was saved.
final class ToolInbox {
    typealias Receive = @MainActor (AddCard, @escaping @Sendable (ToolReply) -> Void) -> Void

    private let source: DispatchSourceRead
    private let path: String
    /// The socket file this instance made, so `close` never removes a newer instance's.
    private let file: ino_t
    private let connections = Connections()

    /// Nil when another instance answers on `endpoint`, or the socket could not be made.
    init?(endpoint: Endpoint, receive: @escaping Receive) {
        guard let listener = Socket.listen(at: endpoint.path) else { return nil }
        var info = stat()
        guard stat(endpoint.path, &info) == 0 else {
            Darwin.close(listener)
            return nil
        }
        path = endpoint.path
        file = info.st_ino
        source = Self.serve(listener, connections, receive)
    }

    func close() {
        guard connections.close() else { return }
        source.cancel()
        var info = stat()
        if stat(path, &info) == 0, info.st_ino == file { unlink(path) }
    }

    /// Off the main thread: accepting and reading never wait on the UI, and only a parsed card reaches it.
    private nonisolated static func serve(_ listener: Int32, _ connections: Connections,
                                          _ receive: @escaping Receive) -> DispatchSourceRead {
        _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: DispatchQueue(label: "Ideator.ToolInbox"))
        source.setEventHandler {
            while true {
                let fd = Darwin.accept(listener, nil, nil)
                guard fd >= 0 else { return }
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
                guard let connection = connections.open(fd) else {
                    Darwin.close(fd)
                    continue
                }
                DispatchQueue.global().async { read(fd, connection, receive) }
            }
        }
        source.setCancelHandler { Darwin.close(listener) }
        source.resume()
        return source
    }

    private nonisolated static func read(_ fd: Int32, _ connection: Connections.Connection, _ receive: @escaping Receive) {
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var reader = LineReader(fd: fd, limit: 8 * AddCard.byteLimit)
        let parsed: Result<AddCard, AddCard.Refusal>? = switch reader.next() {
        case .line(let line)?: ((try? JSONSerialization.jsonObject(with: line)) as? [String: Any]).map(AddCard.parse)
        case .tooLong?: .failure(.tooLong)
        case nil: nil
        }
        switch parsed {
        case .success(let card)?: Task { @MainActor in receive(card) { connection.reply($0) } }
        case .failure(let refusal)?: connection.reply(refusal.reply)
        case nil: connection.reply(.unreadable)
        }
    }
}

/// The connections waiting for an answer. Each is answered at most once: a second reply, or one after
/// `close`, writes nothing.
private nonisolated final class Connections: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [ObjectIdentifier: Int32] = [:]
    private var closed = false

    final class Connection: @unchecked Sendable {
        fileprivate let owner: Connections

        fileprivate init(owner: Connections) {
            self.owner = owner
        }

        func reply(_ reply: ToolReply) {
            owner.finish(self, with: reply)
        }
    }

    func open(_ fd: Int32) -> Connection? {
        lock.withLock {
            guard !closed else { return nil }
            let connection = Connection(owner: self)
            waiting[ObjectIdentifier(connection)] = fd
            return connection
        }
    }

    fileprivate func finish(_ connection: Connection, with reply: ToolReply) {
        lock.withLock {
            guard let fd = waiting.removeValue(forKey: ObjectIdentifier(connection)) else { return }
            Socket.write(line: reply.line, to: fd)
            Darwin.close(fd)
        }
    }

    /// False when it was closed already.
    func close() -> Bool {
        lock.withLock {
            guard !closed else { return false }
            closed = true
            for fd in waiting.values { Darwin.close(fd) }
            waiting = [:]
            return true
        }
    }
}
