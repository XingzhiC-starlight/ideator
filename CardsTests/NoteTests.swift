import XCTest
@testable import Ideator

final class NoteTests: XCTestCase {
    func testBulletStartingLikeACheckboxStaysABullet() {
        for marker in ["[ ] ", "[x] ", "[X] "] {
            for level in 0..<Level.count {
                let note = Note(header: "Shopping", body: [
                    line(B(), "list"), line(B(1), "sub"),
                    Line(kind: .bullet, level: L(level), runs: [Run(text: marker + "milk")]),
                ])
                XCTAssertEqual(Note(markdown: note.markdown), note,
                               "a level-\(level) bullet whose text starts with \"\(marker)\" reads back as the same bullet")
            }
        }
    }

    func testEditorNoteRoundTripsExactly() {
        let note = Note(header: "Groceries *not* a style", body: [
            Line(runs: [Run(text: "milk "), Run(text: "now", style: .bold), Run(text: " and "),
                        Run(text: "later", style: [.bold, .italic])]),
            Line(kind: .bullet, runs: [Run(text: "eggs")]),
            Line(kind: .numbered, runs: [Run(text: "first")]),
            Line(kind: .numbered, runs: [Run(text: "second")]),
            Line(kind: .todo(done: true), runs: [Run(text: "done *literal* stars")]),
            Line(runs: [Run(text: "- not a bullet")]),
            Line(runs: [Run(text: "3. not numbered")]),
            Line(runs: [Run(text: "")]),
            Line(runs: [Run(text: "back\\slash")]),
        ])
        XCTAssertEqual(Note(markdown: note.markdown), note, "every line kind, style and literal marker survives a save and load")
    }

    func testNotesWithoutNestingKeepTheirFileBytes() {
        let note = Note(header: "Groceries", body: [
            Line(runs: [Run(text: "milk "), Run(text: "now", style: .bold)]),
            line(B(), "eggs"), line(N(), "first"), line(N(), "second"), line(D(done: true), "done"),
            line(T, "- not a bullet"), line(T, "# not a heading"), line(T, ""), line(N(), "again"),
        ])
        XCTAssertEqual(note.markdown, """
            # Groceries

            milk **now**
            - eggs
            1. first
            2. second
            - [x] done
            \\- not a bullet
            \\# not a heading

            1. again

            """, "a flat note writes what it wrote before levels, so its digest and cached summary survive")
    }

    func testBlankNoteRoundTrips() {
        XCTAssertEqual(Note(markdown: Note.blank.markdown), Note.blank, "a new card reads back as a new card")
    }

    func testSummaryIsWantedFromTwoParagraphsOn() {
        let one = Note(header: "h", body: [Line(runs: [Run(text: String(repeating: "word ", count: 200))])])
        let two = Note(header: "h", body: [Line(runs: [Run(text: "first")]), Line(runs: [Run(text: "second")])])
        XCTAssertFalse(one.wantsSummary, "one long paragraph is a one-line body")
        XCTAssertTrue(two.wantsSummary, "two paragraphs are enough")
    }

    // MARK: Levels

    func testLevelHasExactlyThreeValues() {
        XCTAssertEqual((-2...5).compactMap { Level($0) }.map(\.rawValue), [0, 1, 2], "only 0, 1 and 2 are levels")
        XCTAssertEqual(Level(clamping: 7).rawValue, 2, "a deeper request is repaired to the deepest level")
        XCTAssertEqual(Level(clamping: -3), .top)
        XCTAssertNil(L(2).deeper, "nothing is deeper than the third level")
        XCTAssertNil(Level.top.shallower)
    }

    func testPlainLineCannotHoldALevel() {
        XCTAssertEqual(LineShape(kind: .text, level: L(2)), .plain)
        XCTAssertEqual(Line(kind: .text, level: L(1), runs: []).level, .top)
        XCTAssertEqual(B(2).with(kind: .text), .plain, "turning an item plain drops its level")
    }

    func testNoteBodyIsTidyByConstruction() {
        let note = Note(header: "h", body: [line(B(2), "a"), line(B(2), "b"), line(T, "c"), line(N(1), "d")])
        XCTAssertEqual(note.body.map(\.shape), [B(0), B(1), T, N(0)], "a note can't hold a skipped level")
    }

    func testTidyLevelsFollowsTheSpec() {
        XCTAssertEqual(tidyLevels([B(1), B(2)]), [B(0), B(1)], "the first item sits at the top; its child just under it")
        XCTAssertEqual(tidyLevels([B(0), B(2)]), [B(0), B(1)], "a skipped level closes")
        XCTAssertEqual(tidyLevels([B(0), B(1), T, B(1)]), [B(0), B(1), T, B(0)], "an item right after a plain line is at the top")
        XCTAssertEqual(tidyLevels([N(0), D(1), B(2), N(1)]), [N(0), D(1), B(2), N(1)], "any kind nests under any kind")
        XCTAssertEqual(tidyLevels([B(0), B(2), B(2), B(1)]), [B(0), B(1), B(2), B(1)])
    }

