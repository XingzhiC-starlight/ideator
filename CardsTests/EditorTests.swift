import AppKit
import XCTest
@testable import Ideator

/// The real text view in a window that is never shown, driven through the calls the keyboard,
/// the Edit menu and the pasteboard make. Each `key` is one event, so one undo group, as in the app.
final class EditorTests: XCTestCase {
    private struct Card {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        let editor = CardTextView()
        var undo: UndoManager { window.undoManager! }

        init(_ note: Note) {
            editor.frame = window.contentLayoutRect
            window.contentView = editor
            window.makeFirstResponder(editor)
            undo.groupsByEvent = false
            editor.show(note)
        }

        func caret(before text: String, offset: Int = 0) {
            let location = (editor.string as NSString).range(of: text).location
            editor.setSelectedRange(NSRange(location: location + offset, length: 0))
        }

        func select(from start: String, through end: String) {
            let string = editor.string as NSString
            let from = string.range(of: start).location
            editor.setSelectedRange(NSRange(location: from, length: NSMaxRange(string.range(of: end)) - from))
        }

        func key(_ press: (CardTextView) -> Void) {
            undo.beginUndoGrouping()
            press(editor)
            undo.endUndoGrouping()
        }

        var shapes: [LineShape] { editor.note.body.map(\.shape) }
        var texts: [String] { editor.note.body.map(\.text) }
    }

    private func pasteboard() -> NSPasteboard { NSPasteboard(name: NSPasteboard.Name("cards-tests-\(UUID().uuidString)")) }

    func testTabNestsAndShiftTabCarriesChildren() {
        let card = Card(Note(header: "h", body: [line(B(), "a"), line(B(), "b"), line(B(1), "c")]))
        card.caret(before: "b")
        card.key { $0.insertTab(nil) }
        XCTAssertEqual(card.shapes, [B(), B(1), B(2)], "b nests under a and carries c")
        XCTAssertEqual(card.texts, ["a", "b", "c"], "no tab character typed")
        card.key { $0.insertBacktab(nil) }
        XCTAssertEqual(card.shapes, [B(), B(), B(1)])
        card.caret(before: "a")
        card.key { $0.insertBacktab(nil) }
        XCTAssertEqual(card.shapes, [T, B(), B(1)], "a top-level item becomes plain text")
    }

    func testTabWhereNothingCanNest() {
        let card = Card(Note(header: "h", body: [line(T, "x"), line(B(), "first"), line(B(1), "child")]))
        card.caret(before: "child")
        card.key { $0.insertTab(nil) }
        XCTAssertEqual(card.shapes, [T, B(), B(1)], "a first child has nothing to sit under")
        XCTAssertEqual(card.texts, ["x", "first", "child"])
        card.caret(before: "x")
        card.key { $0.insertTab(nil) }
        XCTAssertEqual(card.texts.first, "\tx", "a plain line types a tab")
        card.caret(before: "first")
        card.key { $0.insertTab(nil) }
        XCTAssertEqual(card.texts[1], "\tfirst", "the first item of a list types a tab")
        card.caret(before: "h")
        card.key { $0.insertBacktab(nil) }
        XCTAssertEqual(card.editor.note.header, "h", "Shift-Tab in the header does nothing")
    }

    func testUndoAfterTabIsOneStep() {
        let card = Card(Note(header: "h", body: [line(B(), "a"), line(B(), "b"), line(B(1), "c")]))
        card.caret(before: "b")
        card.key { $0.insertTab(nil) }
        card.undo.undo()
        XCTAssertEqual(card.shapes, [B(), B(), B(1)])
        card.undo.redo()
        XCTAssertEqual(card.shapes, [B(), B(1), B(2)])
    }

