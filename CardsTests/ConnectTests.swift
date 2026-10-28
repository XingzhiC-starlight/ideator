import XCTest
@testable import Ideator

final class ConnectTests: XCTestCase {
    private let app = URL(filePath: "/Applications/Ideator.app", directoryHint: .isDirectory)
    private let helper = "/Applications/Ideator.app/Contents/Helpers/ideator-mcp"

    private func command(app: URL? = nil, scratch: String? = nil) -> HelperCommand {
        HelperCommand(app: app ?? self.app, scratchFolder: scratch.map { URL(filePath: $0, directoryHint: .isDirectory) })
    }

    func testTheHelperIsNamedByItsPlaceInsideTheAppItWasGiven() {
        XCTAssertEqual(command().executable.path, helper)
        let elsewhere = URL(filePath: "/Users/me/Desktop/my apps/Ideator.app", directoryHint: .isDirectory)
        XCTAssertEqual(command(app: elsewhere).executable.path, "/Users/me/Desktop/my apps/Ideator.app/Contents/Helpers/ideator-mcp")
        XCTAssertEqual(command().arguments, [])
        XCTAssertEqual(command(scratch: "/tmp/scratch").arguments, ["-CardsFolder", "/tmp/scratch"])
    }

    func testTheRunningAppsHelperIsOnDiskAndFindsThatAppFromItsPath() throws {
        let running = HelperCommand(app: Bundle.main.bundleURL, scratchFolder: nil)

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: running.executable.path), running.executable.path)
        XCTAssertEqual(HandOff.app(containing: running.executable)?.standardizedFileURL.path,
                       Bundle.main.bundleURL.standardizedFileURL.path, "the helper starts the app the path names")
    }

    func testTheShellReadsTheCopiedWordsBackAsTheyWere() throws {
        for (app, scratch) in [("/Applications/Ideator.app", nil), ("/Users/me/Desktop/my apps/Ideator.app", "/tmp/a b/c"),
                               ("/Users/o'neil/$HOME/`x`/Ideator.app", "/tmp/it's \"here\"")] as [(String, String?)] {
            let words = command(app: URL(filePath: app, directoryHint: .isDirectory), scratch: scratch)
            let shell = Process()
            shell.executableURL = URL(filePath: "/bin/zsh")
            shell.arguments = ["-c", "printf '%s\\n' \(words.shellLine)"]
            let output = Pipe()
            shell.standardOutput = output
            try shell.run()
            let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            shell.waitUntilExit()

            XCTAssertEqual(printed, ([words.executable.path] + words.arguments).map { $0 + "\n" }.joined(), "\(app)")
        }
    }

    func testClaudeCodeGetsAUserScopeStdioCommand() {
        XCTAssertEqual(AITool.claudeCode.setup(for: command()),
                       "claude mcp add --transport stdio --scope user ideator -- \(helper)")
    }

    func testClaudeCodeQuotesAPathWithSpacesAndAddsTheScratchFolder() {
        let elsewhere = URL(filePath: "/Users/me/Desktop/my apps/Ideator.app", directoryHint: .isDirectory)
        XCTAssertEqual(AITool.claudeCode.setup(for: command(app: elsewhere, scratch: "/tmp/scratch run")),
                       "claude mcp add --transport stdio --scope user ideator -- "
                       + "'/Users/me/Desktop/my apps/Ideator.app/Contents/Helpers/ideator-mcp' -CardsFolder '/tmp/scratch run'")
    }

    func testCodexGetsAConfigTomlTable() {
        XCTAssertEqual(AITool.codex.setup(for: command()), """
            [mcp_servers.ideator]
            command = "\(helper)"
            """)
    }

    func testCodexTableForAScratchRunHasItsFolderArgument() {
        XCTAssertEqual(AITool.codex.setup(for: command(scratch: "/tmp/scratch")), """
            [mcp_servers.ideator]
            command = "\(helper)"
            args = ["-CardsFolder", "/tmp/scratch"]
            """)
    }

    func testCodexEscapesWhatATomlStringEscapes() {
        let odd = URL(filePath: "/Users/a\"b\\c/Ideator.app", directoryHint: .isDirectory)
        XCTAssertTrue(AITool.codex.setup(for: command(app: odd)).contains(#"command = "/Users/a\"b\\c/Ideator.app/Contents/Helpers/ideator-mcp""#))
    }

    private func entry(_ text: String) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        XCTAssertEqual(Array(object.keys), ["mcpServers"])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: Any])
        XCTAssertEqual(Array(servers.keys), ["ideator"])
        return try XCTUnwrap(servers["ideator"] as? [String: Any])
    }

    func testClaudeDesktopGetsAnMcpServersEntryInJson() throws {
        let text = AITool.claudeDesktop.setup(for: command())
        let ideator = try entry(text)
        XCTAssertEqual(ideator["command"] as? String, helper)
        XCTAssertNil(ideator["args"])
        XCTAssertEqual(text, """
            {
              "mcpServers": {
                "ideator": {
                  "command": "\(helper)"
                }
              }
            }
            """)
    }

    func testClaudeDesktopEntryKeepsOddPathsAndTheScratchFolder() throws {
        let odd = URL(filePath: "/Users/a\"b\\c d/Ideator.app", directoryHint: .isDirectory)
        let ideator = try entry(AITool.claudeDesktop.setup(for: command(app: odd, scratch: "/tmp/it's here")))
        XCTAssertEqual(ideator["command"] as? String, "/Users/a\"b\\c d/Ideator.app/Contents/Helpers/ideator-mcp")
        XCTAssertEqual(ideator["args"] as? [String], ["-CardsFolder", "/tmp/it's here"])
    }

    func testOnlyAScratchRunsSetupsNameACardsFolder() {
        for tool in AITool.allCases {
            XCTAssertFalse(tool.setup(for: command()).contains("-CardsFolder"), "\(tool) for the owner's Ideator")
            let scratch = tool.setup(for: command(scratch: "/tmp/scratch"))
            XCTAssertTrue(scratch.contains("-CardsFolder"), "\(tool) for a scratch run")
            XCTAssertTrue(scratch.contains("/tmp/scratch"), "\(tool) for a scratch run")
            XCTAssertTrue(scratch.contains(helper), "\(tool) names the helper")
        }
    }

    func testEachToolHasANameAndANoteOnWhereToPasteIt() {
        XCTAssertEqual(AITool.allCases.map(\.name), ["Claude Code", "Codex", "Claude Desktop"])
        XCTAssertEqual(AITool.claudeCode.pasteNote, "Paste it into Terminal and press Return.")
        XCTAssertEqual(AITool.codex.pasteNote, "Paste it at the end of ~/.codex/config.toml, then restart Codex.")
        XCTAssertEqual(AITool.claudeDesktop.pasteNote, "In Claude Desktop, open Settings › Developer › Edit Config and paste it "
                       + "into the file. If the file already has \"mcpServers\", add only the \"ideator\" entry to it. Then quit "
                       + "and reopen Claude Desktop.")
    }
}
