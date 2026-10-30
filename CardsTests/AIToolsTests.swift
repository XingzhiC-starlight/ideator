import XCTest
@testable import Ideator

/// Ideator's side of a card from an AI tool: the reply only after the save, the cards held while the
/// welcome card waits, the two Settings rows and where they are kept.
final class AIToolsTests: XCTestCase {
    private var folder: URL!
    private var windowsBefore: [NSWindow] = []
    private var controllers: [DeskController] = []
    private var alerts: [String] = []
    private let suites = TestDefaults()

    override func setUpWithError() throws {
        windowsBefore = NSApp.windows
        folder = FileManager.default.temporaryDirectory
            .appending(path: "CardsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for window in NSApp.windows where !windowsBefore.contains(window) {
            window.orderOut(nil)
            window.close()
        }
        controllers = []
        suites.removeAll()
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    /// Runs while an alert is up, inside the modal loop `present` stands in for.
    private var whileAlertIsUp: () -> Void = {}

    private func makeController() -> DeskController {
        let controller = DeskController(library: Library(folder: folder), keys: KeyStore(inKeychain: false), appMenu: { NSMenu() },
                                        present: { [self] alert in
                                            alerts.append(alert.messageText)
                                            whileAlertIsUp()
                                            return .alertFirstButtonReturn
                                        },
                                        pointer: { NSPoint(x: -10_000, y: -10_000) })
        controllers.append(controller)
        return controller
    }

    private func card(_ title: String, body: String = "") throws -> AddCard {
        try AddCard.parse(["title": title, "body": body]).get()
    }

    private func request(_ title: String, waiting wait: Duration) throws -> HandOffRequest {
        HandOffRequest(card: try card(title), wait: wait)
    }

    private func files() throws -> [String: String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }
        return try Dictionary(uniqueKeysWithValues: names.map { ($0, try String(contentsOf: folder.appending(path: $0), encoding: .utf8)) })
    }

    // MARK: Saving, then replying

    func testTheReplyComesAfterTheCardFileIsSaved() async throws {
        let controller = makeController()
        let reply = controller.add(try card("Buy milk", body: "- eggs\n- [ ] bread"), landing: .top)

        XCTAssertEqual(reply, .done("Added \"Buy milk\" to the top of the stack."))
        XCTAssertEqual(Array(try files().values), ["# Buy milk\n\n- eggs\n- [ ] bread\n"], "saved before the reply, with no wait for the debounce")
        XCTAssertEqual(controller.desk.stack.first?.note.header, "Buy milk")
    }

    func testBottomSaysBottom() async throws {
        let controller = makeController()
        XCTAssertEqual(controller.add(try card("Later"), landing: .bottom), .done("Added \"Later\" to the bottom of the stack."))
    }

    func testAFolderThatRefusesTheSaveIsAnErrorThatSaysNotToAddItAgain() async throws {
        let controller = makeController()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        let reply = controller.add(try card("Buy milk"), landing: .top)

        XCTAssertTrue(reply.isError)
        XCTAssertTrue(reply.text.contains("couldn't save"), reply.text)
        XCTAssertTrue(reply.text.contains("don't add it again"), reply.text)
        XCTAssertEqual(alerts, [], "the reply goes out before the alert, which waits for the user")

        let deadline = Date().addingTimeInterval(5)
        while alerts.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(alerts, ["Ideator can't save your notes"], "the usual alert says so on screen too")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertTrue(controller.flush())
        XCTAssertEqual(Array(try files().values), ["# Buy milk\n"], "saved once the folder lets it, and only once")
    }

    /// The alert is modal: while it is up, the main thread runs only a modal loop. A card that arrives
    /// then must still be saved and answered, not wait for the user to dismiss the alert.
    func testACardThatArrivesWhileTheSaveAlertIsUpIsAnswered() async throws {
        let controller = makeController()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        XCTAssertTrue(controller.add(try card("Refused"), landing: .top).isError)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)

