import XCTest
@testable import Ideator

/// The helper's MCP side, one JSON-RPC line in and at most one out, for a client of either era: a legacy
/// one opens with `initialize` (2025-11-25 and earlier), a modern one (2026-07-28) puts its protocol
/// version in every request's `_meta`.
final class MCPServerTests: XCTestCase {
    private var calls: [AddCard] = []
    private var answer = ToolReply.done("Added it.")
    private var instructions: String? = Instruction.standard

    private func server() -> MCPServer {
        MCPServer(version: "0.9", instructions: { [unowned self] in instructions }) { [unowned self] card in
            calls.append(card)
            return answer
        }
    }

    /// The reply to `message`, parsed, or nil when the server stays silent.
    private func respond(_ message: Any) throws -> [String: Any]? {
        let line = try JSONSerialization.data(withJSONObject: message)
        guard let reply = server().respond(to: line) else { return nil }
        XCTAssertFalse(reply.contains(UInt8(ascii: "\n")), "stdio messages must not contain a newline")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    }

    private func request(_ method: String, id: Any = 1, _ params: [String: Any]? = nil) -> [String: Any] {
        var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { message["params"] = params }
        return message
    }

    private let modernMeta: [String: Any] = [
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": [String: Any](),
        "io.modelcontextprotocol/clientInfo": ["name": "test", "version": "1"],
    ]

    private func result(_ reply: [String: Any]?) throws -> [String: Any] {
        try XCTUnwrap(reply?["result"] as? [String: Any], "\(String(describing: reply))")
    }

    private func error(_ reply: [String: Any]?) throws -> (code: Int, message: String, data: [String: Any]?) {
        let error = try XCTUnwrap(reply?["error"] as? [String: Any], "\(String(describing: reply))")
        return (try XCTUnwrap(error["code"] as? Int), try XCTUnwrap(error["message"] as? String), error["data"] as? [String: Any])
    }

    private func callAddCard(_ arguments: [String: Any], meta: [String: Any]? = nil) throws -> [String: Any] {
        var params: [String: Any] = ["name": "add_card", "arguments": arguments]
        if let meta { params["_meta"] = meta }
        return try result(respond(request("tools/call", id: 7, params)))
    }

    // MARK: Legacy clients

    func testInitializeAnswersWithTheClientsVersionTheServerNameAndTheInstructions() throws {
        let reply = try respond(request("initialize", ["protocolVersion": "2025-06-18", "capabilities": [:],
                                                       "clientInfo": ["name": "claude-code", "version": "2"]]))
        XCTAssertEqual(reply?["id"] as? Int, 1)
        XCTAssertEqual(reply?["jsonrpc"] as? String, "2.0")
        let result = try result(reply)
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18", "a version the server supports is echoed")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "ideator")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["version"] as? String, "0.9")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual(result["instructions"] as? String, Instruction.standard)
        XCTAssertNil(result["resultType"], "a legacy result has no resultType")
        XCTAssertTrue(calls.isEmpty, "a session start hands nothing to Ideator")
    }

    func testInitializeGivesTheEditedInstructionsAndNoneWhenThereAreNone() throws {
        instructions = "Only for to-dos."
        let edited = try result(respond(request("initialize", ["protocolVersion": "2025-06-18"])))
        XCTAssertEqual(edited["instructions"] as? String, "Only for to-dos.")

        instructions = nil
        let none = try result(respond(request("initialize", ["protocolVersion": "2025-06-18"])))
        XCTAssertNil(none["instructions"], "a blank instruction leaves the field out")
    }

    func testInitializeWithAnUnknownVersionAnswersTheLatestLegacyVersion() throws {
        for asked in ["2099-01-01", "2026-07-28", "garbage"] {
            let result = try result(respond(request("initialize", ["protocolVersion": asked, "capabilities": [:]])))
            XCTAssertEqual(result["protocolVersion"] as? String, "2025-11-25", asked)
        }
    }

