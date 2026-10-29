import AppKit

// ideator-mcp: Ideator's MCP server for AI tools, run by the AI tool over stdio. It lives in
// Ideator.app/Contents/Helpers and hands every card to the running Ideator, which saves it.
// What it decides is in MCP/, which CardsTests tests; this file is only the process.

let arguments: HelperArguments
do {
    arguments = try HelperArguments(Array(CommandLine.arguments.dropFirst()),
                                    currentDirectory: URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory))
} catch {
    FileHandle.standardError.write(Data((HelperArguments.Usage.text + "\n").utf8))
    exit(64)
}

/// Starts the app this helper is inside, in the background. A scratch run gets an instance of its own:
/// Launch Services would otherwise hand the request to the owner's Ideator, which has the same bundle id.
nonisolated struct Launcher: Sendable {
    let app: URL?
    let scratchFolder: URL?

    func start() -> String? {
        guard let app else { return "this helper is not inside Ideator.app, so it can't start Ideator." }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = scratchFolder != nil
        if let scratchFolder { configuration.arguments = ["-CardsFolder", scratchFolder.path] }
        var environment = [HandOff.backgroundVariable: "1"]
        environment["CARDS_SHOW_WELCOME"] = ProcessInfo.processInfo.environment["CARDS_SHOW_WELCOME"]
        configuration.environment = environment
        let outcome = Outcome()
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            outcome.finish(error.map { $0.localizedDescription + "." })
        }
        return outcome.wait()
    }

    /// The answer to `openApplication`, which arrives on another queue.
    private nonisolated final class Outcome: @unchecked Sendable {
        private let done = DispatchSemaphore(value: 0)
        private var failure: String?

        func finish(_ failure: String?) {
            self.failure = failure
            done.signal()
        }

        func wait() -> String? {
            guard done.wait(timeout: .now() + 15) == .success else { return "macOS did not answer the request to open it." }
            return failure
        }
    }
}

let executable = (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])).resolvingSymlinksInPath()
let app = HandOff.app(containing: executable)
let version = app.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "0"
let launcher = Launcher(app: app, scratchFolder: arguments.scratchFolder)
let handOff = HandOff(endpoint: Endpoint(scratchFolder: arguments.scratchFolder), launch: { launcher.start() })
let server = MCPServer(version: version) { handOff.send($0) }

/// Several times the backstop, so a call past it is still read and answered as one.
var input = LineReader(fd: STDIN_FILENO, limit: 64 * AddCard.byteLimit)
while let next = input.next() {
    let reply: Data? = switch next {
    case .line(let line): server.respond(to: line)
    case .tooLong: Data(#"{"error":{"code":-32600,"message":"Invalid request: the message is too long"},"id":null,"jsonrpc":"2.0"}"#.utf8)
    }
    if let reply { Socket.write(line: reply, to: STDOUT_FILENO) }
}