    func testEnterAndBackspaceMoveAnEmptyNestedItemUp() {
        let card = Card(Note(header: "h", body: [line(B(), "a")]))
        card.caret(before: "a", offset: 1)
        card.key { $0.insertNewline(nil) }
        XCTAssertEqual(card.shapes, [B(), B()], "Enter continues the list")
        card.key { $0.insertTab(nil) }
        XCTAssertEqual(card.shapes, [B(), B(1)], "the new empty item nests")
        card.key { $0.insertNewline(nil) }
        XCTAssertEqual(card.shapes, [B(), B()], "Enter on an empty nested item moves it up")
        card.key { $0.insertNewline(nil) }
        XCTAssertEqual(card.shapes, [B(), T], "and at the top level ends the list")
        let other = Card(Note(header: "h", body: [line(N(), "a"), line(N(1), "b")]))
        other.caret(before: "b")
        other.key { $0.deleteBackward(nil) }
        XCTAssertEqual(other.shapes, [N(), N()], "Backspace at the start of a nested item moves it up")
        XCTAssertEqual(other.texts, ["a", "b"])
    }

    func testDeletingAParentReLevelsTheChildAndUndoRestoresBoth() {
        let card = Card(Note(header: "h", body: [line(B(), "parent"), line(B(1), "kid")]))
        card.select(from: "parent", through: "parent\n")
        card.key { $0.deleteBackward(nil) }
        XCTAssertEqual(card.texts, ["kid"])
        XCTAssertEqual(card.shapes, [B()], "the orphan moves up to the top")
        card.undo.undo()
        XCTAssertEqual(card.texts, ["parent", "kid"])
        XCTAssertEqual(card.shapes, [B(), B(1)], "one undo brings back the parent and the child's level")
    }

    func testUndoingAJoinRestoresTheJoinedLinesKind() {
        let card = Card(Note(header: "h", body: [line(B(), "a"), line(T, "b")]))
        card.caret(before: "b")
        card.key { $0.deleteBackward(nil) }
        XCTAssertEqual(card.texts, ["ab"])
        XCTAssertEqual(card.shapes, [B()])
        card.undo.undo()
        XCTAssertEqual(card.shapes, [B(), T], "b comes back plain")
    }

    func testUndoingAJoinIntoTheHeaderKeepsBoldAndItalic() {
        let note = Note(header: "Title", body: [
            Line(runs: [Run(text: "bold", style: .bold), Run(text: " and "), Run(text: "italic", style: .italic)]),
            line(T, "next"),
        ])
        let card = Card(note)
        card.caret(before: "bold")
        card.key { $0.deleteBackward(nil) }
        XCTAssertEqual(card.editor.note.header, "Titlebold and italic", "Backspace joins the line into the header")
        card.undo.undo()
        XCTAssertEqual(card.editor.note, note, "undo gives the line back with its bold and italic")
        XCTAssertTrue(card.editor.note.markdown.contains("\n**bold** and *italic*\n"), card.editor.note.markdown)
        card.undo.redo()
        XCTAssertEqual(card.editor.note.header, "Titlebold and italic")
        card.undo.undo()
        XCTAssertEqual(card.editor.note, note, "undo after redo is exact too")
    }

