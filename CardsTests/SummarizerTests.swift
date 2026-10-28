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
