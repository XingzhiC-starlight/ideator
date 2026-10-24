import XCTest
@testable import Ideator

final class ClipboardTests: XCTestCase {
    private func at(_ paragraph: Int, _ offset: Int) -> Clipboard.Position { .init(paragraph: paragraph, offset: offset) }
    private func span(_ start: Clipboard.Position, _ end: Clipboard.Position) -> Clipboard.Span { .init(start: start, end: end) }
    private func read(html: String? = nil, text: String? = nil) -> [Line] { Clipboard.lines(from: .init(html: html, text: text)) ?? [] }
    private func shapes(_ lines: [Line]) -> [LineShape] { lines.map(\.shape) }
    private func texts(_ lines: [Line]) -> [String] { lines.map(\.text) }

    /// Header "Title", then alpha (bullet), beta (level 1), gamma (numbered, level 2), delta (level 1), plain.
    private let sample = Note(header: "Title", body: [
        line(B(), "alpha"), line(B(1), "beta"), line(N(2), "gamma"), line(B(1), "delta"), line(T, "plain"),
    ])

    // MARK: Copy

    func testCopyInsideOneLineIsJustItsText() {
        let copy = Clipboard.copy(sample, span: span(at(2, 1), at(2, 3)))
        XCTAssertEqual(copy, Clipboard.Copy(markdown: "et", html: nil), "no marker and no HTML for part of one line")
        XCTAssertEqual(Clipboard.copy(sample, span: span(at(0, 0), at(0, 5)))?.markdown, "Title", "part of the header is its text")
        XCTAssertNil(Clipboard.copy(sample, span: span(at(2, 1), at(2, 1))), "an empty selection copies nothing")
    }

    func testCopyAcrossLinesTakesWholeLinesWithMarkers() {
        let copy = Clipboard.copy(sample, span: span(at(2, 2), at(3, 1)))
        XCTAssertEqual(copy?.markdown, "- beta\n    1. gamma", "levels count from the shallowest copied item")
        XCTAssertEqual(copy?.html, "<meta charset=\"utf-8\"><ul><li>beta<ol><li>gamma</li></ol></li></ul>")
        XCTAssertEqual(Clipboard.copy(sample, span: span(at(1, 0), at(2, 0)))?.markdown, "- alpha",
                       "a line the selection reaches only at its start is not copied")
        XCTAssertEqual(Clipboard.copy(sample, span: span(at(3, 3), at(4, 1)))?.markdown, "1. gamma\n- delta",
                       "the first copied item starts at the top, numbered from 1")
    }

    func testCopiedHeaderIsATitle() {
        let copy = Clipboard.copy(sample, span: span(at(0, 2), at(2, 1)))
        XCTAssertEqual(copy?.markdown, "# Title\n- alpha\n    - beta")
        XCTAssertEqual(copy?.html, "<meta charset=\"utf-8\"><h1>Title</h1><ul><li>alpha<ul><li>beta</li></ul></li></ul>")
    }

    func testCopiedHTMLKeepsKindsCheckboxesAndStyles() {
        let note = Note(header: "h", body: [
            line(B(), "a"), line(N(), "b"), line(D(done: true), "c"), line(N(1), "d"),
            Line(kind: .bullet, runs: [Run(text: "x "), Run(text: "y", style: [.bold, .italic]), Run(text: " <z> & w")]),
            line(T, "end"),
        ])
        let copy = Clipboard.copy(note, span: span(at(1, 0), at(6, 3)))
        XCTAssertEqual(copy?.markdown, "- a\n1. b\n- [x] c\n    1. d\n- x ***y*** <z> & w\nend")
        XCTAssertEqual(copy?.html, "<meta charset=\"utf-8\"><ul><li>a</li></ul><ol><li>b</li></ol>"
            + "<ul><li><input type=\"checkbox\" disabled checked> c<ol><li>d</li></ol></li>"
            + "<li>x <b><i>y</i></b> &lt;z&gt; &amp; w</li></ul><p>end</p>")
    }