    func testUndoingEveryRandomEditGivesBackTheNote() {
        let note = Note(header: "Title", body: [
            Line(runs: [Run(text: "bold", style: .bold), Run(text: " and "), Run(text: "italic", style: .italic)]),
            Line(runs: [Run(text: "plain "), Run(text: "both", style: [.bold, .italic])]),
        ])
        var random = SplitMix(state: 1500)
        for trial in 0..<300 {
            let card = Card(note)
            var steps: [String] = []
            for _ in 0..<Int.random(in: 1...10, using: &random) {
                let string = card.editor.string as NSString
                let location = Int.random(in: 0...string.length, using: &random)
                let length = Int.random(in: 0...min(4, string.length - location), using: &random)
                let paragraphStart = string.paragraphRange(for: NSRange(location: location, length: 0)).location
                switch Int.random(in: 0..<9, using: &random) {
                case 0:
                    steps.append("type x at \(location)")
                    card.editor.setSelectedRange(NSRange(location: location, length: 0))
                    card.key { $0.insertText("x", replacementRange: $0.selectedRange()) }
                case 1:
                    steps.append("delete \(location)+\(length)")
                    card.editor.setSelectedRange(NSRange(location: location, length: length))
                    card.key { $0.deleteBackward(nil) }
                case 2:
                    steps.append("join at \(paragraphStart)")
                    card.editor.setSelectedRange(NSRange(location: paragraphStart, length: 0))
                    card.key { $0.deleteBackward(nil) }
                case 3:
                    steps.append("forward delete at \(location)")
                    card.editor.setSelectedRange(NSRange(location: location, length: 0))
                    card.key { $0.deleteForward(nil) }
                case 4:
                    steps.append("bold \(location)+\(length)")
                    card.editor.setSelectedRange(NSRange(location: location, length: length))
                    card.key { $0.toggle(.bold) }
                case 5:
                    steps.append("tab over \(location)+\(length)")
                    card.editor.setSelectedRange(NSRange(location: location, length: length))
                    card.key { $0.insertTab(nil) }
                case 6:
                    steps.append("enter at \(location)")
                    card.editor.setSelectedRange(NSRange(location: location, length: 0))
                    card.key { $0.insertNewline(nil) }
                case 7:
                    steps.append("undo")
                    if card.undo.canUndo { card.undo.undo() }
                default:
                    steps.append("redo")
                    if card.undo.canRedo { card.undo.redo() }
                }
            }
            while card.undo.canUndo { card.undo.undo() }
            XCTAssertEqual(card.editor.note, note, "trial \(trial): \(steps)")
        }
    }

    func testListButtonChangesOnlyThatLine() {
        let card = Card(Note(header: "h", body: [line(B(), "parent"), line(B(1), "kid")]))
        card.caret(before: "parent")
        card.key { $0.toggleLineKind(.numbered) }
        XCTAssertEqual(card.shapes, [N(), B(1)])
    }

    func testTypingADashAndSpaceStartsAListAndUndoGivesBackTheDash() {
        let card = Card(Note(header: "h", body: [line(T, "x")]))
        card.caret(before: "x")
        card.key { $0.insertText("-", replacementRange: $0.selectedRange()) }
        card.key { $0.insertText(" ", replacementRange: $0.selectedRange()) }
        XCTAssertEqual(card.shapes, [B()])
        XCTAssertEqual(card.texts, ["x"])
        card.undo.undo()
        XCTAssertEqual(card.shapes, [T])
        XCTAssertEqual(card.texts, ["-x"])
    }

    func testCopyWritesMarkdownAndHTML() {
        let card = Card(Note(header: "h", body: [line(B(), "a"), line(N(1), "b"), line(T, "c")]))
        let board = pasteboard()
        card.select(from: "a", through: "b")
        XCTAssertTrue(card.editor.writeSelection(to: board, types: card.editor.writablePasteboardTypes))
        XCTAssertEqual(board.string(forType: .string), "- a\n    1. b")
        XCTAssertEqual(board.string(forType: .html), "<meta charset=\"utf-8\"><ul><li>a<ol><li>b</li></ol></li></ul>")
        card.caret(before: "c")
        card.editor.setSelectedRange(NSRange(location: card.editor.selectedRange().location, length: 1))
        XCTAssertTrue(card.editor.writeSelection(to: board, types: card.editor.writablePasteboardTypes))
        XCTAssertEqual(board.types?.contains(.html), false, "part of one line is only text")
        XCTAssertEqual(board.string(forType: .string), "c")
        board.releaseGlobally()
    }

