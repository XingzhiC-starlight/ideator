import XCTest
import Carbon.HIToolbox
@testable import Ideator

/// The hint panel and the overlay, as the prototype draws them. Panels are laid out off screen;
/// the tests that order a window in close it themselves.
final class HintPanelTests: XCTestCase {
    private func card(_ progress: String = "1 of 9", optional: Bool = false, skip: Bool = true,
                      title: TourLine = "The stack holds your cards",
                      body: TourLine = "The tan strip is its ribbon, with the buttons. Below it, one stacked card shows at a time.",
                      footer: PhaseScript.Footer = .backAndNext) -> HintCard {
        HintCard(progress: progress, isOptional: optional, canSkip: skip, title: title, body: body, footer: footer)
    }

    private var waiting: HintCard {
        card("2 of 9", title: "Click \(glyph: .plus) on the stack",
             body: "One new card appears at the top left, ready to type. Paste a line from this chat, or type; the first line is its title.",
             footer: .backOnly)
    }

    private var last: HintCard {
        card("9 of 9", skip: false, title: "Done: replay from the menu bar",
             body: "Ideator has no Dock icon: the stacked-rectangles icon in the menu bar has the tour, Settings and Quit. Your notes are files in Documents › Ideator, and this button opens the folder.",
             footer: .backAndStartUsing)
    }

    private var withKeyCap: HintCard {
        card("3 of 9", title: "Click \(glyph: .hide) to hide every card",
             body: "Your card and the stack's page go away; only the ribbon stays. \(key: "⌃⌥I") does the same from any app.",
             footer: .backOnly)
    }

    private var optionalWithChips: HintCard {
        card("8 of 9", optional: true, title: "Your AI tool can add cards",
             body: "In Claude Code or Claude Desktop, say “put this in Ideator” and the card lands on the stack. Turn it on in Settings › MCP, behind \(glyph: .more).")
    }

    /// A panel showing `card` at the size it asks for, laid out and never ordered in.
    private func panel(_ card: HintCard, faceWidth: CGFloat = 316) -> HintPanel {
        let panel = HintPanel()
        panel.apply(card)
        panel.setFrame(NSRect(origin: .zero, size: HintPanel.size(of: card, faceWidth: faceWidth)), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        return panel
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }

    private func shownButtons(in panel: NSWindow) -> [NSButton] {
        descendants(of: panel.contentView!).compactMap { $0 as? NSButton }.filter { !$0.isHidden }
    }

    private func texts(in panel: NSWindow) -> [TourText] {
        descendants(of: panel.contentView!).compactMap { $0 as? TourText }.filter { !$0.isHidden }
    }

    private func press(_ name: String, in panel: NSWindow) {
        shownButtons(in: panel).first { $0.title == name }?.performClick(nil)
    }

    private func returnKey(for window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
                         keyCode: UInt16(kVK_Return))!
    }

    func testThePanelsAreAsLargeAsThePrototypesForTheSameCopy() {
        // The prototype's pages 1 and 2 measured 316 × 152 and 316 × 170 visible at 1512 pt.
        XCTAssertEqual(HintPanel.size(of: card(), faceWidth: 316), CGSize(width: 322, height: 158))
        XCTAssertEqual(HintPanel.size(of: waiting, faceWidth: 316), CGSize(width: 322, height: 176))
    }

    func testEveryLineAndButtonFitsInsideThePanelAtTheSizeItAsksFor() {
        for hint in [card(), waiting, last, withKeyCap, optionalWithChips] {
            for width in [CGFloat(316), 240] {
                let panel = panel(hint, faceWidth: width)
                let content = panel.contentView!
                let face = content.bounds.insetBy(dx: CardShape.gap + 1, dy: CardShape.gap + 1)
                XCTAssertEqual(panel.frame.width, width + 2 * CardShape.gap)
                for text in texts(in: panel) {
                    let frame = content.convert(text.textFrame, from: text.superview)
                    XCTAssertTrue(face.contains(frame), "\(text.spoken) inside the face at \(width): \(frame)")
                    XCTAssertEqual(text.textFrame.height, TourText.height(of: text.text, width: text.textFrame.width),
                                   "\(text.spoken) has all the lines it needs")
                }
                for button in shownButtons(in: panel) {
                    let frame = content.convert(button.bounds, from: button)
                    XCTAssertTrue(face.contains(frame), "\(button.title) inside the face at \(width): \(frame)")
                }
            }
        }
    }

