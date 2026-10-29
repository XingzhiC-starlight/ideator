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
                          scratch: String? = nil, board: NSPasteboard? = nil, maxContentHeight: CGFloat? = nil,
                          place: RunPlace? = nil) -> SettingsWindow {
        SettingsWindow(keys: KeyStore(inKeychain: false), hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                       updates: Updates(build: .current, isScratch: true), aiTools: choice,
                       connect: HelperCommand(app: app, scratchFolder: scratch.map { URL(filePath: $0, directoryHint: .isDirectory) },
                                              place: place),
                       pasteboard: board ?? privateBoard(), maxContentHeight: maxContentHeight) {}
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
                                                 + "at its next session. It holds up to 100 KB."))
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

    func testTheEditorTakesTextUpToTheLimitAndRefusesAChangeThatWouldPassItWithANote() throws {
        let choice = AIToolsChoice(preferences: Preferences(defaults: nil))
        choice.value.instruction.edit(to: String(repeating: "a", count: 99_996))
        let window = settings(choice)
        let editor = try editor(in: window)
        let refusal = "That change would pass the 100 KB limit, so Ideator did not make it."

        type("€", into: editor, in: window)
        XCTAssertEqual(editor.string.utf8.count, 99_999, "a € is 3 bytes")
        XCTAssertFalse(texts(in: window).contains(refusal))

        type("bc", into: editor, in: window)
        XCTAssertEqual(editor.string.utf8.count, 99_999, "two more bytes would pass the limit, so neither is typed")
        XCTAssertEqual(choice.value.instruction.text, editor.string)
        XCTAssertTrue(texts(in: window).contains(refusal))

        type("d", into: editor, in: window)
        XCTAssertEqual(editor.string.utf8.count, 100_000, "the limit itself is allowed")
        XCTAssertFalse(texts(in: window).contains(refusal), "the next change that is made takes the note away")

        type("e", into: editor, in: window)
        XCTAssertEqual(editor.string.utf8.count, 100_000)
        XCTAssertTrue(texts(in: window).contains(refusal))
    }

    func testReplacingTheWholeTextAtTheLimitWithALongerOneIsRefusedAndWithAShorterOneIsNot() throws {
        let choice = AIToolsChoice(preferences: Preferences(defaults: nil))
        choice.value.instruction.edit(to: String(repeating: "a", count: 100_000))
        let window = settings(choice)
        let editor = try editor(in: window)
        window.makeFirstResponder(editor)

        editor.selectAll(nil)
        editor.insertText(String(repeating: "b", count: 100_001), replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.string, String(repeating: "a", count: 100_000), "a paste past the limit changes nothing")

        editor.selectAll(nil)
        editor.insertText("Short.", replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.string, "Short.")
        XCTAssertEqual(choice.value.instruction.text, "Short.")
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

    func testAnAppRunFromADiskImageOffersNoCopyAndSaysToMoveItToApplicationsFirst() throws {
        let board = privateBoard()
        let window = settings(board: board, place: RunPlace(path: "/Volumes/Ideator/Ideator.app", onStartupVolume: false))
        let move = "Ideator is running from a disk image, another volume or a quarantined download, so a setup copied now "
            + "would point at a path that goes away. Move Ideator to Applications, open it from there, then copy a setup."

        for tool in AITool.allCases {
            let copy = try button(tool.name, in: window)
            XCTAssertFalse(copy.isEnabled, tool.name)
            copy.performClick(nil)
            XCTAssertEqual(copy.title, tool.name, "a click on a dimmed button does nothing")
        }
        XCTAssertNil(board.string(forType: .string), "nothing is copied")
        XCTAssertTrue(texts(in: window).contains(move))
        XCTAssertFalse(texts(in: window).contains("Each button copies a tool's setup, for you to paste. Ideator never edits another app's config files."))
    }

    func testAnAppRunFromATranslocatedCopyIsTreatedTheSame() throws {
        let window = settings(place: RunPlace(path: "/private/var/folders/zz/T/AppTranslocation/6E2F1C2A/d/Ideator.app", onStartupVolume: true))
        for tool in AITool.allCases { XCTAssertFalse(try button(tool.name, in: window).isEnabled, tool.name) }
    }

    func testAnAppInApplicationsKeepsItsCopyButtons() throws {
        let window = settings(place: RunPlace(path: "/Applications/Ideator.app", onStartupVolume: true))
        for tool in AITool.allCases { XCTAssertTrue(try button(tool.name, in: window).isEnabled, tool.name) }
    }

    func testAWindowTallerThanTheScreenScrollsFromItsTop() throws {
        let window = settings(maxContentHeight: 400)
        let scroll = try XCTUnwrap(window.contentView as? NSScrollView)
        let document = try XCTUnwrap(scroll.documentView)

        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, 400, "the window stops at the room the screen has")
        XCTAssertGreaterThan(document.frame.height, 400, "the rows keep their height and scroll")
        XCTAssertEqual(document.frame.width, 440)
        XCTAssertEqual(scroll.contentView.documentVisibleRect.minY, 0, "it opens at the Shortcut row, not at Privacy")
        XCTAssertTrue(views(in: window).contains { ($0 as? NSTextField)?.stringValue == "Shortcut" })
    }

    func testAWindowThatFitsTheScreenHasAllItsRowsAndNoRoomToScroll() throws {
        let window = settings(maxContentHeight: 5_000)
        let scroll = try XCTUnwrap(window.contentView as? NSScrollView)
        let document = try XCTUnwrap(scroll.documentView)

        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, document.frame.height)
        XCTAssertLessThan(document.frame.height, 5_000)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
