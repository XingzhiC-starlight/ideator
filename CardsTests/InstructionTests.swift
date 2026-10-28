import XCTest
@testable import Ideator

final class InstructionTests: XCTestCase {
    private let suites = TestDefaults()
    private var directory: URL!
    private var inboxes: [ToolInbox] = []

    override func setUpWithError() throws {
        directory = URL(filePath: "/tmp", directoryHint: .isDirectory)
            .appending(path: "ideator-instruction-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for inbox in inboxes { inbox.close() }
        inboxes = []
        suites.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    private let standard = "Ideator keeps sticky-note cards on the user's Mac desktop, for ideas, to-dos and things to "
        + "remember later. A card has a title, then lines, bullets or checkboxes (up to 3 levels). Cards scroll, so "
        + "length is fine, but the first few lines are what the user sees at a glance: lead with what matters, and "
        + "keep one topic per card. Create a card only when the user asks; you may offer when something looks worth saving."

    func testTheStandardInstructionIsTheSpecsText() {
        XCTAssertEqual(Instruction.standard, standard)
        XCTAssertEqual(Instruction().text, standard)
        XCTAssertTrue(Instruction().isStandard)
    }

    func testAnEditIsWhatASessionGetsAndResetGoesBackToTheStandardText() {
        var instruction = Instruction()
        instruction.edit(to: "Only for to-dos.")

        XCTAssertEqual(instruction.text, "Only for to-dos.")
        XCTAssertEqual(instruction.forSession, "Only for to-dos.")
        XCTAssertFalse(instruction.isStandard)

        instruction.reset()
        XCTAssertEqual(instruction.text, standard)
        XCTAssertEqual(instruction.forSession, standard)
        XCTAssertTrue(instruction.isStandard)
    }

    func testTypingTheStandardTextBackIsNotAnEdit() {
        var instruction = Instruction()
        instruction.edit(to: "Something else")
        instruction.edit(to: standard)

        XCTAssertTrue(instruction.isStandard, "a later build's standard text then reaches this user")
        XCTAssertEqual(instruction, Instruction())
    }

    func testASessionGetsTheTextWithoutSpacesAtItsEndsAndNothingWhenItIsBlank() {
        var instruction = Instruction()
        instruction.edit(to: "  Keep it short.\n\n")
        XCTAssertEqual(instruction.forSession, "Keep it short.")
        XCTAssertEqual(instruction.text, "  Keep it short.\n\n", "the editor keeps what was typed")

        instruction.edit(to: " \n ")
        XCTAssertNil(instruction.forSession, "a blank instruction is no instruction, not the standard one")
        XCTAssertFalse(instruction.isStandard)
    }

    func testAnEditSurvivesALaunchAndResetForgetsIt() {
        let owners = suites.make()
        let choice = AIToolsChoice(preferences: Preferences(defaults: owners))
        XCTAssertEqual(choice.value.instruction, Instruction(), "nothing saved is the standard text")

        choice.value.instruction.edit(to: "Only for to-dos.")
        XCTAssertEqual(AIToolsChoice(preferences: Preferences(defaults: owners)).value.instruction.text, "Only for to-dos.")

        choice.value.instruction.reset()
        XCTAssertNil(owners.object(forKey: "AIToolsInstruction"), "no key left, so the next build's standard text applies")
        XCTAssertEqual(AIToolsChoice(preferences: Preferences(defaults: owners)).value.instruction, Instruction())
    }

    func testABlankEditIsKeptAsBlankNotAsTheStandardText() {
        let owners = suites.make()
        AIToolsChoice(preferences: Preferences(defaults: owners)).value.instruction.edit(to: "")
        let again = AIToolsChoice(preferences: Preferences(defaults: owners)).value.instruction
        XCTAssertEqual(again.text, "")
        XCTAssertNil(again.forSession)
    }

    func testAScratchRunKeepsAnEditForTheRunAndWritesNothing() {
        let owners = suites.make()
        let launch = Launch(arguments: ["CardsFolder": "/tmp/scratch"], defaults: owners, build: BuildInfo(info: [:]), environment: [:])
        let choice = AIToolsChoice(preferences: launch.preferences(standard: owners))

        choice.value.instruction.edit(to: "Scratch only.")

        XCTAssertEqual(choice.value.instruction.text, "Scratch only.", "the edit lasts for the run")
        XCTAssertEqual(owners.dictionaryRepresentation().keys.filter { $0.hasPrefix("AITools") }, [])
        XCTAssertEqual(AIToolsChoice(preferences: launch.preferences(standard: owners)).value.instruction, Instruction())
    }

    func testChangingAnotherSettingKeepsTheEdit() {
        let owners = suites.make()
        let choice = AIToolsChoice(preferences: Preferences(defaults: owners))
        choice.value.instruction.edit(to: "Kept.")
        choice.value.landing = .bottom
        choice.value.enabled = false

        let again = AIToolsChoice(preferences: Preferences(defaults: owners)).value
        XCTAssertEqual(again, AIToolSettings(enabled: false, landing: .bottom, instruction: Instruction(edited: "Kept.")))
    }

    private func endpoint(_ folder: String? = nil) -> Endpoint {
        Endpoint(scratchFolder: folder.map { URL(filePath: $0, directoryHint: .isDirectory) }, directory: directory)
    }

    private func source(scratch folder: String? = nil, appDomain: String? = nil,
                        patience: Duration = .seconds(2)) -> InstructionSource {
        InstructionSource(scratchFolder: folder.map { URL(filePath: $0, directoryHint: .isDirectory) }, appDomain: appDomain,
                          directory: directory, patience: patience)
    }

    @discardableResult
    private func open(_ endpoint: Endpoint, instruction: (@MainActor () -> String)?) -> ToolInbox? {
        let inbox = ToolInbox(endpoint: endpoint, instruction: instruction) { _, reply in reply(.done("a card")) }
        if let inbox { inboxes.append(inbox) }
        return inbox
    }

    /// The helper's side, off the main thread as the helper's own process is.
    private func ask(_ source: InstructionSource) async -> String? {
        await Task.detached { source.current() }.value
    }

    private func saved(_ text: String?) -> String {
        let owners = suites.make()
        var settings = AIToolSettings()
        if let text { settings.instruction.edit(to: text) }
        Preferences(defaults: owners).aiTools = settings
        return suites.names.last!
    }

    func testWithNothingRunningAndNothingSavedTheHelperGivesTheStandardText() async {
        let answer = await ask(source(appDomain: saved(nil)))
        XCTAssertEqual(answer, standard)
        let missing = await ask(source(appDomain: nil))
        XCTAssertEqual(missing, standard, "a helper outside an app has no preferences to read")
    }

    func testWithNothingRunningTheHelperGivesTheTextTheAppSavedAndStartsNothing() async throws {
        let answer = await ask(source(appDomain: saved("Saved while the app ran.")))

        XCTAssertEqual(answer, "Saved while the app ran.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [],
                       "no socket, no file: the helper only asked")
    }

    func testAScratchHelperNeverReadsSavedPreferences() async {
        let answer = await ask(source(scratch: "/tmp/scratch-folder", appDomain: saved("The owner's own edit.")))
        XCTAssertEqual(answer, standard, "a scratch run has no preferences, so its helper shows the standard text")
    }

    func testARunningIdeatorGivesItsInstructionAndItWinsOverWhatIsSaved() async {
        open(endpoint(), instruction: { "Edited, now." })

        let answer = await ask(source(appDomain: saved("Saved earlier.")))

        XCTAssertEqual(answer, "Edited, now.")
    }

    func testAScratchRunsEditReachesTheHelperOnItsFolderOnly() async {
        open(endpoint("/tmp/folder-a"), instruction: { "Edited in the run on A." })

        let sameFolder = await ask(source(scratch: "/tmp/folder-a"))
        let otherFolder = await ask(source(scratch: "/tmp/folder-b"))
        let normalHelper = await ask(source())

        XCTAssertEqual(sameFolder, "Edited in the run on A.")
        XCTAssertEqual(otherFolder, standard)
        XCTAssertEqual(normalHelper, standard, "a normal helper never reaches a scratch run")
    }

    func testTheEditOfARunThatQuitIsGoneForAScratchHelper() async {
        let inbox = open(endpoint("/tmp/folder-a"), instruction: { "Edited in the run." })
        inbox?.close()

        let answer = await ask(source(scratch: "/tmp/folder-a"))
        XCTAssertEqual(answer, standard, "an edit in a scratch run lasts for the run")
    }

    func testABlankInstructionGivesTheSessionNoInstructions() async {
        open(endpoint(), instruction: { "" })
        let answer = await ask(source(appDomain: saved("Saved earlier.")))
        XCTAssertNil(answer)
    }

    func testAnIdeatorThatDoesNotAnswerInTimeLeavesTheSavedText() async throws {
        let silent = endpoint()
        let listener = try XCTUnwrap(Socket.listen(at: silent.path))
        defer { close(listener) }
        let started = ContinuousClock.now

        let answer = await ask(source(appDomain: saved("Saved earlier."), patience: .milliseconds(300)))

        XCTAssertEqual(answer, "Saved earlier.")
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3), "a session start never waits long for a busy Ideator")
    }

    func testAnOlderIdeatorThatRefusesTheAskLeavesTheSavedText() async {
        open(endpoint(), instruction: nil)
        let answer = await ask(source(appDomain: saved("Saved earlier.")))
        XCTAssertEqual(answer, "Saved earlier.")
    }

    func testTheHelpersInitializeCarriesTheInstructionAndHandsNothingToIdeator() async throws {
        open(endpoint("/tmp/folder-a"), instruction: { "Edited in the run on A." })
        let instructions = source(scratch: "/tmp/folder-a")
        let line = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                                               "params": ["protocolVersion": "2025-06-18"]])

        let reply = await Task.detached { () -> [String: Any]? in
            let server = MCPServer(version: "0.9", instructions: { instructions.current() }) { _ in .done("card") }
            return server.respond(to: line).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }.value

        let result = try XCTUnwrap(reply?["result"] as? [String: Any])
        XCTAssertEqual(result["instructions"] as? String, "Edited in the run on A.")
    }
}