    func testPasteIsOneStepAndLeavesTheTextTheNoteSays() {
        let note = Note(header: "h", body: [line(B(), "Fruit"), line(B(1), ""), line(T, "end")])
        let card = Card(note)
        let board = pasteboard()
        board.declareTypes([.html, .string], owner: nil)
        board.setString("<ul><li>apple<ul><li>green</li></ul></li><li>pear</li></ul>", forType: .html)
        board.setString("apple\ngreen\npear", forType: .string)
        card.editor.setSelectedRange(NSRange(location: ("h\nFruit\n" as NSString).length, length: 0))
        card.key { XCTAssertTrue($0.readSelection(from: board, type: .html)) }
        XCTAssertEqual(card.texts, ["Fruit", "apple", "green", "pear", "end"])
        XCTAssertEqual(card.shapes, [B(), B(1), B(2), B(1), T], "the pasted list sits at the empty item's level")
        XCTAssertEqual(card.editor.string, card.editor.note.attributedText.string)
        XCTAssertEqual(card.editor.selectedRange().location, ("h\nFruit\napple\ngreen\npear" as NSString).length)
        card.undo.undo()
        XCTAssertEqual(card.editor.note, note, "one undo takes the whole paste back")
        board.releaseGlobally()
    }

    func testChangedParagraphsAreTheSmallestRegion() {
        let a = Note(header: "h", body: [line(B(), "a"), line(B(), "b"), line(B(), "c")])
        let inserted = Note(header: "h", body: [line(B(), "a"), line(B(), "x"), line(B(), "b"), line(B(), "c")])
        XCTAssertTrue(Note.changedParagraphs(from: a, to: inserted) == (2..<2, 2..<3), "an insertion replaces nothing")
        XCTAssertTrue(Note.changedParagraphs(from: inserted, to: a) == (2..<3, 2..<2))
        let appended = Note(header: "h", body: a.body + [line(B(), "d")])
        XCTAssertTrue(Note.changedParagraphs(from: a, to: appended) == (3..<4, 3..<5), "the old last line gains its line break")
        let retitled = Note(header: "H", body: a.body)
        XCTAssertTrue(Note.changedParagraphs(from: a, to: retitled) == (0..<1, 0..<1))
        let same = Note.changedParagraphs(from: a, to: a)
        XCTAssertTrue(same.old.isEmpty && same.new.isEmpty, "nothing changed")
    }

    func testTheParagraphAttributeRoundTrips() {
        for run in everyRun(upTo: 1) {
            for shape in run {
                XCTAssertEqual(LineShape(attributeValue: shape.attributeValue), shape)
            }
        }
        XCTAssertEqual(LineShape(kind: .bullet).attributeValue, "bullet", "the top level stores what it did before levels")
        XCTAssertEqual(LineShape(attributeValue: "done:9"), D(2, done: true), "a level out of range is clamped")
        XCTAssertEqual(LineShape(attributeValue: "text:2"), .plain)
        XCTAssertEqual(LineShape(attributeValue: "nonsense"), .plain)
        let note = Note(header: "h", body: [line(B(), "a"), line(N(1), ""), line(D(2, done: true), "c"), line(T, "d")])
        XCTAssertEqual(Note(attributedText: note.attributedText), note, "the editor's text holds every shape")
    }

    func testPastedParagraphSeparatorsDoNotSplitTheStorage() {
        let card = Card(Note(header: "h", body: [line(T, ""), line(T, "end")]))
        let board = pasteboard()
        board.declareTypes([.html], owner: nil)
        board.setString("<ul><li>one\u{2029}two</li><li>three</li></ul>", forType: .html)
        card.editor.setSelectedRange(NSRange(location: ("h\n" as NSString).length, length: 0))
        card.key { XCTAssertTrue($0.readSelection(from: board, type: .html)) }
        XCTAssertEqual(card.texts, ["one two", "three", "end"])
        XCTAssertEqual(card.editor.string, card.editor.note.attributedText.string, "storage and note agree paragraph for paragraph")
        card.editor.selectAll(nil)
        XCTAssertTrue(card.editor.writeSelection(to: board, types: card.editor.writablePasteboardTypes), "copy after the paste must not trap")
        XCTAssertEqual(board.string(forType: .string), "# h\n- one two\n- three\nend")
        board.releaseGlobally()
    }
}
