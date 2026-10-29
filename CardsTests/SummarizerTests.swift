import XCTest
@testable import Ideator

/// The summarizer against a request the test answers by hand: which key each request carries,
/// and which answers are allowed to reach the desk.
final class SummarizerTests: XCTestCase {
    private let a = CardID(rawValue: "a")
    private let b = CardID(rawValue: "b")

    private func card(_ id: CardID, _ second: String = "two") -> Card {
        Card(id: id, note: Note(header: id.rawValue, body: ["one", second].map { Line(runs: [Run(text: $0)]) }))
    }

    /// Polls until `condition` holds or `timeout` passes; the assertions that follow say what was wrong.
    private func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Long enough for a request with no quiet period to have gone out.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    func testAKeyReplacedDuringTheQuietPeriodSendsTheRequestWithTheNewKey() async {
        let harness = Harness(key: "old")
        defer { harness.finish() }
        harness.sync([card(a)], typing: a)
        await settle()
        XCTAssertEqual(harness.requests.count, 0, "the typed card is still waiting out its quiet period")

        harness.key = "new"
        harness.sync([card(a)])
        await eventually { harness.requests.count == 1 }

        XCTAssertEqual(harness.requests.map(\.key), ["new"], "the request that goes out carries the key now saved")
        harness.answer(0, .text("fresh"))
        await eventually { !harness.delivered.isEmpty }
        XCTAssertEqual(harness.delivered, [Delivery(card: a, summary: Summary(source: card(a).digest, outcome: .text("fresh")))])
    }

    func testAKeyReplacedWhileARequestIsInFlightRestartsItAndKeepsTheOldAnswerOut() async {
        let harness = Harness(key: "old")
        defer { harness.finish() }
        harness.sync([card(a)])
        await eventually { harness.requests.count == 1 }
        XCTAssertEqual(harness.requests.map(\.key), ["old"])

        harness.key = "new"
        harness.sync([card(a)])
        await eventually { harness.requests.count == 2 }
        XCTAssertEqual(harness.requests.map(\.key), ["old", "new"], "the card asks again under the new key")

        harness.answer(0, .failed(reason: "HTTP 401: invalid x-api-key"))
        await settle()
        XCTAssertEqual(harness.delivered, [], "a failure under a key that is gone is not stored on the card")

        harness.answer(1, .text("fresh"))
        await eventually { !harness.delivered.isEmpty }
        XCTAssertEqual(harness.delivered, [Delivery(card: a, summary: Summary(source: card(a).digest, outcome: .text("fresh")))])
    }

    func testSyncingAgainWithTheSameKeyKeepsTheRequestInFlight() async {
        let harness = Harness(key: "key")
        defer { harness.finish() }
        harness.sync([card(a)])
        await eventually { harness.requests.count == 1 }

        harness.sync([card(a)])
        await settle()

        XCTAssertEqual(harness.requests.count, 1, "an unchanged key leaves the request alone")
    }

    func testRemovingTheKeyCancelsWaitingAndInFlightRequests() async {
        let harness = Harness(key: "key")
        defer { harness.finish() }
        harness.sync([card(a), card(b)], typing: a)
        await eventually { harness.requests.count == 1 }
        XCTAssertEqual(harness.requests.map(\.note.header), ["b"], "b is in flight, a is waiting")

        harness.key = nil
        harness.sync([card(a), card(b)])
        harness.answer(0, .text("late"))
        try? await Task.sleep(for: Summarizer.quietPeriod + .milliseconds(500))

        XCTAssertEqual(harness.requests.count, 1, "the waiting request never went out")
        XCTAssertEqual(harness.delivered, [], "and the answer to the one in flight was dropped")
    }

    func testAChangedNoteCancelsTheRequestForTheOldText() async {
        let harness = Harness(key: "key")
        defer { harness.finish() }
        harness.sync([card(a)])
        await eventually { harness.requests.count == 1 }

        let edited = card(a, "three")
        harness.sync([edited])
        await eventually { harness.requests.count == 2 }
        harness.answer(0, .text("about the old text"))
        harness.answer(1, .text("about the new text"))
        await eventually { !harness.delivered.isEmpty }
        await settle()

        XCTAssertEqual(harness.delivered, [Delivery(card: a, summary: Summary(source: edited.digest, outcome: .text("about the new text")))])
    }

