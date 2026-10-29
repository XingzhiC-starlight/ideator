// cards-mcp: a throwaway MCP client for the verify recipes. It starts Ideator's helper (ideator-mcp)
// the way Claude Code, Codex or Claude Desktop does, as a child process speaking newline-delimited
// JSON-RPC on its stdin and stdout, and runs one session of steps against it.
//
//   cards-mcp HELPER [-CardsFolder FOLDER] STEP...
//
// Steps, in order, each one request and its reply:
//   initialize[=VERSION]   legacy handshake (default 2025-11-25), then notifications/initialized
//   discover               server/discover with 2026-07-28 _meta
//   list                   tools/list
//   ping                   ping
//   add TITLE [BODYFILE]   tools/call add_card with the title and, if given, the file's text as the body
//   add-bytes N            tools/call add_card titled "Too long" whose body is N bytes of "x"
//
// Prints each request (cut at 300 characters) after "->" and each reply after "<-" with the time it took.
// After an initialize or discover reply it prints the `instructions` field in full on a line of its own.
// Exit 1 when the helper ends or a reply takes longer than CARDS_MCP_TIMEOUT seconds (default 120).
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let helper = args.first else {
    FileHandle.standardError.write(Data("usage: cards-mcp HELPER [-CardsFolder FOLDER] STEP...\n".utf8))
    exit(2)
}
var rest = Array(args.dropFirst())
var helperArguments: [String] = []
if rest.first == "-CardsFolder", rest.count >= 2 {
    helperArguments = Array(rest.prefix(2))
    rest.removeFirst(2)
}
let timeout = Double(ProcessInfo.processInfo.environment["CARDS_MCP_TIMEOUT"] ?? "") ?? 120

let process = Process()
process.executableURL = URL(filePath: helper)
process.arguments = helperArguments
let toHelper = Pipe(), fromHelper = Pipe()
process.standardInput = toHelper
process.standardOutput = fromHelper
do { try process.run() } catch {
    print("cards-mcp: could not start \(helper): \(error)")
    exit(1)
}

final class Lines: @unchecked Sendable {
    private let lock = NSCondition()
    private var buffer = Data()
    private var ended = false

    init(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.lock.lock()
            if data.isEmpty { self.ended = true; handle.readabilityHandler = nil } else { self.buffer.append(data) }
            self.lock.broadcast()
            self.lock.unlock()
        }
    }

    func next(within seconds: Double) -> Data? {
        let deadline = Date().addingTimeInterval(seconds)
        lock.lock()
        defer { lock.unlock() }
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return Data(line)
            }
            if ended || !lock.wait(until: deadline) { return nil }
        }
    }
}

let replies = Lines(fromHelper.fileHandleForReading)
var nextID = 0

func cut(_ data: Data) -> String {
    let text = String(decoding: data, as: UTF8.self)
    return text.count > 300 ? String(text.prefix(300)) + "… (\(data.count) bytes)" : text
}

func encode(_ message: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])
}

/// The request as printed: a card's title and body as their lengths, as cards-verify logs typed text.
func redacted(_ message: [String: Any]) -> [String: Any] {
    guard var params = message["params"] as? [String: Any], let arguments = params["arguments"] as? [String: Any] else { return message }
    params["arguments"] = arguments.mapValues { value in (value as? String).map { "<\($0.count) characters>" } ?? value }
    var copy = message
    copy["params"] = params
    return copy
}

func send(_ message: [String: Any]) {
    print("-> \(cut(encode(redacted(message))))")
    toHelper.fileHandleForWriting.write(encode(message) + Data("\n".utf8))
}

func request(_ method: String, _ params: [String: Any]) {
    nextID += 1
    let started = Date()
    send(["jsonrpc": "2.0", "id": nextID, "method": method, "params": params])
    guard let reply = replies.next(within: timeout) else {
        print("<- nothing within \(Int(timeout)) s, or the helper ended (status \(process.isRunning ? "running" : "\(process.terminationStatus)"))")
        exit(1)
    }
    print(String(format: "<- %@  (%.2f s)", cut(reply), Date().timeIntervalSince(started)))
    if method == "initialize" || method == "server/discover" {
        let result = (try? JSONSerialization.jsonObject(with: reply) as? [String: Any])?["result"] as? [String: Any]
        let text = result?["instructions"] as? String
        print("   instructions (\(text.map { "\($0.count) characters" } ?? "none")): "
            + (text.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .withoutEscapingSlashes]) }
                .map { String(decoding: $0, as: UTF8.self) } ?? "none"))
    }
}

let modernMeta: [String: Any] = [
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": [String: Any](),
    "io.modelcontextprotocol/clientInfo": ["name": "cards-mcp", "version": "1"],
]

var steps = rest[...]
while let step = steps.popFirst() {
    switch step {
    case let s where s.hasPrefix("initialize"):
        let version = s.hasPrefix("initialize=") ? String(s.dropFirst("initialize=".count)) : "2025-11-25"
        request("initialize", ["protocolVersion": version, "capabilities": [String: Any](),
                               "clientInfo": ["name": "cards-mcp", "version": "1"]])
        send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    case "discover": request("server/discover", ["_meta": modernMeta])
    case "list": request("tools/list", [:])
    case "ping": request("ping", [:])
    case "add":
        guard let title = steps.popFirst() else { print("cards-mcp: add needs a title"); exit(2) }
        var arguments: [String: Any] = ["title": title]
        if let file = steps.first, FileManager.default.fileExists(atPath: file) {
            steps.removeFirst()
            arguments["body"] = try! String(contentsOfFile: file, encoding: .utf8)
        }
        request("tools/call", ["name": "add_card", "arguments": arguments])
    case "add-bytes":
        guard let n = steps.popFirst().flatMap({ Int($0) }) else { print("cards-mcp: add-bytes needs a number"); exit(2) }
        request("tools/call", ["name": "add_card", "arguments": ["title": "Too long", "body": String(repeating: "x", count: n)]])
    default:
        print("cards-mcp: unknown step \(step)")
        exit(2)
    }
}

try? toHelper.fileHandleForWriting.close()
process.waitUntilExit()
print("helper exited with status \(process.terminationStatus) after its stdin closed")
