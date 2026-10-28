import XCTest
@testable import Ideator

final class ConnectSettingsTests: XCTestCase {
    private var boards: [NSPasteboard] = []
    private let app = URL(filePath: "/Applications/Ideator.app", directoryHint: .isDirectory)

    override func tearDown() async throws {
        for board in boards { board.releaseGlobally() }
        boards = []
    }

    /// A pasteboard of the test's own: these tests never touch the general one, which holds the user's clipboard.
    private func privateBoard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("IdeatorTests-\(UUID().uuidString)"))
        boards.append(board)
        return board
    }

    private func settings(_ choice: AIToolsChoice = AIToolsChoice(preferences: Preferences(defaults: nil)),
                          scratch: String? = nil, board: NSPasteboard? = nil) -> SettingsWindow {
        SettingsWindow(keys: KeyStore(inKeychain: false), hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                       updates: Updates(build: .current, isScratch: true), aiTools: choice,
                       connect: HelperCommand(app: app, scratchFolder: scratch.map { URL(filePath: $0, directoryHint: .isDirectory) }),
                       pasteboard: board ?? privateBoard()) {}
    }

    private func views(in window: SettingsWindow) -> [NSView] { descendants(of: window.contentView!) }

    private func editor(in window: SettingsWindow) throws -> NSTextView {
        try XCTUnwrap(views(in: window).compactMap { $0 as? NSTextView }.first)
    }

    private func button(_ title: String, in window: SettingsWindow) throws -> NSButton {
        try XCTUnwrap(views(in: window).compactMap { $0 as? NSButton }.first { $0.title == title }, title)
    }

    private func texts(in window: SettingsWindow) -> [String] {
        views(in: window).compactMap { ($0 as? NSTextField)?.stringValue }
    }

    private func type(_ text: String, into editor: NSTextView, in window: SettingsWindow) {
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    func testTheInstructionAndTheConnectSectionComeAfterTheLandingRowAndBeforePrivacy() throws {
        let window = settings()
        let order = views(in: window).compactMap { view -> String? in
            if view is NSTextView { return "editor" }
            if let button = view as? NSButton { return button.title }
            if let field = view as? NSTextField, !field.isEditable { return field.stringValue }
            return nil
        }
        func index(_ label: String) throws -> Int { try XCTUnwrap(order.firstIndex(of: label), label) }
        let expected = ["Bottom", "Instruction for AI tools", "editor", "Reset to Default", "Connect AI tools", "Claude Code",
                        "Codex", "Claude Desktop", "Privacy"]
        let positions = try expected.map(index)
        XCTAssertEqual(positions, positions.sorted(), "\(expected) in this order")
        XCTAssertTrue(texts(in: window).contains("Ideator gives an AI tool this text when a session starts, so an edit reaches it "
                                                 + "at its next session."))
    }

    func testTheEditorShowsTheStandardTextAndResetStartsDimmed() throws {
        let window = settings()
        XCTAssertEqual(try editor(in: window).string, Instruction.standard)
        XCTAssertTrue(try editor(in: window).isEditable)
        XCTAssertFalse(try button("Reset to Default", in: window).isEnabled)
    }

    func testTypingChangesWhatAToolIsGivenAndResetToDefaultTakesItBack() throws {
        let choice = AIToolsChoice(preferences: Preferences(defaults: nil))
        let window = settings(choice)
        let editor = try editor(in: window)
        let reset = try button("Reset to Default", in: window)

        type(" Ask before saving.", into: editor, in: window)

        XCTAssertEqual(choice.value.instruction.text, Instruction.standard + " Ask before saving.")
        XCTAssertEqual(editor.string, Instruction.standard + " Ask before saving.", "typing leaves the editor as typed")
        XCTAssertTrue(reset.isEnabled)

        reset.performClick(nil)

        XCTAssertEqual(editor.string, Instruction.standard)
        XCTAssertEqual(choice.value.instruction, Instruction())
        XCTAssertFalse(reset.isEnabled)
    }

    func testAnEditSavedEarlierIsInTheEditorWhenTheWindowOpens() throws {
        let choice = AIToolsChoice(preferences: Preferences(defaults: nil))
        choice.value.instruction.edit(to: "Only to-dos.")
        let window = settings(choice)

        XCTAssertEqual(try editor(in: window).string, "Only to-dos.")
        XCTAssertTrue(try button("Reset to Default", in: window).isEnabled)
    }

    func testClearingTheEditorLeavesItBlankAndResetBringsTheStandardTextBack() throws {
        let choice = AIToolsChoice(preferences: Preferences(defaults: nil))
        let window = settings(choice)
        let editor = try editor(in: window)

        window.makeFirstResponder(editor)
        editor.selectAll(nil)
        editor.insertText("", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "")
        XCTAssertNil(choice.value.instruction.forSession, "a cleared editor sends no instruction")

        try button("Reset to Default", in: window).performClick(nil)
        XCTAssertEqual(editor.string, Instruction.standard)
    }

    func testEachConnectButtonCopiesItsToolsSetup() throws {
        let board = privateBoard()
        let window = settings(board: board)
        let command = HelperCommand(app: app, scratchFolder: nil)

        for tool in AITool.allCases {
            board.clearContents()
            try button(tool.name, in: window).performClick(nil)
            XCTAssertEqual(board.string(forType: .string), tool.setup(for: command), tool.name)
        }
    }

    func testAScratchWindowCopiesSetupsThatNameItsFolder() throws {
        let board = privateBoard()
        let window = settings(scratch: "/tmp/scratch-run", board: board)

        for tool in AITool.allCases {
            try button(tool.name, in: window).performClick(nil)
            let copied = try XCTUnwrap(board.string(forType: .string))
            XCTAssertTrue(copied.contains("-CardsFolder"), tool.name)
            XCTAssertTrue(copied.contains("/tmp/scratch-run"), tool.name)
        }
    }

    func testACopyIsAnsweredWithCopiedAndWhereToPasteIt() throws {
        let window = settings()
        let note = "Each button copies a tool's setup, for you to paste. Ideator never edits another app's config files."
        XCTAssertTrue(texts(in: window).contains(note))

        let codex = try button("Codex", in: window)
        codex.performClick(nil)

        XCTAssertEqual(codex.title, "Copied")
        XCTAssertTrue(texts(in: window).contains("Copied for Codex. \(AITool.codex.pasteNote)"))
        XCTAssertFalse(texts(in: window).contains(note))
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