    func testTheCardBeingTypedInWaitsOutTheQuietPeriodWhileOthersGoAtOnce() async {
        let harness = Harness(key: "key")
        defer { harness.finish() }
        let start = ContinuousClock.now
        harness.sync([card(a), card(b)], typing: a)
        await eventually { harness.requests.count == 1 }
        XCTAssertEqual(harness.requests.map(\.note.header), ["b"], "the other card does not wait")

        await eventually { harness.requests.count == 2 }

        XCTAssertEqual(harness.requests.map(\.note.header), ["b", "a"])
        XCTAssertGreaterThan(ContinuousClock.now - start, .seconds(2), "a's request went out only after the pause")
    }
}

private struct Delivery: Equatable {
    let card: CardID
    let summary: Summary
}

/// A `Summarizer` whose requests stop at `requests` until the test answers them.
private final class Harness {
    final class Request {
        let note: Note
        let key: String
        fileprivate var reply: CheckedContinuation<Summary.Outcome, Never>?
        init(note: Note, key: String) { (self.note, self.key) = (note, key) }
    }

    var key: String?
    private(set) var requests: [Request] = []
    private(set) var delivered: [Delivery] = []
    private var summarizer: Summarizer!

    init(key: String) {
        self.key = key
        summarizer = Summarizer(apiKey: { [unowned self] in self.key },
                                deliver: { [unowned self] in delivered.append(Delivery(card: $0, summary: $1)) },
                                summarize: { [unowned self] in await send($0, $1) })
    }

    func sync(_ cards: [Card], typing: CardID? = nil) {
        summarizer.sync(cards, typing: typing)
    }

    private func send(_ note: Note, _ key: String) async -> Summary.Outcome {
        let request = Request(note: note, key: key)
        requests.append(request)
        return await withCheckedContinuation { request.reply = $0 }
    }

    func answer(_ index: Int, _ outcome: Summary.Outcome) {
        guard requests.indices.contains(index) else { return XCTFail("request #\(index) never went out") }
        requests[index].reply?.resume(returning: outcome)
        requests[index].reply = nil
    }

    /// Cancels what is left and releases the requests nobody answered.
    func finish() {
        summarizer.sync([], typing: nil)
        for index in requests.indices where requests[index].reply != nil { answer(index, .failed(reason: "test over")) }
    }
}

/// Which company a key is for, decided by its start and nowhere else.
final class ProviderTests: XCTestCase {
    private let note = Note(markdown: "# Trip\n\nflights\nhotel\n")

    override func setUp() {
        URLProtocol.registerClass(StandInAPI.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StandInAPI.self)
        StandInAPI.replies = [:]
        StandInAPI.hosts = []
    }

    func testAKeyThatStartsWithSkAntDashIsAnthropicsAndAnyOtherKeyIsOpenAIs() {
        XCTAssertEqual(Provider(key: "sk-ant-api03-abc"), .anthropic)
        XCTAssertEqual(Provider(key: "sk-proj-abc"), .openAI)
        XCTAssertEqual(Provider(key: "sk-abc"), .openAI)
        XCTAssertEqual(Provider(key: "sk-ant"), .openAI, "the dash after ant belongs to the prefix")
        XCTAssertEqual(Provider(key: "pasted-from-another-service"), .openAI, "no third provider: it goes to OpenAI and fails there")
    }

    func testEachProviderIsNamedByItsCompany() {
        XCTAssertEqual(Provider.anthropic.name, "Anthropic")
        XCTAssertEqual(Provider.openAI.name, "OpenAI")
    }