        var second: ToolReply?
        var alertIsUp = false
        var answeredWhileUp = false
        let next = try card("Next")
        whileAlertIsUp = {
            alertIsUp = true
            Task { @MainActor in
                second = controller.add(next, landing: .top)
                answeredWhileUp = alertIsUp
            }
            let deadline = Date().addingTimeInterval(3)
            while second == nil, Date() < deadline { RunLoop.current.run(mode: .modalPanel, before: Date().addingTimeInterval(0.05)) }
            alertIsUp = false
        }

        let deadline = Date().addingTimeInterval(10)
        while alerts.isEmpty || second == nil || alertIsUp, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(alerts, ["Ideator can't save your notes"])
        XCTAssertTrue(answeredWhileUp, "the second card is answered while the alert is still up")
        XCTAssertEqual(second, .done("Added \"Next\" to the top of the stack."))
        XCTAssertEqual(Set(try files().values), ["# Refused\n", "# Next\n"], "both saved, each once")
    }

    func testTheRepliesSayWhatTheSpecSays() {
        XCTAssertEqual(ToolReply.added("T", to: .top), .done("Added \"T\" to the top of the stack."))
        XCTAssertEqual(ToolReply.added("T", to: .bottom), .done("Added \"T\" to the bottom of the stack."))
        XCTAssertEqual(ToolReply.turnedOff, .failed("Turned off in Ideator's Settings"))
    }

    // MARK: While the welcome card waits for Continue

    func testCardsHeldDuringTheWelcomeAreAnsweredInOrderOnContinue() async throws {
        let held = HeldCards()
        let replies = Replies()
        held.hold(try request("first", waiting: .seconds(30))) { replies.add($0) }
        held.hold(try request("second", waiting: .seconds(30))) { replies.add($0) }
        XCTAssertEqual(replies.all, [], "nothing is answered before Continue")

        held.release { .done("saved \($0.title)") }

        XCTAssertEqual(replies.all, [.done("saved first"), .done("saved second")])
        held.release { _ in .done("again") }
        XCTAssertEqual(replies.all.count, 2, "each card is answered once")
    }

    func testACardHeldPastItsWaitIsAnsweredPressContinueAndNeverSaved() async throws {
        let held = HeldCards()
        let replies = Replies()
        held.hold(try request("late", waiting: .milliseconds(100))) { replies.add($0) }

        let deadline = Date().addingTimeInterval(5)
        while replies.all.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }

        XCTAssertEqual(replies.all, [.waitingForContinue])
        XCTAssertTrue(ToolReply.waitingForContinue.isError)
        XCTAssertTrue(ToolReply.waitingForContinue.text.contains("press Continue in Ideator, then try again"),
                      "it says what to do: \(ToolReply.waitingForContinue.text)")
        var saved: [String] = []
        held.release { saved.append($0.title); return .done("saved") }
        XCTAssertEqual(saved, [], "Continue after the reply does not add the card the tool was told about")
    }

    func testAReleaseAfterTheWaitRanOutStillRefuses() async throws {
        let held = HeldCards()
        let replies = Replies()
        held.hold(try request("late", waiting: .zero)) { replies.add($0) }
        held.release { _ in .done("saved") }
        XCTAssertEqual(replies.all, [.waitingForContinue], "a Documents prompt that held the main thread past the deadline")
    }

    func testTheAppWaitsAtMostTheSpecsFortySecondsWhateverItIsSent() throws {
        let card = try card("T")
        let wait = { (object: [String: Any]) in try HandOffRequest.parse(object.merging(card.arguments) { $1 }).get().wait }
        XCTAssertEqual(try wait([:]), .seconds(40), "a line with no wait gets the longest")
        XCTAssertEqual(try wait(["waitMs": 12_345]), .milliseconds(12_345))
        XCTAssertEqual(try wait(["waitMs": 3_600_000]), .seconds(40))
        XCTAssertEqual(try wait(["waitMs": -5]), .zero)
        let line = try XCTUnwrap(HandOffRequest(card: card, wait: .milliseconds(1_500)).line)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertEqual(try HandOffRequest.parse(object).get(), HandOffRequest(card: card, wait: .milliseconds(1_500)))
    }

    // MARK: The settings and where they live

    func testTheFactorySettingsAreOnAndTop() {
        XCTAssertEqual(Preferences(defaults: nil).aiTools, AIToolSettings(enabled: true, landing: .top))
        XCTAssertEqual(Preferences(defaults: suites.make()).aiTools, AIToolSettings(enabled: true, landing: .top))
    }

    func testAnOrdinaryRunKeepsTheSettingsAcrossLaunches() {
        let owners = suites.make()
        AIToolsChoice(preferences: Preferences(defaults: owners)).value = AIToolSettings(enabled: false, landing: .bottom)
        XCTAssertEqual(AIToolsChoice(preferences: Preferences(defaults: owners)).value, AIToolSettings(enabled: false, landing: .bottom))
    }

    func testAScratchRunKeepsAChangeForTheRunAndWritesNothing() {
        let owners = suites.make()
        let launch = Launch(arguments: ["CardsFolder": "/tmp/scratch"], defaults: owners, build: BuildInfo(info: [:]), environment: [:])
        let choice = AIToolsChoice(preferences: launch.preferences(standard: owners))

        choice.value.landing = .bottom
        choice.value.enabled = false

        XCTAssertEqual(choice.value, AIToolSettings(enabled: false, landing: .bottom), "the change lasts for the run")
        XCTAssertEqual(owners.dictionaryRepresentation().keys.filter { $0.hasPrefix("AITools") }, [])
        XCTAssertEqual(AIToolsChoice(preferences: launch.preferences(standard: owners)).value, AIToolSettings(enabled: true, landing: .top))
    }

    func testTheHelperStartsIdeatorInTheBackground() {
        let background = Launch(arguments: [:], build: BuildInfo(info: [:]), environment: [HandOff.backgroundVariable: "1"])
        XCTAssertTrue(background.inBackground)
        XCTAssertFalse(Launch(arguments: [:], build: BuildInfo(info: [:]), environment: [:]).inBackground)
    }

    func testSettingsMCPPaneHasTheSwitchThenWhereCardsGo() throws {
        let choice = AIToolsChoice(preferences: Preferences(defaults: nil))
        let window = SettingsWindow(keys: KeyStore(inKeychain: false), hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                                    updates: Updates(build: .current, isScratch: true), aiTools: choice) {}
        let views = descendants(of: window.pane(.mcp))
        let labels = views.compactMap { view -> String? in
            if let button = view as? NSButton { return button.title }
            if let field = view as? NSTextField, !field.isEditable { return field.stringValue }
            return nil
        }
        func index(_ label: String) throws -> Int { try XCTUnwrap(labels.firstIndex(of: label), label) }
        XCTAssertLessThan(try index("Let AI tools add cards"), try index("Cards from AI tools go to:"))
        XCTAssertLessThan(try index("Cards from AI tools go to:"), try index("Top"))
        XCTAssertLessThan(try index("Top"), try index("Bottom"))

        let buttons = views.compactMap { $0 as? NSButton }
        let allow = try XCTUnwrap(buttons.first { $0.title == "Let AI tools add cards" })
        let top = try XCTUnwrap(buttons.first { $0.title == "Top" })
        let bottom = try XCTUnwrap(buttons.first { $0.title == "Bottom" })
        XCTAssertEqual(allow.state, .on)
        XCTAssertEqual(top.state, .on)

        bottom.performClick(nil)
        XCTAssertEqual(choice.value.landing, .bottom)
        XCTAssertEqual(top.state, .off)

        allow.performClick(nil)
        XCTAssertEqual(choice.value.enabled, false)
        XCTAssertFalse(top.isEnabled, "where cards go means nothing while AI tools may not add them")
        XCTAssertFalse(bottom.isEnabled)
    }

    /// Every view under `view` in reading order: each view, then what it holds.
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

/// Replies collected from closures that may run on any thread.
private final class Replies: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [ToolReply] = []
    var all: [ToolReply] { lock.withLock { replies } }
    func add(_ reply: ToolReply) { lock.withLock { replies.append(reply) } }
}