    func testTheButtonsAreTheOnesThePageOffersNamedForTheHarness() {
        XCTAssertEqual(shownButtons(in: panel(card())).map(\.title).sorted(), ["Back", "Next", "Skip the tour"])
        XCTAssertEqual(shownButtons(in: panel(waiting)).map(\.title).sorted(), ["Back", "Skip the tour"],
                       "a page that waits for the real control has no Next")
        XCTAssertEqual(shownButtons(in: panel(last)).map(\.title).sorted(), ["Back", "Start using Ideator"],
                       "the last page has nothing to skip to")
        for hint in [card(), waiting, last] {
            XCTAssertFalse(shownButtons(in: panel(hint)).contains { $0.title == "New" || $0.accessibilityLabel() == "New" },
                           "the harness takes the window with a New button for the stack")
        }
    }

    func testEachButtonSendsItsInput() {
        let page = panel(card())
        var inputs: [TourInput] = []
        page.onInput = { inputs.append($0) }
        for name in ["Skip the tour", "Back", "Next"] { press(name, in: page) }
        XCTAssertEqual(inputs, [.skip, .back, .next])

        let end = panel(last)
        end.onInput = { inputs.append($0) }
        press("Start using Ideator", in: end)
        XCTAssertEqual(inputs.last, .finish)
    }

    func testReturnPressesNextOrStartUsingIdeatorAndNothingOnAPageThatWaits() {
        var inputs: [TourInput] = []
        for hint in [card(), last, waiting] {
            let panel = panel(hint)
            panel.onInput = { inputs.append($0) }
            _ = panel.performKeyEquivalent(with: returnKey(for: panel))
        }
        XCTAssertEqual(inputs, [.next, .finish])
    }

    func testANewCardReplacesTheOneShown() {
        let panel = panel(card())

        panel.apply(last)
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(texts(in: panel).map(\.spoken).contains("Done: replay from the menu bar"))
        XCTAssertFalse(texts(in: panel).map(\.spoken).contains("The stack holds your cards"))
    }

    func testVoiceOverReadsAChipAsItsControlsName() throws {
        let panel = panel(waiting)
        let title = try XCTUnwrap(texts(in: panel).first { $0.spoken.hasPrefix("Click") })

        XCTAssertEqual(TourLine("Click \(glyph: .plus) on the stack").spoken, "Click New on the stack")
        XCTAssertEqual(title.accessibilityValue() as? String, "Click New on the stack")
        XCTAssertEqual(title.accessibilityRole(), .staticText)
        XCTAssertTrue(texts(in: panel).contains { $0.accessibilityValue() as? String == "2 of 9" })
    }

    func testOptionalShowsOnlyOnAnOptionalPage() {
        XCTAssertTrue(texts(in: panel(optionalWithChips)).contains { $0.spoken == "Optional" })
        XCTAssertFalse(texts(in: panel(card())).contains { $0.spoken == "Optional" })
    }