    func testARequestGoesToTheCompanyOfTheKeyItCarries() async {
        StandInAPI.replies["api.anthropic.com"] = (200, #"{"content":[{"type":"text","text":"from anthropic"}],"stop_reason":"end_turn"}"#)
        StandInAPI.replies["api.openai.com"] = (200, #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"from openai"}]}]}"#)

        let anthropic = await Provider(key: "sk-ant-key").summarize(note, apiKey: "sk-ant-key")
        let openAI = await Provider(key: "sk-key").summarize(note, apiKey: "sk-key")

        XCTAssertEqual(anthropic, .text("from anthropic"))
        XCTAssertEqual(openAI, .text("from openai"))
        XCTAssertEqual(StandInAPI.hosts, ["api.anthropic.com", "api.openai.com"])
    }

    func testTheSummarizerSendsAnOpenAIShapedKeyToOpenAIAndKeepsTheAnswer() async {
        StandInAPI.replies["api.openai.com"] = (200, #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Trip list: flights."}]}]}"#)
        var delivered: [Summary] = []
        let card = Card(id: CardID(rawValue: "a"), note: note)
        let summarizer = Summarizer(apiKey: { "sk-proj-key" }, deliver: { delivered.append($1) })

        summarizer.sync([card], typing: nil)
        let deadline = ContinuousClock.now + .seconds(5)
        while delivered.isEmpty, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(delivered, [Summary(source: card.digest, outcome: .text("Trip list: flights."))])
        XCTAssertEqual(StandInAPI.hosts, ["api.openai.com"])
    }

    func testWithNoKeyACardSaysSoWithoutNamingACompany() {
        let card = Card(id: CardID(rawValue: "a"), note: note)

        XCTAssertEqual(Desk.summaryFace(of: card, hasKey: false), .unavailable(reason: "No API key. Add one in Settings."))
        XCTAssertEqual(Desk.summaryFace(of: card, hasKey: true), .loading)
    }
}

/// The OpenAI call: the request it builds and how it reads what comes back, from canned JSON.
final class OpenAITests: XCTestCase {
    private let note = Note(markdown: "# Trip\n\nflights\nhotel\n")

    private func outcome(_ body: String, status: Int = 200) -> Summary.Outcome {
        OpenAI.outcome(status: status, data: Data(body.utf8))
    }

    private func message(_ parts: String...) -> String {
        #"{"id":"msg_1","type":"message","status":"completed","role":"assistant","content":["# + parts.joined(separator: ",") + "]}"
    }

    private func text(_ value: String) -> String {
        #"{"type":"output_text","text":""# + value + #"","annotations":[],"logprobs":[]}"#
    }

    private func response(status: String = "completed", output: String...) -> String {
        #"{"id":"resp_1","object":"response","status":""# + status
            + #"","error":null,"incomplete_details":null,"output":["# + output.joined(separator: ",") + "]}"
    }

    func testTheRequestIsAResponsesCallWithTheKeyAsABearerToken() throws {
        let request = try OpenAI.request(for: note, apiKey: "sk-test")

        XCTAssertEqual(request.url, URL(string: "https://api.openai.com/v1/responses"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testTheBodyHoldsTheSharedPromptTheCardTextAndNothingElseUnvetted() throws {
        let request = try OpenAI.request(for: note, apiKey: "sk-test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])

        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(body["instructions"] as? String, Summary.instructions, "one prompt for both companies")
        XCTAssertEqual(body["input"] as? String, note.plainText)
        XCTAssertEqual(body["store"] as? Bool, false, "OpenAI keeps a stored response for 30 days; the app never reads one back")
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual(Set(body.keys), ["model", "instructions", "input", "max_output_tokens", "reasoning", "store"],
                       "no temperature or top_p: a reasoning model may refuse them")
        XCTAssertGreaterThanOrEqual(body["max_output_tokens"] as? Int ?? 0, 2048, "reasoning tokens count toward the cap")
    }

    func testTheSummaryIsTheOutputTextOfTheMessageAfterAReasoningItem() {
        let reply = response(output: #"{"id":"rs_1","type":"reasoning","summary":[]}"#,
                             message(text("  To-do list for the trip: hotel.\\n")))

        XCTAssertEqual(outcome(reply), .text("To-do list for the trip: hotel."))
    }

    func testTheTextIsFoundByItemAndPartTypeWhereverItSits() {
        let reply = response(output: message(#"{"type":"annotation_note","text":"not it"}"#, text("Plan for the move.")),
                             #"{"id":"rs_1","type":"reasoning","summary":[]}"#)

        XCTAssertEqual(outcome(reply), .text("Plan for the move."))
    }

    func testEveryOutputTextPartIsJoinedInOrder() {
        let reply = response(output: message(text("Plan for "), text("the move.")), message(text(" Two boxes.")))

        XCTAssertEqual(outcome(reply), .text("Plan for the move. Two boxes."))
    }

    func testARefusalPartMeansTheModelDeclined() {
        let reply = response(output: message(#"{"type":"refusal","refusal":"I can't help with that."}"#))

        XCTAssertEqual(outcome(reply), .failed(reason: "The model declined to summarize this card."))
    }

    func testAResponseCutOffByTheTokenCapIsAFailureNotAShortSummary() {
        let reply = response(status: "incomplete", output: #"{"id":"rs_1","type":"reasoning","summary":[]}"#)
            .replacingOccurrences(of: #""incomplete_details":null"#, with: #""incomplete_details":{"reason":"max_output_tokens"}"#)

        XCTAssertEqual(outcome(reply), .failed(reason: "The response was cut off (max_output_tokens)."))
    }

    func testAFailedResponseShowsItsErrorMessage() {
        let reply = response(status: "failed", output: "")
            .replacingOccurrences(of: #""error":null"#, with: #""error":{"code":"server_error","message":"stand-in: model overloaded"}"#)

        XCTAssertEqual(outcome(reply), .failed(reason: "stand-in: model overloaded"))
    }

    func testAnAnswerWithNoTextIsAFailure() {
        XCTAssertEqual(outcome(response(output: #"{"id":"rs_1","type":"reasoning","summary":[]}"#)),
                       .failed(reason: "The response had no text."))
        XCTAssertEqual(outcome(#"{"status":"completed"}"#), .failed(reason: "The response had no text."), "a reply with no output at all")
        XCTAssertEqual(outcome(response(output: message(text("   ")))), .failed(reason: "The response had no text."))
    }

    func testAnErrorStatusShowsTheStatusAndTheServersMessage() {
        let refused = outcome(#"{"error":{"message":"Incorrect API key provided: sk-fake.","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}"#, status: 401)
        XCTAssertEqual(refused, .failed(reason: "HTTP 401: Incorrect API key provided: sk-fake."))

        XCTAssertEqual(outcome("<html>Bad gateway</html>", status: 502), .failed(reason: "HTTP 502: request failed"), "a proxy's page has no JSON")
    }

    func testABodyThatIsNotAResponseIsAFailureWithAReason() {
        guard case .failed(let reason) = outcome("not json") else { return XCTFail("a summary from nothing") }
        XCTAssertFalse(reason.isEmpty)
    }

    func testAnErrorReplyReachesTheCardThroughTheWholeCall() async {
        URLProtocol.registerClass(StandInAPI.self)
        defer {
            URLProtocol.unregisterClass(StandInAPI.self)
            StandInAPI.replies = [:]
        }
        StandInAPI.replies["api.openai.com"] = (401, #"{"error":{"message":"stand-in: key refused","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}"#)

        let refused = await Provider.openAI.summarize(note, apiKey: "sk-fake")

        XCTAssertEqual(refused, .failed(reason: "HTTP 401: stand-in: key refused"))
    }
}

/// The Messages API call against a stand-in for api.anthropic.com, so a test reads the reason a
/// card would show under "Summary unavailable".
final class AnthropicTests: XCTestCase {
    private let note = Note(markdown: "# Trip\n\nflights\nhotel\n")

    override func setUp() {
        URLProtocol.registerClass(StandInAPI.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StandInAPI.self)
        StandInAPI.replies = [:]
    }

    func testAnErrorReplyShowsTheServersMessageEvenWithoutAnErrorType() async {
        StandInAPI.replies["api.anthropic.com"] = (401, #"{"type":"error","error":{"type":"authentication_error","message":"stand-in: key refused"}}"#)
        let refused = await Provider.anthropic.summarize(note, apiKey: "key")
        XCTAssertEqual(refused, .failed(reason: "HTTP 401: stand-in: key refused"))

        StandInAPI.replies["api.anthropic.com"] = (502, #"{"error":{"message":"stand-in: upstream timed out"}}"#)
        let proxied = await Provider.anthropic.summarize(note, apiKey: "key")
        XCTAssertEqual(proxied, .failed(reason: "HTTP 502: stand-in: upstream timed out"), "a proxy's error has no type")
    }

    func testTheRequestIsAMessagesCallWithTheKeyInTheXApiKeyHeader() throws {
        let request = try Anthropic.request(for: note, apiKey: "sk-ant-test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])

        XCTAssertEqual(request.url, URL(string: "https://api.anthropic.com/v1/messages"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(body["system"] as? String, Summary.instructions, "the same prompt as OpenAI's")
        XCTAssertEqual((body["messages"] as? [[String: String]])?.first, ["role": "user", "content": note.plainText])
    }

    func testTheSummaryIsTheTextBlocksNotTheThinkingBlocks() {
        let reply = #"{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":" Trip list: flights. "}],"stop_reason":"end_turn"}"#

        XCTAssertEqual(Anthropic.outcome(status: 200, data: Data(reply.utf8)), .text("Trip list: flights."))
    }

    func testARefusalStopReasonMeansTheModelDeclined() {
        let reply = #"{"content":[],"stop_reason":"refusal"}"#

        XCTAssertEqual(Anthropic.outcome(status: 200, data: Data(reply.utf8)), .failed(reason: "The model declined to summarize this card."))
    }
}

/// api.anthropic.com and api.openai.com, answered by the test and recorded by host.
private nonisolated final class StandInAPI: URLProtocol {
    nonisolated(unsafe) static var replies: [String: (status: Int, body: String)] = [:]
    nonisolated(unsafe) static var hosts: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        ["api.anthropic.com", "api.openai.com"].contains(request.url?.host() ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        Self.hosts.append(host)
        let (status, body) = Self.replies[host] ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
