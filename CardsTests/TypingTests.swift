import XCTest
@testable import Ideator

final class TypingTests: XCTestCase {
    func testTabNestsUnderTheItemAbove() {
        XCTAssertEqual(Typing.onTab([B(), B()], touching: 1..<2), .reshape([B(), B(1)]))
        XCTAssertEqual(Typing.onTab([N(), D(1), D(1)], touching: 2..<3), .reshape([N(), D(1), D(2)]), "nests under a sibling at any kind")
    }

    func testTabTypesATabWhereNothingCanNest() {
        XCTAssertEqual(Typing.onTab([B(), B()], touching: 0..<1), .system, "the first item of the body")
        XCTAssertEqual(Typing.onTab([T, B()], touching: 1..<2), .system, "the first item after a plain line")
        XCTAssertEqual(Typing.onTab([T], touching: 0..<1), .system, "a plain line")
        XCTAssertEqual(Typing.onTab([B()], touching: 0..<0), .system, "the header")
        XCTAssertEqual(Typing.onTab([T, T], touching: 0..<2), .system, "several plain lines")
    }

    func testTabIsRefusedWhenALevelWouldBeSkippedOrPassed() {
        XCTAssertEqual(Typing.onTab([B(), B(1)], touching: 1..<2), .nothing, "a first child has nothing to sit under")
        XCTAssertEqual(Typing.onTab([B(), B(1), B(2)], touching: 2..<3), .nothing, "already at the third level")
        XCTAssertEqual(Typing.onTab([B(), B(), B(1), B(2)], touching: 1..<2), .nothing, "a child would pass the third level")
        XCTAssertEqual(Typing.onTab([B(), B(), B()], touching: 0..<3), .nothing, "a selection holding a first item moves nothing")
    }

    func testTabCarriesChildren() {
        XCTAssertEqual(Typing.onTab([B(), B(), B(1)], touching: 1..<2), .reshape([B(), B(1), B(2)]))
        XCTAssertEqual(Typing.onTab([B(), B(1), B(1)], touching: 2..<3), .reshape([B(), B(1), B(2)]))
        XCTAssertEqual(Typing.onTab([B(), B(), B()], touching: 1..<3), .reshape([B(), B(1), B(1)]), "every selected item moves")
        XCTAssertEqual(Typing.onTab([B(), B(), T], touching: 1..<3), .reshape([B(), B(1), T]), "selected plain lines stay put")
    }

    func testShiftTabMovesUpCarryingChildren() {
        XCTAssertEqual(Typing.onBacktab([B(), B(1)], touching: 1..<2), .reshape([B(), B()]))
        XCTAssertEqual(Typing.onBacktab([B(), B(1), B(2)], touching: 1..<2), .reshape([B(), B(), B(1)]), "carries its child")
        XCTAssertEqual(Typing.onBacktab([B(), B(1), B(1)], touching: 1..<2), .reshape([B(), B(), B(1)]),
                       "the next sibling becomes its child")
        XCTAssertEqual(Typing.onBacktab([B(), B(1)], touching: 0..<1), .reshape([T, B()]),
                       "a top-level item becomes plain and its children rise")
        XCTAssertEqual(Typing.onBacktab([T], touching: 0..<1), .nothing, "plain text has nowhere to go")
        XCTAssertEqual(Typing.onBacktab([B()], touching: 0..<0), .nothing, "the header has nowhere to go")
    }

    func testTabThenShiftTabRestoresEveryRunOfFourLines() {
        for run in everyRun(upTo: 4) {
            let body = tidyLevels(run)
            for i in body.indices where body[i].kind.isList {
                if case .reshape(let nested) = Typing.onTab(body, touching: i..<(i + 1)) {
                    XCTAssertEqual(tidyLevels(nested), nested, "Tab keeps the body tidy: \(body) @\(i)")
                    XCTAssertEqual(Typing.onBacktab(nested, touching: i..<(i + 1)), .reshape(body), "Shift-Tab undoes Tab: \(body) @\(i)")
                }
                if case .reshape(let raised) = Typing.onBacktab(body, touching: i..<(i + 1)) {
                    XCTAssertEqual(tidyLevels(raised), raised, "Shift-Tab keeps the body tidy: \(body) @\(i)")
                }
            }
        }
    }

    func testReturnContinuesAtTheSameLevel() {
        XCTAssertEqual(Typing.onReturn([B(), B(1)], at: 1, isEmpty: false), .splitLine(B(1)))
        XCTAssertEqual(Typing.onReturn([D(1, done: true)], at: 0, isEmpty: false), .splitLine(D(1)), "a new checkbox starts unticked")
        XCTAssertEqual(Typing.onReturn([B()], at: nil, isEmpty: false), .splitLine(.plain), "the header")
        XCTAssertEqual(Typing.onReturn([T], at: 0, isEmpty: true), .splitLine(.plain), "a plain line")
    }

    func testReturnOnAnEmptyItemMovesItUp() {
        XCTAssertEqual(Typing.onReturn([B(), B(1)], at: 1, isEmpty: true), .reshape([B(), B()]))
        XCTAssertEqual(Typing.onReturn([B()], at: 0, isEmpty: true), .reshape([T]), "a top-level item ends the list, as before")
    }

    func testBackspaceAtTheStartOfAnItemMovesItUp() {
        XCTAssertEqual(Typing.onBackspaceAtStart([B(), B(1)], at: 1), .reshape([B(), B()]))
        XCTAssertEqual(Typing.onBackspaceAtStart([B()], at: 0), .reshape([T]), "a top-level item becomes plain, as before")
        XCTAssertEqual(Typing.onBackspaceAtStart([B(), T], at: 1), .system, "a plain line joins the line above")
    }

    func testChangingAKindChangesOnlyThatLine() {
        XCTAssertEqual(Typing.onToggleKind(.numbered, body: [B(), B(1), B(2)], touching: 1..<2), .reshape([B(), N(1), B(2)]))
        XCTAssertEqual(Typing.onToggleKind(.bullet, body: [T, T], touching: 1..<2), .reshape([T, B()]), "plain text becomes a top-level item")
        XCTAssertEqual(Typing.onToggleKind(.todo(done: false), body: [D(), D(1, done: true)], touching: 0..<2), .reshape([T, T]),
                       "all already checkboxes: back to plain")
        XCTAssertEqual(Typing.onToggleKind(.bullet, body: [B(), B(1)], touching: 0..<1), .reshape([T, B()]),
                       "a parent turned plain: its child moves up just enough")
        XCTAssertEqual(Typing.onToggleKind(.bullet, body: [B()], touching: 0..<0), .nothing, "the header")
    }
}