    func testTidyLevelsOnEveryRunOfFiveLines() {
        for run in everyRun(upTo: 5) {
            let tidy = tidyLevels(run)
            XCTAssertEqual(tidyLevels(tidy), tidy, "idempotent: \(run)")
            XCTAssertEqual(tidy.map(\.kind), run.map(\.kind), "kinds untouched: \(run)")
            var above: LineShape?
            for (asked, got) in zip(run, tidy) {
                XCTAssertLessThanOrEqual(got.level, asked.level, "never deeper than asked: \(run)")
                if got.kind.isList {
                    let cap = above.map { $0.kind.isList ? $0.level.rawValue + 1 : 0 } ?? 0
                    XCTAssertLessThanOrEqual(got.level.rawValue, cap, "at most one below the item above: \(run)")
                }
                above = got
            }
        }
    }

    func testListNumbersCountPerParent() {
        XCTAssertEqual(listNumbers([N(), N(1), N(1), N(), B(), N()]), [1, 1, 2, 2, nil, 1],
                       "a nested run restarts at 1 and its parent's count continues")
        XCTAssertEqual(listNumbers([B(), N(1), N(1), B(), N(1)]), [nil, 1, 2, nil, 1], "a new parent restarts its children")
        XCTAssertEqual(listNumbers([N(), B(1), N(1), N()]), [1, nil, 1, 2], "a bullet ends its own level's run only")
        XCTAssertEqual(listNumbers([N(), T, N()]), [1, nil, 1], "a plain line ends every run")
        XCTAssertEqual(listNumbers([N(), N(1), N(2), N(2), N(1), N()]), [1, 1, 1, 2, 2, 2])
    }

    // MARK: Markdown with levels

    func testMarkdownWritesFourSpacesPerLevel() {
        let trip = Note(header: "Trip", body: [
            line(B(), "pack"), line(B(1), "socks"), line(N(1), "shirts"), line(N(1), "pants"),
            line(D(2, done: true), "wool"), line(B(), "book"),
        ])
        XCTAssertEqual(trip.markdown, """
            # Trip

            - pack
                - socks
                1. shirts
                2. pants
                    - [x] wool
            - book

            """)
        XCTAssertEqual(Note(markdown: trip.markdown), trip)
    }

    func testMarkdownReadsAnyIndentThatNests() {
        func levels(_ body: String) -> [Int] { Note(markdown: "# T\n\n" + body).body.map(\.level.rawValue) }
        XCTAssertEqual(levels("- a\n  - b\n    - c\n"), [0, 1, 2], "2-space indents")
        XCTAssertEqual(levels("- a\n\t- b\n\t\t- c\n"), [0, 1, 2], "a tab counts as 4 spaces")
        XCTAssertEqual(levels("- a\n        - b\n"), [0, 1], "an indent that skips a level is a child")
        XCTAssertEqual(levels("    - a\n- b\n"), [0, 0], "the first item is at the top whatever its indent")
        XCTAssertEqual(levels("- a\n    - b\n        - c\n            - d\n"), [0, 1, 2, 2], "past the third level clamps")
        XCTAssertEqual(levels("    - a\n  - b\n        - c\n    - d\n"), [0, 0, 1, 1], "a ragged indent nests under the item it passes")
        XCTAssertEqual(levels("text\n    - a\n"), [0, 0], "an item right after a plain line is at the top")
        XCTAssertEqual(Note(markdown: "# T\n\n- a\n  - b\n").markdown, "# T\n\n- a\n    - b\n",
                       "an old 2-space file is rewritten with 4-space indents on its next save")
    }

    func testIndentedPlainLinesStayPlain() {
        let read = Note(markdown: "# T\n\n- a\n  indented plain\n- b\n")
        XCTAssertEqual(read.body.map(\.kind), [.bullet, .text, .bullet])
        XCTAssertEqual(read.body[1].text, "  indented plain", "a plain line keeps its spaces")
        for text in ["  - x", "\t1. y", "   # z", "  > q", "- bare", "    [x] not", "\t* star"] {
            let note = Note(header: "h", body: [line(B(), "p"), line(T, text)])
            XCTAssertEqual(Note(markdown: note.markdown), note, "plain \(text.debugDescription) survives: \(note.markdown.debugDescription)")
        }
    }

    func testEveryTidyRunOfFourLinesRoundTrips() {
        for run in everyRun(upTo: 4) {
            let note = Note(header: "H", body: tidyLevels(run).enumerated().map { line($1, "x\($0)") })
            XCTAssertEqual(Note(markdown: note.markdown), note, "\(note.markdown.debugDescription)")
        }
    }

    func testSummaryTextIndentsTwoSpacesPerLevel() {
        let note = Note(header: "Trip", body: [line(B(), "pack"), line(N(1), "socks"), line(D(2, done: true), "wool"), line(T, "end")])
        XCTAssertEqual(note.plainText, "Trip\n- pack\n  - socks\n    [x] wool\nend")
    }
}
