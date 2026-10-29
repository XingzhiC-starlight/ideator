import XCTest
@testable import Ideator

/// The `add_card` call as both boundaries read it: the helper from the AI tool, Ideator from the helper.
final class AddCardTests: XCTestCase {
    private func card(_ arguments: [String: Any]) throws -> AddCard {
        try AddCard.parse(arguments).get()
    }

    private func refusal(_ arguments: [String: Any]) -> AddCard.Refusal? {
        if case .failure(let refusal) = AddCard.parse(arguments) { refusal } else { nil }
    }

    func testATitleAloneIsACardWithAnEmptyBody() throws {
        let card = try card(["title": "Buy milk"])
        XCTAssertEqual(card.title, "Buy milk")
        XCTAssertEqual(card.body, "")
        XCTAssertEqual(card.note, Note(header: "Buy milk", body: []))
    }

    func testANullBodyIsNoBody() throws {
        XCTAssertEqual(try card(["title": "Buy milk", "body": NSNull()]).body, "")
    }

    func testTheTitleIsOneTrimmedLine() throws {
        XCTAssertEqual(try card(["title": "  Trip plan \n"]).title, "Trip plan")
        XCTAssertEqual(try card(["title": "Trip\nplan\r\nfor May\u{2028}2027"]).title, "Trip plan for May 2027",
                       "a header is one line, so each line break becomes a space")
    }

    func testAnEmptyOrBlankOrMissingTitleIsRefused() {
        XCTAssertEqual(refusal(["title": ""]), .noTitle)
        XCTAssertEqual(refusal(["title": " \n\t "]), .noTitle)
        XCTAssertEqual(refusal(["body": "- a"]), .noTitle)
        XCTAssertEqual(refusal(["title": 42]), .noTitle)
    }

    func testABodyThatIsNotTextIsRefused() {
        XCTAssertEqual(refusal(["title": "T", "body": ["- a"]]), .bodyNotText)
    }

    func testTheBackstopCountsTitleAndBodyTogetherInUTF8Bytes() throws {
        let title = "T"
        let fits = String(repeating: "a", count: AddCard.byteLimit - 1)
        XCTAssertNoThrow(try card(["title": title, "body": fits]), "exactly 1,000,000 bytes is not past the limit")
        XCTAssertEqual(refusal(["title": title, "body": fits + "a"]), .tooLong)
        let wide = String(repeating: "é", count: AddCard.byteLimit / 2)
        XCTAssertEqual(refusal(["title": title, "body": wide]), .tooLong, "é is two bytes")
    }

    func testEveryRefusalSaysNothingWasSavedAndIsAnError() {
        for refusal in [AddCard.Refusal.noTitle, .bodyNotText, .tooLong] {
            XCTAssertTrue(refusal.reply.isError)
            XCTAssertTrue(refusal.reply.text.hasSuffix("Nothing was saved."), refusal.reply.text)
        }
        XCTAssertTrue(AddCard.Refusal.tooLong.reply.text.contains("1 MB"))
    }

    func testTheBodyIsReadTheWayACardFileIsRead() throws {
        let body = """
            Plain line with **bold** and *italic*
            - bullet
                - nested bullet
                    - third level
            * star bullet
            1. first
            2. second
            - [ ] open
            - [x] done
            # Heading
            ```swift
            """
        let note = try card(["title": "Formats", "body": body + "\n"]).note

        XCTAssertEqual(note.header, "Formats")
        XCTAssertEqual(note.body.map(\.kind), [.text, .bullet, .bullet, .bullet, .bullet, .numbered, .numbered,
                                               .todo(done: false), .todo(done: true), .text, .text])
        XCTAssertEqual(note.body.map(\.level.rawValue), [0, 0, 1, 2, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(note.body[0].runs, [Run(text: "Plain line with "), Run(text: "bold", style: .bold),
                                           Run(text: " and "), Run(text: "italic", style: .italic)])
        XCTAssertEqual(note.body[9].text, "# Heading", "a heading becomes a plain line with its text as written")
        XCTAssertEqual(note.body[10].text, "```swift")
        XCTAssertEqual(Note(markdown: note.markdown), note, "the card file reads back to the same card")
    }

    func testTheArgumentsTheHelperSendsReadBackToTheSameCard() throws {
        let card = try card(["title": "A\nB", "body": "- x"])
        XCTAssertEqual(try AddCard.parse(card.arguments).get(), card)
    }
}
