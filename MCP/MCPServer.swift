import Foundation

/// The helper's MCP server over stdio: one JSON-RPC 2.0 message in, at most one out, and no state
/// between messages. It serves both eras of the protocol
/// (https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning):
/// - legacy clients (2025-11-25 and earlier) open with `initialize`, then send plain requests;
/// - modern clients (2026-07-28) send `server/discover` or any request with their version and
///   capabilities in `_meta`, and every result says `resultType`.
/// A session start never starts Ideator: at most it asks a running one for the instruction, and only
/// `tools/call` hands a card over, through `addCard`.
nonisolated struct MCPServer {
    static let name = "ideator"
    static let modernVersions = ["2026-07-28"]
    /// Newest first: `initialize` with any other version is answered with the first.
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    let version: String
    /// Asked at each `initialize` and `server/discover`; nil leaves the field out.
    let instructions: () -> String?
    let addCard: (AddCard) -> ToolReply

    private enum Era {
        case legacy, modern
    }

    private struct Failure: Error {
        let code: Int
        let message: String
        var data: [String: Any]?
    }

    func respond(to line: Data) -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: line, options: .fragmentsAllowed) else {
            return encode(id: nil, failure: Failure(code: -32700, message: "Parse error"))
        }
        guard let request = message as? [String: Any] else {
            return encode(id: nil, failure: Failure(code: -32600, message: "Invalid request: send one JSON-RPC object per line"))
        }
        guard let method = request["method"] as? String, let id = request["id"] else {
            return nil   // a notification, or a response to a request this server never sends
        }
        // JSON's true and false also arrive as NSNumber.
        let integer = (id as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.rounded() == $0.doubleValue }
        guard id is String || integer == true else {
            return encode(id: nil, failure: Failure(code: -32600, message: "Invalid request: the id must be a string or an integer"))
        }
        let params = request["params"] as? [String: Any] ?? [:]
        do {
            let era = try era(of: method, params: params)
            var result = try result(of: method, params: params)
            if era == .modern {
                result["resultType"] = "complete"
                result["_meta"] = ["io.modelcontextprotocol/serverInfo": serverInfo]
                result.merge(Self.cachingHints[method] ?? [:]) { $1 }
            }
            return encode(["jsonrpc": "2.0", "id": id, "result": result])
        } catch let failure as Failure {
            return encode(id: id, failure: failure)
        } catch {
            return encode(id: id, failure: Failure(code: -32603, message: "Internal error"))
        }
    }

    /// `initialize` selects legacy semantics; a version in `_meta` selects modern ones, and must be one
    /// this server speaks, with the client's capabilities beside it.
    private func era(of method: String, params: [String: Any]) throws -> Era {
        guard method != "initialize", let meta = params["_meta"] as? [String: Any],
              let version = meta["io.modelcontextprotocol/protocolVersion"] as? String else { return .legacy }
        guard Self.modernVersions.contains(version) else {
            throw Failure(code: -32022, message: "Unsupported protocol version",
                          data: ["supported": Self.modernVersions + Self.legacyVersions, "requested": version])
        }
        guard meta["io.modelcontextprotocol/clientCapabilities"] is [String: Any] else {
            throw Failure(code: -32602, message: "Invalid params: _meta has no io.modelcontextprotocol/clientCapabilities")
        }
        return .modern
    }

    private func result(of method: String, params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return withInstructions(["protocolVersion": Self.legacyVersions.contains(asked) ? asked : Self.legacyVersions[0],
                                     "capabilities": ["tools": ["listChanged": false]],
                                     "serverInfo": serverInfo])
        case "server/discover":
            return withInstructions(["supportedVersions": Self.modernVersions + Self.legacyVersions,
                                     "capabilities": ["tools": [String: Any]()]])
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": [Self.addCardTool]]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard name == "add_card" else { throw Failure(code: -32602, message: "Unknown tool: \(name)") }
            let reply = switch AddCard.parse(params["arguments"] as? [String: Any] ?? [:]) {
            case .success(let card): addCard(card)
            case .failure(let refusal): refusal.reply
            }
            return ["content": [["type": "text", "text": reply.text]], "isError": reply.isError]
        default:
            throw Failure(code: -32601, message: "Method not found: \(method)")
        }
    }

    /// Complete results of these methods MUST carry both hints
    /// (https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching.md). Never fresh:
    /// Settings can change the instructions and an update the tool, and asking the helper again costs
    /// nothing. Only the instructions are the user's own.
    private static let cachingHints: [String: [String: Any]] = [
        "server/discover": ["ttlMs": 0, "cacheScope": "private"],
        "tools/list": ["ttlMs": 0, "cacheScope": "public"],
    ]

    private func withInstructions(_ result: [String: Any]) -> [String: Any] {
        var result = result
        if let text = instructions() { result["instructions"] = text }
        return result
    }

    private var serverInfo: [String: Any] { ["name": Self.name, "title": "Ideator", "version": version] }

    private static var addCardTool: [String: Any] {
        [
            "name": "add_card",
            "title": "Add a card to Ideator",
            "description": "Add one card to Ideator, the user's sticky-note app on their Mac. Use it only when the user "
                + "asks you to put something in Ideator; you may offer first. The title becomes the card's header. "
                + "The optional body is Markdown as Ideator reads it: \"- \" or \"* \" bullets, \"1. \" numbers, "
                + "\"- [ ] \" and \"- [x] \" checkboxes, 4 spaces of indent per level up to 3 levels, **bold** and "
                + "*italic*. Any other line stays a plain line with its text as written. The reply says where the "
                + "card went once Ideator has saved it.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "The card's header, one line."],
                    "body": ["type": "string", "description": "The card's text under the header, in the Markdown above."],
                ],
                "required": ["title"],
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false],
        ]
    }

    private func encode(id: Any?, failure: Failure) -> Data? {
        var error: [String: Any] = ["code": failure.code, "message": failure.message]
        if let data = failure.data { error["data"] = data }
        return encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": error])
    }

    /// One line: `JSONSerialization` escapes every newline inside a string.
    private func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