    func testCopyThenPasteGivesBackTheSameLines() {
        let note = Note(header: "h", body: [
            line(N(), "one"), line(B(1), "two"), line(D(2, done: true), "three"), line(N(1), "four"),
            Line(kind: .bullet, runs: [Run(text: "five "), Run(text: "bold", style: .bold), Run(text: " *star*")]),
            line(T, "  plain - x"),
        ])
        let copy = Clipboard.copy(note, span: span(at(1, 0), at(6, 4)))!
        XCTAssertEqual(read(html: copy.html, text: copy.markdown), note.body, "HTML first")
        XCTAssertEqual(read(text: copy.markdown), note.body, "Markdown alone")
    }

    // MARK: Reading HTML

    func testHTMLFromCocoaApps() {
        // As AppKit writes a nested list (TextEdit, Notes): head and style, nested <ul> as a sibling item.
        let html = """
            <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
            <html>
            <head>
            <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
            <title></title>
            <meta name="Generator" content="Cocoa HTML Writer">
            <style type="text/css">
            li.li1 {margin: 0.0px 0.0px 0.0px 0.0px; font: 13.0px 'Helvetica Neue'}
            ul.ul1 {list-style-type: disc}
            </style>
            </head>
            <body>
            <p class="p1">Groceries</p>
            <ul class="ul1">
            <li class="li1">milk</li>
            <ul class="ul2">
            <li class="li1">oat</li>
            </ul>
            <li class="li1"><b>bread</b></li>
            </ul>
            <ol class="ol1">
            <li class="li1">first</li>
            <li class="li1">second</li>
            </ol>
            </body>
            </html>
            """
        let lines = read(html: html, text: "Groceries\n\t•\tmilk")
        XCTAssertEqual(texts(lines), ["Groceries", "milk", "oat", "bread", "first", "second"])
        XCTAssertEqual(shapes(lines), [T, B(), B(1), B(), N(), N()])
        XCTAssertEqual(lines[3].runs, [Run(text: "bread", style: .bold)])
    }

    func testHTMLFromGoogleDocs() {
        let span = "font-size:11pt;font-family:Arial,sans-serif;color:#000000;background-color:transparent;font-variant:normal;"
            + "text-decoration:none;vertical-align:baseline;white-space:pre;white-space:pre-wrap;"
        let item = "dir=\"ltr\" style=\"font-size:11pt;font-family:Arial,sans-serif;font-weight:400;white-space:pre;\""
        let html = "<meta charset=\"utf-8\"><b style=\"font-weight:normal;\" id=\"docs-internal-guid-6a1b2c3d-7fff-1234-abcd\">"
            + "<ul style=\"margin-top:0;margin-bottom:0;padding-inline-start:48px;\">"
            + "<li \(item) aria-level=\"1\"><p dir=\"ltr\" style=\"line-height:1.38;margin-top:0pt;\" role=\"presentation\">"
            + "<span style=\"\(span)font-weight:700;font-style:normal;\">Pack</span>"
            + "<span style=\"\(span)font-weight:400;font-style:normal;\">&nbsp;the bags</span></p></li>"
            + "<ul style=\"margin-top:0;margin-bottom:0;padding-inline-start:48px;\">"
            + "<li \(item) aria-level=\"2\"><p dir=\"ltr\" role=\"presentation\">"
            + "<span style=\"\(span)font-weight:400;font-style:italic;\">socks</span></p></li></ul>"
            + "<li \(item) aria-level=\"1\"><p dir=\"ltr\" role=\"presentation\">"
            + "<span style=\"\(span)font-weight:400;font-style:normal;\">Book</span></p></li></ul><br /></b>"
        let lines = read(html: html, text: "Pack the bags\nsocks\nBook")
        XCTAssertEqual(texts(lines), ["Pack the bags", "socks", "Book"])
        XCTAssertEqual(shapes(lines), [B(), B(1), B()])
        XCTAssertEqual(lines[0].runs, [Run(text: "Pack", style: .bold), Run(text: " the bags")], "the normal-weight wrapper adds no bold")
        XCTAssertEqual(lines[1].runs, [Run(text: "socks", style: .italic)])
    }

