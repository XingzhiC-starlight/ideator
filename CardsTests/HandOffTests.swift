import XCTest
@testable import Ideator

/// The hand-off from the helper to Ideator: which endpoint each side uses, and the two halves talking
/// over a real socket in a temporary folder.
final class HandOffTests: XCTestCase {
    private var directory: URL!
    private var inboxes: [ToolInbox] = []

    override func setUpWithError() throws {
        directory = URL(filePath: "/tmp", directoryHint: .isDirectory)
            .appending(path: "ideator-handoff-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for inbox in inboxes { inbox.close() }
        inboxes = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func endpoint(_ folder: String? = nil) -> Endpoint {
        Endpoint(scratchFolder: folder.map { URL(filePath: $0, directoryHint: .isDirectory) }, directory: directory)
    }

    private func card(_ title: String, body: String = "") throws -> AddCard {
        try AddCard.parse(["title": title, "body": body]).get()
    }

    @discardableResult
    private func open(_ endpoint: Endpoint,
                      receive: @escaping @MainActor (HandOffRequest, @escaping @Sendable (ToolReply) -> Void) -> Void) -> ToolInbox? {
        let inbox = ToolInbox(endpoint: endpoint, receive: receive)
        if let inbox { inboxes.append(inbox) }
        return inbox
    }

    /// The helper's side, off the main thread, as the helper's own process would be.
    private func send(_ card: AddCard, to endpoint: Endpoint, startup: Duration = .seconds(2),
                      launch: @escaping @Sendable () -> String? = { "not started" }) async -> ToolReply {
        let handOff = HandOff(endpoint: endpoint, launch: launch, startup: startup)
        return await Task.detached { handOff.send(card) }.value
    }

    // MARK: Endpoints

    func testANormalRunAndEachScratchFolderHaveEndpointsOfTheirOwn() {
        let normal = endpoint()
        let scratch = endpoint("/tmp/run-1/folder")
        XCTAssertNotEqual(normal, scratch, "a normal helper can never reach a scratch run")
        XCTAssertNotEqual(scratch, endpoint("/tmp/run-2/folder"), "a scratch helper reaches only its own folder's run")
        XCTAssertEqual(scratch, endpoint("/tmp/run-1/folder/"), "the same folder is the same endpoint")
        XCTAssertEqual(normal.path, directory.appending(path: "ideator-mcp.sock").path)
    }

    /// The app opens its folder by the path it was given, and the file system resolves it, so a helper
    /// with another spelling of the same folder must reach that run, not start a second one on it.
    func testTheSameFolderSpelledAnotherWayIsTheSameEndpoint() throws {
        let folder = directory.appending(path: "Notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(folder.path.hasPrefix("/tmp/"), folder.path)
        let given = endpoint(folder.path)

        XCTAssertEqual(endpoint("/private" + folder.path), given, "/tmp is a link to /private/tmp")
        XCTAssertEqual(endpoint(directory.path + "/NOTES"), given, "the file system ignores letter case")
        XCTAssertEqual(endpoint(directory.path + "/x/../Notes"), given)
        XCTAssertEqual(endpoint("/private" + folder.path + "/later"), endpoint(folder.path + "/later"),
                       "a folder not made yet: the part that exists is resolved")
        XCTAssertNotEqual(endpoint(directory.path + "/Other"), given)
    }

    func testTheEndpointFitsInASocketAddress() {
        let path = Endpoint(scratchFolder: URL(filePath: "/tmp/x"), directory: Endpoint.userTemporaryDirectory).path
        XCTAssertLessThan(path.utf8.count, 104, path)
        XCTAssertTrue(path.hasPrefix(Endpoint.userTemporaryDirectory.path), path)
    }

    func testTheHelperTakesNoArgumentsOrTheAppsCardsFolderArgument() throws {
        let cwd = URL(filePath: "/Users/someone/project", directoryHint: .isDirectory)
        XCTAssertNil(try HelperArguments([], currentDirectory: cwd).scratchFolder)
        XCTAssertEqual(try HelperArguments(["-CardsFolder", "/tmp/notes"], currentDirectory: cwd).scratchFolder?.path, "/tmp/notes")
        XCTAssertEqual(try HelperArguments(["-CardsFolder", "notes/../scratch"], currentDirectory: cwd).scratchFolder?.path,
                       "/Users/someone/project/scratch", "a relative folder is made absolute, so the app it starts gets the same one")
        XCTAssertThrowsError(try HelperArguments(["-CardsFolder"], currentDirectory: cwd))
        XCTAssertThrowsError(try HelperArguments(["--folder", "/tmp/notes"], currentDirectory: cwd))
    }

    func testTheHelperFindsTheAppThatContainsIt() {
        let helper = URL(filePath: "/Applications/Ideator.app/Contents/Helpers/ideator-mcp")
        XCTAssertEqual(HandOff.app(containing: helper)?.path, "/Applications/Ideator.app")
        XCTAssertNil(HandOff.app(containing: URL(filePath: "/usr/local/bin/ideator-mcp")), "a helper outside an app starts nothing")
        XCTAssertNil(HandOff.app(containing: URL(filePath: "/Applications/Other.app/Contents/MacOS/ideator-mcp")))
    }

    // MARK: Over the socket

    func testIdeatorReceivesTheCardAndItsReplyReachesTheHelper() async throws {
        let endpoint = endpoint("/tmp/folder")
        var received: [AddCard] = []
        XCTAssertNotNil(open(endpoint) { request, reply in
            received.append(request.card)
            reply(.done("Added \"\(request.card.title)\" to the top of the stack."))
        })

        let reply = await send(try card("Buy milk", body: "- eggs"), to: endpoint)

        XCTAssertEqual(reply, .done("Added \"Buy milk\" to the top of the stack."))
        XCTAssertEqual(received, [try card("Buy milk", body: "- eggs")])
    }

    func testTheReplyCanComeLater() async throws {
        let endpoint = endpoint()
        open(endpoint) { _, reply in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                reply(.done("later"))
            }
        }
        let reply = await send(try card("T"), to: endpoint)
        XCTAssertEqual(reply, .done("later"))
    }

    func testWhenNothingAnswersTheHelperLaunchesAndWaitsForTheEndpoint() async throws {
        let endpoint = endpoint("/tmp/not-running")
        let launches = Counter()
        let reply = await send(try card("T"), to: endpoint) {
            launches.add()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self.open(endpoint) { request, reply in reply(.done("started for \(request.card.title)")) }
            }
            return nil
        }
        XCTAssertEqual(reply, .done("started for T"))
        XCTAssertEqual(launches.value, 1)
    }

    /// The welcome wait counts from the call, so the time the launch took comes off what the app may
    /// still wait, and the AI tool hears back within the spec's 40 seconds.
    func testTheCardCarriesTheWaitForContinueLeftAfterTheLaunch() async throws {
        let path = endpoint("/tmp/slow-start").path
        let reply = await send(try card("T"), to: endpoint("/tmp/slow-start")) {
            Thread.sleep(forTimeInterval: 0.5)
            DispatchQueue.global().async {
                guard let listener = Socket.listen(at: path) else { return }
                defer {
                    close(listener)
                    unlink(path)
                }
                let fd = accept(listener, nil, nil)
                defer { close(fd) }
                var reader = LineReader(fd: fd, limit: 1 << 20)
                guard case .line(let line)? = reader.next(),
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
                Socket.write(line: ToolReply.done("\(object["waitMs"] ?? "none")").line, to: fd)
            }
            return nil
        }
        let waitMs = try XCTUnwrap(Int(reply.text), reply.text)
        XCTAssertLessThanOrEqual(waitMs, 39_500, "the half second the launch took is spent")
        XCTAssertGreaterThan(waitMs, 35_000)
    }

    func testALaunchThatFailsSaysWhyAndSavesNothing() async throws {
        let reply = await send(try card("T"), to: endpoint()) { "The application can't be opened." }
        XCTAssertTrue(reply.isError)
        XCTAssertTrue(reply.text.contains("The application can't be opened."), reply.text)
        XCTAssertTrue(reply.text.contains("Nothing was saved."), reply.text)
    }

    func testAnEndpointThatNeverOpensIsAnError() async throws {
        let reply = await send(try card("T"), to: endpoint(), startup: .milliseconds(300)) { nil }
        XCTAssertTrue(reply.isError)
        XCTAssertTrue(reply.text.contains("Nothing was saved."), reply.text)
    }

    func testIdeatorQuittingBeforeItRepliesIsAnError() async throws {
        let endpoint = endpoint()
        open(endpoint) { [unowned self] _, _ in
            for inbox in inboxes { inbox.close() }
        }
        let reply = await send(try card("T"), to: endpoint)
        XCTAssertEqual(reply, .lost)
    }

    func testASecondInstanceDoesNotTakeAnEndpointThatAnswers() throws {
        let endpoint = endpoint()
        XCTAssertNotNil(open(endpoint) { _, reply in reply(.done("first")) })
        XCTAssertNil(open(endpoint) { _, reply in reply(.done("second")) })
    }

    func testAnEndpointLeftBehindByAKilledInstanceIsTakenOver() async throws {
        let endpoint = endpoint()
        let killed = try XCTUnwrap(Socket.listen(at: endpoint.path))
        close(killed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: endpoint.path), "a killed instance leaves its socket file")

        XCTAssertNotNil(open(endpoint) { _, reply in reply(.done("second")) })
        let reply = await send(try card("T"), to: endpoint)
        XCTAssertEqual(reply, .done("second"))
    }