    func testThePanelFloatsWithoutActivatingIdeatorOnEverySpace() {
        let panel = HintPanel()

        XCTAssertEqual(panel.title, "Ideator tour")
        XCTAssertEqual(panel.level, .floating, "readable when the cards drop behind another app")
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel), "a click never reads as the cards coming forward")
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    // MARK: Chips on the line

    /// The rows, in points from the top, where `text` drawn on its own shows the chip's square and
    /// the first letter's ink; the letter is an H, so its ink ends on the baseline.
    private func rows(of text: NSAttributedString) throws -> (chip: ClosedRange<CGFloat>, letter: ClosedRange<CGFloat>) {
        let view = TourText()
        view.text = text
        view.place(in: NSRect(x: 0, y: 0, width: 300, height: TourText.height(of: text, width: 300)))
        let scale = 2
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * scale,
                                                 pixelsHigh: Int(view.bounds.height) * scale, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        func rows(where shows: (NSColor) -> Bool, columns: Range<Int>) -> ClosedRange<CGFloat>? {
            let hit = (0..<rep.pixelsHigh).filter { y in columns.contains { x in rep.colorAt(x: x, y: y).map(shows) ?? false } }
            guard let first = hit.first, let last = hit.last else { return nil }
            return CGFloat(first) / CGFloat(scale) - TourText.bleed...CGFloat(last + 1) / CGFloat(scale) - TourText.bleed
        }
        let ribbon = TourButton.ribbon.usingColorSpace(.deviceRGB)!
        let chip = try XCTUnwrap(rows(where: { $0.alphaComponent > 0.95 && abs($0.redComponent - ribbon.redComponent) < 0.04
                                               && abs($0.blueComponent - ribbon.blueComponent) < 0.04 },
                                      columns: 0..<rep.pixelsWide))
        let letter = try XCTUnwrap(rows(where: { $0.alphaComponent > 0.5 }, columns: 0..<(4 * scale)))
        return (chip, letter)
    }

    func testAChipHangsFromTheBaselineWhereThePrototypeHangsIt() throws {
        let title = try rows(of: TourLine("H\(glyph: .plus) on the stack").attributed(.title))
        XCTAssertEqual(title.chip.upperBound - title.letter.upperBound, 5.5, accuracy: 0.5, "a title's chip: 5.5 below the baseline")
        XCTAssertEqual(title.letter.upperBound - title.chip.lowerBound, 12.5, accuracy: 0.5, "and 12.5 above it")

        let body = try rows(of: TourLine("H\(glyph: .trash) deletes it.").attributed(.body))
        XCTAssertEqual(body.chip.upperBound - body.letter.upperBound, 6.5, accuracy: 0.5, "a body's chip: 6.5 below the baseline")
        XCTAssertEqual(body.letter.upperBound - body.chip.lowerBound, 11.5, accuracy: 0.5, "and 11.5 above it")
    }

    func testAChipLeavesTheLinesOfItsTextEvenlySpaced() {
        let oneLine = TourLine("Click \(glyph: .trash) to delete it.")
        let twoLines = TourLine("Its buttons appear on hover: \(glyph: .returnToStack) returns the card to the stack, \(glyph: .trash) deletes it. Return it now.")
        XCTAssertEqual(TourText.height(of: oneLine.attributed(.body), width: 282), 18)
        XCTAssertEqual(TourText.height(of: twoLines.attributed(.body), width: 282), 36, "two lines 18 pt apart, as without chips")
        XCTAssertEqual(TourText.height(of: TourLine("Click \(glyph: .hide) to hide every card").attributed(.title), width: 282), 24)
    }

    // MARK: The overlay

    private let ring = RingShape(rect: CGRect(x: 600, y: 400, width: 28, height: 28), radius: 9)

    private func pointing(rings: [RingShape] = [], notch: Notch? = nil, panel: CGRect = CGRect(x: 100, y: 100, width: 322, height: 158),
                          lit: [CGRect] = [], menuBar: Bool = false) -> Pointing {
        Pointing(panel: panel, notch: notch, rings: rings, lit: lit, needsMenuBarLevel: menuBar)
    }

    func testTheOverlayNeverTakesTheMouseAndSitsAboveThePanelOrTheMenuBar() {
        let overlay = GuideOverlay()
        overlay.apply(pointing(rings: [ring]), above: .floating)
        XCTAssertTrue(overlay.ignoresMouseEvents, "clicks go to the ringed control under it")
        XCTAssertGreaterThan(overlay.level.rawValue, NSWindow.Level.floating.rawValue, "over the panel, to draw its notch")
        XCTAssertLessThan(overlay.level.rawValue, NSWindow.Level.mainMenu.rawValue)

        overlay.apply(pointing(rings: [ring], menuBar: true), above: .floating)
        XCTAssertGreaterThan(overlay.level.rawValue, NSWindow.Level.statusBar.rawValue, "a ring around the menu bar icon shows")
    }

    /// The overlay's drawing, read back in screen points.
    private func drawing(_ pointing: Pointing) throws -> (NSPoint) -> NSColor {
        let overlay = GuideOverlay()
        overlay.apply(pointing, above: .floating)
        let canvas = try XCTUnwrap(overlay.contentView)
        let rep = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let origin = overlay.frame.origin
        let scale = CGFloat(rep.pixelsWide) / canvas.bounds.width
        return { point in
            let x = Int((point.x - origin.x) * scale)
            let y = rep.pixelsHigh - 1 - Int((point.y - origin.y) * scale)
            return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
        }
    }

    func testARingIsAnAccentLineWithAHaloAndNothingInside() throws {
        let color = try drawing(pointing(rings: [ring]))

        let onLine = color(NSPoint(x: ring.rect.midX, y: ring.rect.minY + 1))
        XCTAssertEqual(onLine.alphaComponent, 1, accuracy: 0.02, "the 2 pt line just inside the ring's edge")
        // The accent's hue, a dark reddish brown; exact levels shift through the display's color space.
        XCTAssertGreaterThan(onLine.redComponent, onLine.greenComponent + 0.15)
        XCTAssertGreaterThan(onLine.greenComponent, onLine.blueComponent)
        XCTAssertLessThan(onLine.redComponent, 0.7)
        XCTAssertEqual(color(NSPoint(x: ring.rect.midX, y: ring.rect.midY)).alphaComponent, 0, "the control itself is never tinted")
        let halo = color(NSPoint(x: ring.rect.midX, y: ring.rect.minY - 3)).alphaComponent
        XCTAssertGreaterThan(halo, 0.2, "the halo, with the glow under it")
        XCTAssertLessThan(halo, 0.6)
        let glow = color(NSPoint(x: ring.rect.midX, y: ring.rect.minY - 10)).alphaComponent
        XCTAssertGreaterThan(glow, 0.02, "the glow reaches past the halo")
        XCTAssertLessThan(glow, halo)
        XCTAssertEqual(color(NSPoint(x: ring.rect.midX, y: ring.rect.minY - 40)).alphaComponent, 0, "and fades out")
    }

    func testRingsAndLitCellsStayUnderThePanelAndTheNotchCoversItsEdge() throws {
        let panel = CGRect(x: 100, y: 100, width: 322, height: 158)
        let face = panel.insetBy(dx: 3, dy: 3)
        let overlapping = RingShape(rect: CGRect(x: face.maxX - 40, y: 200, width: 80, height: 28), radius: 9)
        let lit = CGRect(x: face.minX - 50, y: 120, width: 100, height: 80)
        let color = try drawing(pointing(rings: [overlapping], notch: .right(at: 100), panel: panel, lit: [lit]))

        XCTAssertEqual(color(NSPoint(x: face.maxX - 20, y: 201)).alphaComponent, 0, "the ring is not drawn over the panel")
        XCTAssertEqual(color(NSPoint(x: face.maxX + 20, y: 201)).alphaComponent, 1, accuracy: 0.02, "but is beside it")
        XCTAssertEqual(color(NSPoint(x: face.minX + 20, y: 160)).alphaComponent, 0, "nor is a lit cell")
        XCTAssertGreaterThan(color(NSPoint(x: face.minX - 20, y: 160)).alphaComponent, 0.05)

        let tip = color(NSPoint(x: face.maxX + 4, y: face.maxY - 100))
        XCTAssertEqual(tip.alphaComponent, 1, accuracy: 0.02, "the notch sticks out of the panel's right edge")
        XCTAssertGreaterThan(tip.greenComponent, 0.85, "in the paper color")
        XCTAssertEqual(color(NSPoint(x: face.maxX + 4, y: face.maxY - 120)).alphaComponent, 0, "at its offset only")
    }

    // MARK: The stage

    func testTheStageShowsThePanelWhereItIsPointedWithoutTakingKeyAndHidesBoth() throws {
        let stage = TourStage()
        let scene = TourScene(card: card(), pointing: pointing(panel: CGRect(x: -20_000, y: -20_000, width: 322, height: 158)),
                              heldHover: nil)
        defer { stage.hide() }
        let keyBefore = NSApp.keyWindow

        stage.show(scene, takesKey: false)

        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "Ideator tour" && $0.isVisible })
        XCTAssertEqual(panel.frame, scene.pointing.panel)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(NSApp.keyWindow === keyBefore)
        XCTAssertTrue(NSApp.windows.contains { $0 is GuideOverlay && $0.isVisible })

        stage.hide()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(NSApp.windows.contains { $0 is GuideOverlay && $0.isVisible })
    }
}

private extension TourLine {
    init(_ line: TourLine) { self = line }
}