    func testHTMLFromTheClaudeApp() {
        let html = """
            <html><body><!--StartFragment--><p class="whitespace-normal break-words">Here's the plan:</p>
            <ol class="[&amp;:not(:last-child)_ul]:pb-1 list-decimal space-y-1.5 pl-7" depth="0">
            <li class="whitespace-normal break-words" index="0"><strong>Set up</strong> the repo
            <ul class="list-disc space-y-1.5 pl-7" depth="1">
            <li class="whitespace-normal break-words" index="0">clone it</li>
            <li class="whitespace-normal break-words" index="1">run <code class="bg-text-200/5 border">make</code></li>
            </ul>
            </li>
            <li class="whitespace-normal break-words" index="1">Ship <em>it</em></li>
            </ol><!--EndFragment--></body></html>
            """
        let lines = read(html: html, text: "Here's the plan:\n\n1. Set up the repo")
        XCTAssertEqual(texts(lines), ["Here's the plan:", "Set up the repo", "clone it", "run make", "Ship it"])
        XCTAssertEqual(shapes(lines), [T, N(), B(1), B(1), N()])
        XCTAssertEqual(lines[1].runs, [Run(text: "Set up", style: .bold), Run(text: " the repo")])
        XCTAssertEqual(lines[4].runs, [Run(text: "Ship "), Run(text: "it", style: .italic)])
    }

    func testHTMLFromAWebPage() {
        let html = "<meta charset=\"UTF-8\"><ul style=\"caret-color: rgb(0, 0, 0); font-family: -apple-system;\">"
            + "<li>Eggs</li><li>Milk<ul><li>whole</li><li>oat&nbsp;<em>barista</em></li></ul></li></ul>"
            + "<span style=\"font-family: -apple-system;\">Total:<span class=\"Apple-converted-space\">&nbsp;</span></span><b>2</b>"
        let lines = read(html: html, text: "Eggs\nMilk")
        XCTAssertEqual(texts(lines), ["Eggs", "Milk", "whole", "oat barista", "Total: 2"])
        XCTAssertEqual(shapes(lines), [B(), B(), B(1), B(1), T])
    }

    func testHTMLChecklistsFromGitHub() {
        let html = "<ul class=\"contains-task-list\"><li class=\"task-list-item\">\n"
            + "<input type=\"checkbox\" class=\"task-list-item-checkbox\" disabled checked> done</li>"
            + "<li class=\"task-list-item\"><input type=\"checkbox\" class=\"task-list-item-checkbox\" disabled> open</li></ul>"
        let lines = read(html: html)
        XCTAssertEqual(shapes(lines), [D(done: true), D()])
        XCTAssertEqual(texts(lines), ["done", "open"])
    }

    func testHTMLHeadingsLinksCodeAndTablesBecomePlainLines() {
        let html = "<h2>Notes</h2><ul><li>see <a href=\"https://x\">the doc</a></li></ul>"
            + "<table><tr><td>a</td><td>b</td></tr></table><p><img src=\"x.png\" alt=\"pic\">after image</p><pre>line 1\nline 2</pre>"
        let lines = read(html: html)
        XCTAssertEqual(texts(lines), ["Notes", "see the doc", "a", "b", "after image", "line 1", "line 2"])
        XCTAssertEqual(shapes(lines), [T, B(), T, T, T, T, T])
    }

    func testHTMLWithoutAListLeavesThePlainText() {
        XCTAssertEqual(texts(read(html: "<p>hi <b>there</b></p>", text: "hi there\nfriend")), ["hi there", "friend"])
        XCTAssertEqual(texts(read(html: "<p>only</p><p>html</p>")), ["only", "html"], "no text at all: the HTML's lines")
    }

    func testBrokenHTMLStillReads() {
        XCTAssertEqual(texts(read(html: "<ul><li>a<li>b<li>c")), ["a", "b", "c"], "unclosed items")
        XCTAssertEqual(shapes(read(html: "<ul><li>a<li>b<li>c")), [B(), B(), B()])
        XCTAssertEqual(texts(read(html: "<ul><li>a</li></ul></ul></li><li>z")), ["a", "z"], "stray closing tags")
        XCTAssertEqual(texts(read(html: "<ul><li>a < b &amp c &#x41;&#66;&bogus;</li></ul>")), ["a < b &amp c AB&bogus;"])
        XCTAssertEqual(texts(read(html: "<ul><li><ul><li>x</li><li>y<ul><li>z</li></ul></li></ul></li></ul>")), ["x", "y", "z"],
                       "a wrapper item around a nested list adds no line")
        XCTAssertEqual(texts(read(html: "<ul><li>a</li><li></li><li>b</li></ul>")), ["a", "", "b"], "an empty item stays")
        let deep = read(html: String(repeating: "<ul><li>", count: 5000) + "deep")
        XCTAssertEqual(shapes(deep), [B()], "5000 nested lists end, clamped and counted from the top")
        for fragment in ["<li", "<li <b", "<", "<!-- open", "<ul><li>x</b></i></span>"] {
            _ = read(html: fragment)
        }
    }

