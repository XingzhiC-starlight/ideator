import Foundation

/// Ideator only copies a setup for these tools: it never edits a tool's config.
nonisolated enum AITool: CaseIterable {
    case claudeCode, codex, claudeDesktop

    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .claudeDesktop: "Claude Desktop"
        }
    }

    var pasteNote: String {
        switch self {
        case .claudeCode: "Paste it into Terminal and press Return."
        case .codex: "Paste it at the end of ~/.codex/config.toml, then restart Codex."
        case .claudeDesktop: "In Claude Desktop, open Settings › Developer › Edit Config and paste it into the file. "
            + "If the file already has \"mcpServers\", add only the \"ideator\" entry to it. Then quit and reopen Claude Desktop."
        }
    }

    /// - Claude Code: `claude mcp add`, with `--scope user` so every project has it
    ///   (https://code.claude.com/docs/en/mcp);
    /// - Codex: a `[mcp_servers.<name>]` table for `~/.codex/config.toml` (https://developers.openai.com/codex/mcp);
    /// - Claude Desktop: the `mcpServers` object of `claude_desktop_config.json`
    ///   (https://modelcontextprotocol.io/docs/develop/connect-local-servers).
    func setup(for helper: HelperCommand) -> String {
        switch self {
        case .claudeCode:
            return "claude mcp add --transport stdio --scope user \(MCPServer.name) -- \(helper.shellLine)"
        case .codex:
            var lines = ["[mcp_servers.\(MCPServer.name)]", "command = \(Self.quoted(helper.executable.path))"]
            if !helper.arguments.isEmpty { lines.append("args = [\(helper.arguments.map(Self.quoted).joined(separator: ", "))]") }
            return lines.joined(separator: "\n")
        case .claudeDesktop:
            var entry = ["      \"command\": \(Self.quoted(helper.executable.path))"]
            if !helper.arguments.isEmpty { entry.append("      \"args\": [\(helper.arguments.map(Self.quoted).joined(separator: ", "))]") }
            return "{\n  \"mcpServers\": {\n    \"\(MCPServer.name)\": {\n\(entry.joined(separator: ",\n"))\n    }\n  }\n}"
        }
    }

    /// A JSON string, which is also a TOML basic string.
    private static func quoted(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

/// A scratch run's `-CardsFolder` argument keeps a pasted setup off the owner's notes.
nonisolated struct HelperCommand: Equatable {
    let executable: URL
    let arguments: [String]

    init(app: URL, scratchFolder: URL?) {
        executable = app.appending(path: "Contents/Helpers/ideator-mcp")
        arguments = scratchFolder.map { ["-CardsFolder", $0.standardizedFileURL.path] } ?? []
    }

    var isTemporary: Bool { false }

    var shellLine: String {
        ([executable.path] + arguments).map(Self.shellWord).joined(separator: " ")
    }

    private static func shellWord(_ word: String) -> String {
        let plain = !word.isEmpty && word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/._-+=:,@%".contains($0)) }
        return plain ? word : "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
