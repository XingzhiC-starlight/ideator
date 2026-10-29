import AppKit
import XCTest
@testable import Ideator

/// The buttons in a card's top-right corner, on a popped card and on the stack's card: what a press
/// reaches while they are hidden, what accessibility still reaches, and the room the title leaves
/// them. Windows stay off screen unless a test needs the pointer rule.
final class HoverButtonsTests: XCTestCase {
    private let cell = CGRect(x: 0, y: 0, width: 342, height: 267)
    /// 40 characters whose first line, on a popped card, used to end under the buttons.
    private let longTitle = "Everything to finish before the holidays"
    private let noDrag = WindowDrag(moved: { _ in }, dropped: { _ in })

    /// A card in each home: a window that puts it at a cell, and the pointer rule of that window.
    private struct Home {
        let name: String
        let window: NSWindow
        let place: (CardFace, CGRect) -> Void
        let pointer: (NSPoint) -> Void

        var card: CardView {
            func find(_ view: NSView) -> CardView? { (view as? CardView) ?? view.subviews.lazy.compactMap(find).first }
            return find(window.contentView!)!
        }
    }

    private func homes(send: @escaping (Command) -> Void = { _ in }) -> [Home] {
        let popped = CardWindow(send: send, drag: noDrag)
        let stack = StackWindow(send: send, menu: { NSMenu() }, toggleHidden: {}, drag: noDrag)
        return [
            Home(name: "popped", window: popped, place: { popped.apply($0, frame: $1) },
                 pointer: { popped.pointerMoved(to: $0) }),
            Home(name: "stacked", window: stack,
                 place: { stack.apply(StackFace(stacked: [], selected: $0, clarity: false, desktopFull: false),
                                      cell: $1, visibility: .all) },
                 pointer: { stack.pointerMoved(to: $0) }),
        ]
    }

    private func face(_ title: String = "Groceries", collapsed: Bool = false) -> CardFace {
        CardFace(id: CardID(rawValue: "a"), note: Note(markdown: "# \(title)\n\nline one\nline two\n"),
                 collapsed: collapsed, summary: collapsed ? .unavailable(reason: "No key") : .body(""))
    }

    private func show(_ face: CardFace, in home: Home) -> CardView {
        home.place(face, cell)
        home.window.contentView!.layoutSubtreeIfNeeded()
        return home.card
    }

    private func row(of card: CardView) -> NSStackView {
        card.subviews.compactMap { $0 as? NSStackView }
            .first { $0.arrangedSubviews.contains { $0.toolTip == "Delete this card" } }!
    }