    // MARK: Reading text

    func testOneLineIsTypedTextVerbatim() {
        for text in ["- not a list", "**not bold**", "1) one", "C:\\Users\\me", "tail newline\n"] {
            let lines = read(text: text)
            XCTAssertEqual(shapes(lines), [T], text)
            XCTAssertEqual(texts(lines), [text.trimmingCharacters(in: .newlines)], text)
        }
    }

    func testTerminalOutputWithOtherBullets() {
        let text = """
            ⏺ Here's what changed:

              • Note.swift: levels
                ◦ tidyLevels
                  ▪ one scan
              · Clipboard.swift
              ‣ CardEditor.swift
              1) first
              2) second

            """
        let lines = read(text: text)
        XCTAssertEqual(texts(lines), ["⏺ Here's what changed:", "", "Note.swift: levels", "tidyLevels", "one scan",
                                      "Clipboard.swift", "CardEditor.swift", "first", "second"])
        XCTAssertEqual(shapes(lines), [T, T, B(), B(1), B(2), B(), B(), N(), N()])
    }

    func testMarkdownTextFromOtherApps() {
        let lines = read(text: "# Trip\n- pack\n  - socks\n- [x] book\n1.\ttabbed\n**Bold** line\n## 1. Not a list")
        XCTAssertEqual(texts(lines), ["Trip", "pack", "socks", "book", "tabbed", "Bold line", "1. Not a list"],
                       "a heading becomes its plain text")
        XCTAssertEqual(shapes(lines), [T, B(), B(1), D(done: true), N(), T, T])
        XCTAssertEqual(lines[5].runs, [Run(text: "Bold", style: .bold), Run(text: " line")])
    }

    func testPastedTextKeepsBackslashesMarkdownWouldKeep() {
        XCTAssertEqual(texts(read(text: "C:\\Users\\me\nprint(\"a\\nb\")\n\\*not italic\\*")),
                       ["C:\\Users\\me", "print(\"a\\nb\")", "*not italic*"])
        XCTAssertEqual(texts(read(text: "\\1. plain\nnext")), ["1. plain", "next"], "Cards' own escape of a numbered-looking line")
    }

    func testTabIndentedBullets() {
        let lines = read(text: "\t•\tmilk\n\t\t◦\toat\n\t•\tbread")
        XCTAssertEqual(texts(lines), ["milk", "oat", "bread"])
        XCTAssertEqual(shapes(lines), [B(), B(1), B()])
    }

    func testLevelsCountFromTheShallowestPastedItem() {
        XCTAssertEqual(shapes(read(text: "    - a\n        - b\n    - c")), [B(), B(1), B()])
        XCTAssertEqual(shapes(read(html: "<ul><li><ul><li>b</li><li>c<ul><li>d</li></ul></li></ul></li></ul>")), [B(), B(), B(1)])
    }

    // MARK: Paste

    private func paste(_ text: String, into note: Note, _ start: Clipboard.Position, _ end: Clipboard.Position? = nil,
                       typing: Style = []) -> Clipboard.Pasted {
        Clipboard.paste(read(text: text), into: note, replacing: span(start, end ?? start), typing: typing)
    }

    private let fruit = Note(header: "Fruit", body: [line(B(), "apple"), line(B(1), "kid"), line(T, ""), line(T, "tail")])