    func testNotificationsGetNoReply() throws {
        XCTAssertNil(try respond(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        XCTAssertNil(try respond(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 7]]))
    }

    func testPingAnswersAnEmptyResult() throws {
        let reply = try respond(request("ping", id: "p-1"))
        XCTAssertEqual(reply?["id"] as? String, "p-1", "a string id comes back as it was sent")
        XCTAssertEqual(try result(reply).count, 0)
    }

    func testToolsListHasOneToolAddCardWithARequiredTitleAndAnOptionalBody() throws {
        let tools = try XCTUnwrap(try result(respond(request("tools/list")))["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.map { $0["name"] as? String }, ["add_card"])
        let schema = try XCTUnwrap(tools[0]["inputSchema"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["required"] as? [String], ["title"])
        let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        XCTAssertEqual(Set(properties.keys), ["title", "body"])
        XCTAssertEqual(properties["body"]?["type"] as? String, "string")
        let description = try XCTUnwrap(tools[0]["description"] as? String)
        XCTAssertTrue(description.contains("only when the user asks"), description)
    }

    func testAddCardHandsTheParsedCardOverAndAnswersWithIdeatorsReply() throws {
        answer = .done("Added \"Buy milk\" to the top of the stack.")
        let result = try callAddCard(["title": "Buy\nmilk", "body": "- eggs"])

        XCTAssertEqual(calls, [try AddCard.parse(["title": "Buy milk", "body": "- eggs"]).get()])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "Added \"Buy milk\" to the top of the stack.")
    }

    func testIdeatorsRefusalIsAToolError() throws {
        answer = .failed("Turned off in Ideator's Settings")
        let result = try callAddCard(["title": "Buy milk"])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual((result["content"] as? [[String: Any]])?.first?["text"] as? String, "Turned off in Ideator's Settings")
    }

    func testACardTheParserRefusesIsAToolErrorAndNeverReachesIdeator() throws {
        let over = String(repeating: "x", count: AddCard.byteLimit + 1)
        for arguments: [String: Any] in [["title": ""], ["title": "T", "body": over], [:]] {
            let result = try callAddCard(arguments)
            XCTAssertEqual(result["isError"] as? Bool, true)
            let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String
            XCTAssertTrue(text?.hasSuffix("Nothing was saved.") == true, String(describing: text))
        }
        XCTAssertTrue(calls.isEmpty)
    }

    func testAnUnknownToolIsAnInvalidParamsError() throws {
        let error = try error(respond(request("tools/call", ["name": "delete_card", "arguments": [:]])))
        XCTAssertEqual(error.code, -32602)
        XCTAssertEqual(error.message, "Unknown tool: delete_card")
    }

    func testAnUnknownMethodIsMethodNotFound() throws {
        XCTAssertEqual(try error(respond(request("resources/list"))).code, -32601)
    }

    func testALineThatIsNotJSONIsAParseErrorWithANullID() throws {
        let reply = try XCTUnwrap(server().respond(to: Data("{not json".utf8)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
        XCTAssertTrue(object["id"] is NSNull)
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    /// JSON-RPC 2.0: JSON that is not a request object is an Invalid Request, not a parse error.
    func testJSONThatIsNotAnObjectIsAnInvalidRequestWithANullID() throws {
        for line in ["null", "5", "\"ping\"", "[]"] {
            let reply = try XCTUnwrap(server().respond(to: Data(line.utf8)), line)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any], line)
            XCTAssertTrue(object["id"] is NSNull, line)
            XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? Int, -32600, line)
        }
    }

    /// MCP, unlike base JSON-RPC: a request ID must be a string or an integer, never null
    /// (https://modelcontextprotocol.io/specification/2026-07-28/basic/index.md, Requests).
    func testARequestWhoseIDIsNullOrNotAStringOrNumberIsAnInvalidRequest() throws {
        for id in [NSNull(), true, ["x": 1]] as [Any] {
            let reply = try respond(request("tools/list", id: id))
            XCTAssertEqual(try error(reply).code, -32600, "\(id)")
            XCTAssertTrue(reply?["id"] is NSNull, "\(id)")
        }
        XCTAssertTrue(calls.isEmpty)
    }

    func testARequestWhoseIDIsNotAnIntegerIsAnInvalidRequest() throws {
        for id in [1.5, -0.25] as [Double] {
            let reply = try respond(request("tools/list", id: id))
            XCTAssertEqual(try error(reply).code, -32600, "\(id)")
            XCTAssertTrue(reply?["id"] is NSNull, "\(id)")
        }
        XCTAssertEqual(try respond(request("ping", id: -3))?["id"] as? Int, -3)
    }

    // MARK: Modern clients (2026-07-28)

    /// https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching.md: a complete
    /// `server/discover` or `tools/list` result MUST carry `ttlMs` (>= 0) and `cacheScope`.
    func testDiscoverAndToolsListCarryCachingHints() throws {
        let discover = try result(respond(request("server/discover", ["_meta": modernMeta])))
        XCTAssertEqual(discover["ttlMs"] as? Int, 0, "the instructions are the user's to edit, so never fresh")
        XCTAssertEqual(discover["cacheScope"] as? String, "private")

        let list = try result(respond(request("tools/list", ["_meta": modernMeta])))
        XCTAssertEqual(list["ttlMs"] as? Int, 0, "an update can change the tool, and asking again costs nothing")
        XCTAssertEqual(list["cacheScope"] as? String, "public", "the same tool for every user")

        for other in [try result(respond(request("ping", ["_meta": modernMeta]))), try callAddCard(["title": "T"], meta: modernMeta)] {
            XCTAssertNil(other["ttlMs"])
            XCTAssertNil(other["cacheScope"])
        }
        let legacy = try result(respond(request("tools/list")))
        XCTAssertNil(legacy["ttlMs"], "a legacy result carries no caching hints")
    }

    func testDiscoverListsTheVersionsTheToolsCapabilityAndTheInstructions() throws {
        instructions = "Edited for discover."
        let result = try result(respond(request("server/discover", ["_meta": modernMeta])))
        XCTAssertEqual(result["resultType"] as? String, "complete")
        XCTAssertEqual(result["supportedVersions"] as? [String], ["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"])
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual(result["instructions"] as? String, "Edited for discover.")
        let serverInfo = (result["_meta"] as? [String: Any])?["io.modelcontextprotocol/serverInfo"] as? [String: Any]
        XCTAssertEqual(serverInfo?["name"] as? String, "ideator")
    }

    func testAModernRequestGetsResultTypeOnEveryResult() throws {
        let list = try result(respond(request("tools/list", ["_meta": modernMeta])))
        XCTAssertEqual(list["resultType"] as? String, "complete")
        XCTAssertEqual((list["tools"] as? [[String: Any]])?.count, 1)

        let call = try callAddCard(["title": "T"], meta: modernMeta)
        XCTAssertEqual(call["resultType"] as? String, "complete")
        XCTAssertEqual(call["isError"] as? Bool, false)
        XCTAssertEqual(calls.map(\.title), ["T"])
    }

    func testAModernRequestForAVersionTheServerLacksIsUnsupportedProtocolVersion() throws {
        var meta = modernMeta
        meta["io.modelcontextprotocol/protocolVersion"] = "2099-01-01"
        let error = try error(respond(request("tools/list", ["_meta": meta])))
        XCTAssertEqual(error.code, -32022)
        XCTAssertEqual(error.data?["requested"] as? String, "2099-01-01")
        XCTAssertEqual((error.data?["supported"] as? [String])?.first, "2026-07-28")
    }

    func testAModernRequestWithoutClientCapabilitiesIsInvalidParams() throws {
        var meta = modernMeta
        meta["io.modelcontextprotocol/clientCapabilities"] = nil
        XCTAssertEqual(try error(respond(request("tools/list", ["_meta": meta]))).code, -32602)
        XCTAssertTrue(calls.isEmpty)
    }
}