    func testAQuitInstanceRemovesItsEndpointButNotAnotherInstances() throws {
        let endpoint = endpoint()
        let quit = try XCTUnwrap(ToolInbox(endpoint: endpoint) { _, reply in reply(.done("quit")) })
        quit.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: endpoint.path))

        let older = try XCTUnwrap(ToolInbox(endpoint: endpoint) { _, reply in reply(.done("older")) })
        try FileManager.default.removeItem(atPath: endpoint.path)
        XCTAssertNotNil(open(endpoint) { _, reply in reply(.done("newer")) })
        older.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: endpoint.path), "a quitting instance leaves a newer one's endpoint alone")
    }

    func testTheEndpointIsOnlyThisUsers() throws {
        let endpoint = endpoint()
        open(endpoint) { _, reply in reply(.done("ok")) }
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: endpoint.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode & 0o077, 0, "no other user may connect")
    }

    func testIdeatorParsesWhatArrivesLikeAToolCall() async throws {
        let endpoint = endpoint()
        var received = 0
        open(endpoint) { _, reply in
            received += 1
            reply(.done("ok"))
        }
        let replies = await Task.detached { () -> [String] in
            ["{\"body\":\"x\"}\n", "not json\n"].map { line in
                guard let fd = Socket.connect(to: endpoint.path) else { return "no connection" }
                defer { close(fd) }
                _ = line.withCString { write(fd, $0, strlen($0)) }
                var reader = LineReader(fd: fd, limit: 1 << 20)
                guard case .line(let data)? = reader.next() else { return "no reply" }
                return ToolReply(line: data)?.text ?? "unreadable"
            }
        }.value
        XCTAssertEqual(replies[0], AddCard.Refusal.noTitle.reply.text)
        XCTAssertTrue(replies[1].hasSuffix("Nothing was saved."), replies[1])
        XCTAssertEqual(received, 0, "neither line reaches the desk")
    }
}

/// A count the helper's launch closure, which runs off the main thread, can bump.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}