    func testOneLineIsTypedAtTheCaret() {
        let pasted = paste("- x", into: fruit, at(1, 2))
        XCTAssertEqual(texts(pasted.note.body).first, "ap- xple", "never starts a list")
        XCTAssertEqual(pasted.note.body[0].shape, B(), "the line keeps its kind")
        XCTAssertEqual(pasted.caret, at(1, 5))
        let bold = paste("bold", into: fruit, at(1, 5), typing: .bold)
        XCTAssertEqual(bold.note.body[0].runs, [Run(text: "apple"), Run(text: "bold", style: .bold)], "in the caret's style")
        let header = paste("ed", into: fruit, at(0, 5), typing: .bold)
        XCTAssertEqual(header.note.header, "Fruited")
    }

    func testOneLineReplacesASelectionAcrossLines() {
        let pasted = paste("Z", into: fruit, at(1, 1), at(2, 2))
        XCTAssertEqual(texts(pasted.note.body), ["aZd", "", "tail"])
        XCTAssertEqual(shapes(pasted.note.body), [B(), T, T])
    }

    func testSeveralLinesOnAnEmptyLineReplaceIt() {
        let pasted = paste("1. one\n2. two\n    - sub", into: fruit, at(3, 0))
        XCTAssertEqual(texts(pasted.note.body), ["apple", "kid", "one", "two", "sub", "tail"])
        XCTAssertEqual(shapes(pasted.note.body), [B(), B(1), N(), N(), B(1), T], "the first line brings its kind")
        XCTAssertEqual(pasted.caret, at(5, 3), "after the last pasted line")
    }

    func testSeveralLinesOnAnEmptyNestedItemShiftByItsLevel() {
        let note = Note(header: "Fruit", body: [line(B(), "apple"), line(B(1), "")])
        let pasted = paste("- red\n- green\n    - lime", into: note, at(2, 0))
        XCTAssertEqual(shapes(pasted.note.body), [B(), B(1), B(1), B(2)])
        XCTAssertEqual(texts(pasted.note.body), ["apple", "red", "green", "lime"])
    }

    func testSeveralLinesInsideTextJoinTheCurrentLine() {
        let pasted = paste("a\n- b\n- c", into: fruit, at(2, 1))
        XCTAssertEqual(texts(pasted.note.body), ["apple", "ka", "b", "cid", "", "tail"], "the text after the caret follows the last line")
        XCTAssertEqual(shapes(pasted.note.body), [B(), B(1), B(1), B(1), T, T], "later lines shift by the current item's level")
        XCTAssertEqual(pasted.caret, at(4, 1))
    }

    func testSeveralLinesIntoTheHeader() {
        let note = Note(header: "Hello World", body: [line(B(), "old")])
        let pasted = paste("A\n- b\n- c", into: note, at(0, 5))
        XCTAssertEqual(pasted.note.header, "HelloA")
        XCTAssertEqual(texts(pasted.note.body), ["b", "c World", "old"])
        XCTAssertEqual(shapes(pasted.note.body), [B(), B(), B()])
        let fresh = paste("# Trip\n- pack\n    - socks", into: .blank, at(0, 0))
        XCTAssertEqual(fresh.note.header, "Trip", "a pasted document's title becomes the header")
        XCTAssertEqual(shapes(fresh.note.body), [B(), B(1)])
    }

    func testPasteIsTidied() {
        let deep = Note(header: "h", body: [line(B(), "a"), line(B(1), "b"), line(B(2), "")])
        XCTAssertEqual(shapes(paste("- x\n    - y\n        - z", into: deep, at(3, 0)).note.body), [B(), B(1), B(2), B(2), B(2)],
                       "anything past level 3 is tidied up")
        let parent = Note(header: "h", body: [line(B(), "a"), line(B(1), "kid")])
        let split = paste("text\nmore", into: parent, at(1, 1))
        XCTAssertEqual(texts(split.note.body), ["atext", "more", "kid"])
        XCTAssertEqual(shapes(split.note.body), [B(), T, B()], "an item that lost its parent moves up")
    }

    func testHTMLPasteUnderAPlainLine() {
        let lines = read(html: "<ul><li>a<ul><li>b</li><li>c<ol><li>d</li></ol></li></ul></li><li>e</li></ul>")
        let pasted = Clipboard.paste(lines, into: Note(header: "h", body: [line(T, "")]), replacing: span(at(1, 0), at(1, 0)), typing: [])
        XCTAssertEqual(shapes(pasted.note.body), [B(), B(1), B(1), N(2), B()])
    }
}