    private func button(_ tooltip: String, in card: CardView) -> NSButton {
        row(of: card).arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.toolTip == tooltip }!
    }

    /// What a press at the center of `view` reaches, found the way the window finds it.
    private func pressed(at view: NSView, in window: NSWindow) -> NSView? {
        window.contentView!.hitTest(view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil))
    }

    private func names(under element: NSAccessibilityProtocol) -> [String] {
        let own = [element.accessibilityLabel(), element.accessibilityTitle(), element.accessibilityHelp()]
        let children = (element.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol }
        return own.compactMap { $0 } + children.flatMap(names(under:))
    }

    /// Where each visible character of the title is drawn, in the card's coordinates.
    private func titleGlyphs(of card: CardView) -> [NSRect] {
        let editor = card.subviews.compactMap { $0 as? NSScrollView }.first!.documentView as! CardTextView
        let layout = editor.layoutManager!, container = editor.textContainer!
        let string = editor.string as NSString
        let title = string.paragraphRange(for: NSRange(location: 0, length: 0))
        return (title.location..<NSMaxRange(title)).compactMap { index in
            guard let scalar = Unicode.Scalar(string.character(at: index)),
                  !CharacterSet.whitespacesAndNewlines.contains(scalar) else { return nil }
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            return card.convert(rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y), from: editor)
        }
    }

    func testAPressOnAHiddenButtonReachesTheCardUnderIt() {
        for collapsed in [false, true] {
            for home in homes() {
                let card = show(face(collapsed: collapsed), in: home)
                let move = home.name == "popped" ? "Return this card to the top of the stack" : "Bring this card out"
                let tooltips = (collapsed ? ["Refresh summary"] : []) + [move, "Delete this card"]
                for tooltip in tooltips {
                    let hit = pressed(at: button(tooltip, in: card), in: home.window)
                    if collapsed {
                        XCTAssertTrue(hit === card, "\(home.name), collapsed: a press on hidden \(tooltip) is the card's, got \(String(describing: hit))")
                    } else {
                        XCTAssertTrue(hit is CardTextView, "\(home.name): a press on hidden \(tooltip) is a text click, got \(String(describing: hit))")
                    }
                }
                card.setHovering(true)
                for tooltip in tooltips {
                    let shown = button(tooltip, in: card)
                    XCTAssertTrue(pressed(at: shown, in: home.window) === shown, "\(home.name), collapsed \(collapsed): shown \(tooltip) takes the press")
                }
            }
        }
    }

    func testHiddenButtonsStayInTheAccessibilityTreeAndPressable() {
        var sent: [Command] = []
        let card = show(face(), in: homes(send: { sent.append($0) })[0])
        let listed = names(under: card)
        for name in ["↩ Stack", "Delete this card"] {
            XCTAssertTrue(listed.contains(name), "VoiceOver finds \(name) without hovering, got \(listed)")
        }
        _ = button("Return this card to the top of the stack", in: card).accessibilityPerformPress()
        guard case .returnToStack(_)? = sent.last else { return XCTFail("AXPress on ↩ Stack sends .returnToStack, got \(sent)") }
    }

    func testACardHasNoClarityButtonOfItsOwn() {
        for collapsed in [false, true] {
            for home in homes() {
                let card = show(face(collapsed: collapsed), in: home)
                let move = home.name == "popped" ? "Return this card to the top of the stack" : "Bring this card out"
                let tooltips = row(of: card).arrangedSubviews.filter { !$0.isHidden }.compactMap(\.toolTip)
                XCTAssertEqual(tooltips, (collapsed ? ["Refresh summary"] : []) + [move, "Delete this card"],
                               "\(home.name), collapsed \(collapsed): Clarity is the ribbon's button alone")
            }
        }
    }

    func testAPressOnACollapsedBodyTurnsClarityOff() throws {
        var sent: [Command] = []
        for home in homes(send: { sent.append($0) }) {
            sent = []
            let card = show(face(collapsed: true), in: home)
            let content = card.bounds.insetBy(dx: CardView.margin.width, dy: CardView.margin.height)
            let body = card.convert(NSPoint(x: content.midX, y: content.minY + 10), to: nil)
            let press = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: body, modifierFlags: [], timestamp: 0,
                windowNumber: home.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))

            card.mouseDown(with: press)

            guard case .setClarity(false)? = sent.last else { return XCTFail("\(home.name): got \(sent)") }
            XCTAssertEqual(sent.count, 1, "\(home.name): that is all the press sends")
        }
    }

    func testALongTitleNeverRunsUnderTheButtons() {
        for home in homes() {
            let expanded = show(face(longTitle), in: home)
            expanded.setHovering(true)
            let buttons = row(of: expanded).frame
            let glyphs = titleGlyphs(of: expanded)
            XCTAssertEqual(glyphs.count, longTitle.filter { !$0.isWhitespace }.count, "\(home.name): every letter is laid out")
            for glyph in glyphs {
                XCTAssertFalse(glyph.intersects(buttons), "\(home.name), expanded: a letter at \(glyph) runs under the buttons at \(buttons)")
            }
        }
        for home in homes() {
            let collapsed = show(face(longTitle, collapsed: true), in: home)
            collapsed.setHovering(true)
            let header = collapsed.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == longTitle }!
            XCTAssertFalse(header.frame.intersects(row(of: collapsed).frame),
                           "\(home.name), collapsed: the title at \(header.frame) runs under the buttons at \(row(of: collapsed).frame)")
        }
    }

    func testHoverButtonsKeepTheirSizeWhenTheSummarysRefreshAppears() {
        for home in homes() {
            var firstHeight: [String: CGFloat] = [:]
            for (step, collapsed) in [("expanded", false), ("collapsed", true), ("expanded again", false)] {
                let card = show(face(longTitle, collapsed: collapsed), in: home)
                for case let button as NSButton in row(of: card).arrangedSubviews where !button.isHidden {
                    let name = button.toolTip ?? "a button"
                    let oneLine = firstHeight[name, default: button.frame.height]
                    firstHeight[name] = oneLine
                    XCTAssertGreaterThanOrEqual(button.frame.width, button.intrinsicContentSize.width,
                                                "\(home.name), \(step): \(name) is squeezed to \(button.frame.size)")
                    XCTAssertLessThanOrEqual(button.frame.height, oneLine,
                                             "\(home.name), \(step): \(name) wraps to \(button.frame.size), it was \(oneLine) high")
                }
            }
        }
    }

    func testACardThatMovesUnderAStillPointerShowsItsButtons() {
        for home in homes() {
            let card = show(face(), in: home)
            home.window.orderFront(nil)
            defer { home.window.orderOut(nil) }
            let next = cell.offsetBy(dx: cell.width, dy: 0)
            home.place(face(), next)   // on screen, so the window slides there
            let delete = button("Delete this card", in: card)
            let inWindow = delete.convert(NSPoint(x: delete.bounds.midX, y: delete.bounds.midY), to: nil)

            home.pointer(NSPoint(x: next.minX + inWindow.x, y: next.minY + inWindow.y))
            XCTAssertEqual(row(of: card).alphaValue, 1, "\(home.name): the pointer rests where the card arrives, so its buttons show")
            XCTAssertTrue(pressed(at: delete, in: home.window) === delete, "\(home.name): and take the press")

            home.pointer(NSPoint(x: cell.minX + inWindow.x, y: cell.minY + inWindow.y))
            XCTAssertEqual(row(of: card).alphaValue, 0, "\(home.name): the card left the pointer, so its buttons hide")
            XCTAssertTrue(pressed(at: delete, in: home.window) is CardTextView, "\(home.name): and a press there is a text click")
        }
    }
}
