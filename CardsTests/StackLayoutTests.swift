import XCTest
@testable import Ideator

/// The stack's ribbon, count badge and shown card's buttons, in a window that is never shown.
final class StackLayoutTests: XCTestCase {
    /// The cell width a 1512-point screen gives, and a 1366-point one.
    private let wide: CGFloat = 302.4
    private let narrow: CGFloat = 273
    private let belowAnyCell: CGFloat = 180
    /// Less than the icon toolbar, the menu button and the badge need side by side.
    private let tooNarrowForBadge: CGFloat = 110

    private struct Stack {
        let window: StackWindow
        let toggled: () -> Int
        let sent: () -> [Command]
        /// Each Spread press, true for a fresh set.
        let spreads: () -> [Bool]

        var view: NSView { window.contentView!.subviews[0] }   // the glass holds the stack view
        func control(_ tooltip: String) -> NSView {
            view.subviews.first { $0.toolTip == tooltip }!
        }
        var toggle: NSView { view.subviews.first { $0.toolTip == "Hide all" || $0.toolTip == "Show all" }! }
        var menu: NSView { control("Settings and quit") }
        var badge: NSView { control("Arrange the stack") }
        var desktopFull: NSView { view.subviews.first { ($0 as? NSTextField)?.stringValue == "Desktop full" }! }
        /// New, the toggle, Spread and Clarity, left to right.
        var ribbonButtons: [NSButton] {
            view.subviews.compactMap { $0 as? NSButton }
                .filter { ["New", "Hide all", "Show all", "Spread", "Clarity"].contains($0.accessibilityLabel()) }
                .sorted { $0.frame.minX < $1.frame.minX }
        }
        var spread: NSButton { ribbonButtons.first { $0.accessibilityLabel() == "Spread" }! }
        var clarity: NSButton { ribbonButtons.last! }
        var toolbarEnd: CGFloat { ribbonButtons.map(\.frame.maxX).max()! }
        var card: CardView { view.subviews.compactMap { $0 as? CardView }.first! }
    }

    private func hoverButton(_ title: String, in card: CardView) -> NSButton? {
        let row = card.subviews.compactMap { $0 as? NSStackView }
            .first { $0.arrangedSubviews.contains { $0.toolTip == "Delete this card" } }
        return row?.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.title == title }
    }

    private func stack(width: CGFloat, _ visibility: Visibility = .all, full: Bool = false,
                       clarity: Bool = false, count: Int = 12, spread: SpreadButton = .spread,
                       refusal: SpreadRefusal? = nil) -> Stack {
        var toggles = 0
        var commands: [Command] = []
        var spreads: [Bool] = []
        let window = StackWindow(send: { commands.append($0) }, menu: { NSMenu() }, toggleHidden: { toggles += 1 },
                                 spread: { spreads.append($0) }, drag: WindowDrag(moved: { _ in }, dropped: { _ in }))
        let card = CardFace(id: CardID(rawValue: "a"), note: Note(header: "Title", body: []), collapsed: false,
                            summary: .body(""))
        let rows = (0..<count).map { StackRow(id: CardID(rawValue: "row\($0)"), title: "Card \($0)") }
        let face = StackFace(stacked: rows, selected: card, clarity: clarity, desktopFull: full, spreadButton: spread)
        window.apply(face, cell: CGRect(x: 0, y: 0, width: width, height: (width * 0.78).rounded()), visibility: visibility,
                     spreadRefusal: refusal)
        window.contentView!.layoutSubtreeIfNeeded()
        return Stack(window: window, toggled: { toggles }, sent: { commands }, spreads: { spreads })
    }

    func testTheRibbonIsNewTheToggleSpreadAndClarityButNoPop() {
        let shown = stack(width: wide)
        XCTAssertEqual(shown.ribbonButtons.map { $0.accessibilityLabel() }, ["New", "Hide all", "Spread", "Clarity"])
        XCTAssertTrue(shown.ribbonButtons.allSatisfy { $0.image != nil && $0.imagePosition == .imageOnly }, "icons, no words")
        XCTAssertEqual(shown.ribbonButtons.first?.toolTip, "New card")
        XCTAssertLessThan(shown.ribbonButtons.last!.frame.maxX, shown.view.bounds.midX, "all four at the left")
    }

    func testTheToolbarIconsAreEvenlySpacedByWhatTheyDraw() throws {
        for width in [wide, narrow] {
            for (visibility, clarity) in [(Visibility.all, false), (.hideAll, false), (.all, true), (.hideAll, true)] {
                let ribbon = stack(width: width, visibility, clarity: clarity)
                let buttons = ribbon.ribbonButtons
                let inked = try shownSpans(of: buttons, in: ribbon.window)
                let state = "\(visibility), clarity \(clarity), width \(width), x\(ribbon.window.backingScaleFactor), "
                    + "ink \(inked), frames \(buttons.map(\.frame)), images \(buttons.map { $0.image?.size ?? .zero })"
                for (left, right) in zip(inked, inked.dropFirst()) {
                    XCTAssertEqual(right.lowerBound - left.upperBound, 12, accuracy: 0.5, state)
                }
                for (left, right) in zip(buttons, buttons.dropFirst()) {
                    XCTAssertLessThanOrEqual(left.frame.maxX, right.frame.minX, "hit areas never overlap")
                }
                for button in buttons {
                    XCTAssertGreaterThanOrEqual(button.frame.width, 18)
                }
            }
        }
    }

    /// Where each of `buttons` shows ink, as a span of its superview's x coordinates: read from the
    /// pixels its window puts on screen, with the window ordered in out of sight and each button's
    /// layer rendered at the window's pixel density. Not from a drawing of the view offscreen, which
    /// can differ: on a 1x screen macOS 26 drew some symbols narrower in the window than on their own.
    private func shownSpans(of buttons: [NSButton], in window: NSWindow) throws -> [ClosedRange<CGFloat>] {
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        window.displayIfNeeded()
        CATransaction.flush()
        let scale = window.backingScaleFactor
        return try buttons.map { button in
            let layer = try XCTUnwrap(button.layer)
            let columns = Int((button.bounds.width * scale).rounded())
            let rows = Int((button.bounds.height * scale).rounded())
            let context = try XCTUnwrap(CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8,
                                                  bytesPerRow: columns * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
            let alpha = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let inked = (0..<columns).filter { x in (0..<rows).contains { y in alpha[(y * columns + x) * 4 + 3] > 25 } }
            let first = try XCTUnwrap(inked.first, "\(button.accessibilityLabel() ?? "a button") shows nothing")
            let last = try XCTUnwrap(inked.last)
            return (button.frame.minX + CGFloat(first) / scale)...(button.frame.minX + CGFloat(last + 1) / scale)
        }
    }

    func testClaritySaysItsStateByFillColorAndValue() throws {
        let off = stack(width: wide).clarity
        let on = stack(width: wide, clarity: true).clarity
        XCTAssertEqual([off.accessibilityLabel(), on.accessibilityLabel()], ["Clarity", "Clarity"])
        XCTAssertNotEqual(off.image?.tiffRepresentation, on.image?.tiffRepresentation, "an outline off, filled on")
        XCTAssertEqual(off.frame, on.frame, "and it does not move")
        XCTAssertEqual(off.contentTintColor, Palette.ribbonInk)
        XCTAssertEqual(on.contentTintColor, Palette.accent)
        XCTAssertEqual(off.accessibilityValue() as? String, "off")
        XCTAssertEqual(on.accessibilityValue() as? String, "on")
        XCTAssertEqual(off.toolTip, "Clarity is off: click to collapse every card")
        XCTAssertEqual(on.toolTip, "Clarity is on: click to expand every card")
    }

    func testSpreadSaysWhatAClickDoesByTintTooltipAndValue() {
        let spreads = stack(width: wide)
        let gathers = stack(width: wide, spread: .gather)
        XCTAssertEqual([spreads.spread.accessibilityLabel(), gathers.spread.accessibilityLabel()], ["Spread", "Spread"],
                       "one name in both states")
        XCTAssertEqual(spreads.spread.toolTip, "Spread cards")
        XCTAssertEqual(gathers.spread.toolTip, "Gather cards")
        XCTAssertEqual(spreads.spread.contentTintColor, Palette.ribbonInk)
        XCTAssertEqual(gathers.spread.contentTintColor, Palette.accent, "tinted while its cards are out, like Clarity on")
        XCTAssertEqual(spreads.spread.accessibilityValue() as? String, "in")
        XCTAssertEqual(gathers.spread.accessibilityValue() as? String, "out")
        XCTAssertEqual(spreads.spread.frame, gathers.spread.frame, "and it does not move")
    }

    func testARefusedSpreadSaysWhyUntilAClickWouldGather() {
        XCTAssertEqual(stack(width: wide, refusal: .taken).spread.toolTip, "Your Spread cells are taken")
        XCTAssertEqual(stack(width: wide, refusal: .noCells).spread.toolTip, "Pick Spread cells in Settings")
        XCTAssertEqual(stack(width: wide, spread: .gather, refusal: .taken).spread.toolTip, "Gather cards")
    }

    func testAClickSpreadsAndTheNewSpreadActionStartsAFreshSet() throws {
        let ribbon = stack(width: wide)
        ribbon.spread.performClick(nil)
        XCTAssertEqual(ribbon.spreads(), [false], "a click carries no Option")
        let fresh = try XCTUnwrap(ribbon.spread.cell?.accessibilityCustomActions()?.first { $0.name == "New spread" },
                                  "AppKit serves a button's actions from its cell: ones set on the button never reach VoiceOver")
        XCTAssertEqual(fresh.handler?(), true)
        XCTAssertEqual(ribbon.spreads(), [false, true], "the action asks for a fresh set")
        XCTAssertEqual(ribbon.sent().count, 0, "the ribbon leaves the command to the controller")
    }

    func testTheClarityButtonSetsTheOppositeOfWhatTheRibbonShows() {
        for shown in [false, true] {
            let ribbon = stack(width: wide, clarity: shown)

            _ = ribbon.clarity.accessibilityPerformPress()

            guard case .setClarity(let on)? = ribbon.sent().last else { return XCTFail("got \(ribbon.sent())") }
            XCTAssertEqual(on, !shown, "Clarity \(shown ? "on" : "off") is pressed to \(shown ? "off" : "on")")
            XCTAssertEqual(ribbon.sent().count, 1)
        }
    }

    func testTheStackedCardPopsItselfAndADesktopCardReturnsToTheStack() throws {
        let shown = stack(width: wide)
        let pop = try XCTUnwrap(hoverButton("↗ Pop", in: shown.card))
        XCTAssertNil(hoverButton("↩ Stack", in: shown.card), "a stacked card is already on the stack")
        XCTAssertTrue(pop.isEnabled)
        XCTAssertEqual(pop.toolTip, "Bring this card out")
        pop.performClick(nil)
        guard case .pop? = shown.sent().last else { return XCTFail("Pop sends .pop, got \(shown.sent())") }

        var sent: [Command] = []
        let desktop = CardView(home: .desktop(WindowDrag(moved: { _ in }, dropped: { _ in })), send: { sent.append($0) })
        desktop.apply(CardFace(id: CardID(rawValue: "a"), note: Note(header: "Title", body: []), collapsed: false,
                               summary: .body("")))
        XCTAssertNil(hoverButton("↗ Pop", in: desktop), "a desktop card is already out")
        let back = try XCTUnwrap(hoverButton("↩ Stack", in: desktop))
        XCTAssertEqual(back.toolTip, "Return this card to the top of the stack")
        back.performClick(nil)
        guard case .returnToStack(let id)? = sent.last else { return XCTFail("↩ Stack sends .returnToStack, got \(sent)") }
        XCTAssertEqual(id, CardID(rawValue: "a"))
    }

    func testPopIsGreyedOnAFullDesktopAndSaysWhy() throws {
        let full = stack(width: wide, full: true)
        let pop = try XCTUnwrap(hoverButton("↗ Pop", in: full.card))
        XCTAssertFalse(pop.isEnabled)
        XCTAssertEqual(pop.toolTip, "Desktop full")
        let roomAgain = stack(width: wide)
        XCTAssertTrue(try XCTUnwrap(hoverButton("↗ Pop", in: roomAgain.card)).isEnabled)
    }

    func testTheToggleOffersHideAllWhileCardsShowAndShowAllWhileHidden() throws {
        let shown = stack(width: wide)
        XCTAssertEqual(shown.toggle.toolTip, "Hide all", "with cards showing it hides them")
        XCTAssertEqual(shown.toggle.accessibilityLabel(), "Hide all")
        let hidden = stack(width: wide, .hideAll)
        XCTAssertEqual(hidden.toggle.toolTip, "Show all", "under Hide all it shows them again")
        XCTAssertEqual(hidden.toggle.accessibilityLabel(), "Show all")
        XCTAssertEqual(hidden.toggle.frame.minX, shown.toggle.frame.minX, "the chevron keeps its x")
        XCTAssertEqual(hidden.toggle.frame.size, shown.toggle.frame.size, "and its size")
        XCTAssertEqual(hidden.view.bounds.maxY - hidden.toggle.frame.maxY, shown.view.bounds.maxY - shown.toggle.frame.maxY,
                       "and its distance from the top, so it flips in place within the ribbon")
        try XCTUnwrap(hidden.toggle as? NSButton).performClick(nil)
        XCTAssertEqual(hidden.toggled(), 1, "one click toggles")
    }

    func testTheBadgeIsInTheCardsBottomRightUnlessHideAllRemovedTheCard() {
        let shown = stack(width: wide)
        XCTAssertGreaterThan(shown.badge.frame.midX, shown.view.bounds.midX, "on the right")
        XCTAssertLessThan(shown.badge.frame.maxY, shown.menu.frame.minY, "below the ribbon, in the card area")
        XCTAssertLessThan(shown.badge.frame.minY, shown.view.bounds.height * 0.2, "near the bottom")
        let hidden = stack(width: wide, .hideAll)
        XCTAssertEqual(hidden.badge.frame.midY, hidden.menu.frame.midY, accuracy: 2, "in the ribbon")
        XCTAssertLessThanOrEqual(hidden.badge.frame.maxX, hidden.menu.frame.minX, "left of the menu button")
        XCTAssertGreaterThan(hidden.badge.frame.minX, hidden.toolbarEnd, "right of the toolbar")
    }

    private func center(of badge: NSView, in stack: Stack) -> CGPoint {
        stack.view.convert(CGPoint(x: badge.frame.midX, y: badge.frame.midY), to: stack.view.superview)
    }

    func testTheBadgeIsAButtonThatTakesTheClickInBothPlacements() {
        for visibility in [Visibility.all, .hideAll] {
            let stack = stack(width: wide, visibility)
            let hit = stack.view.hitTest(center(of: stack.badge, in: stack))
            XCTAssertTrue(hit === stack.badge, "the badge takes the press, \(visibility)")
            XCTAssertTrue(stack.badge is NSButton, "as a button")
            XCTAssertFalse(hit === stack.view, "so in the ribbon the press does not drag the stack")
        }
    }

    func testTheBadgeReadsItsCountToVoiceOverAndOffersTheArranger() throws {
        let badge = try XCTUnwrap(stack(width: wide).badge as? NSButton)
        XCTAssertEqual(badge.title, "12", "it shows the number")
        XCTAssertEqual(badge.accessibilityLabel(), "12 cards in the stack", "and says what it counts")
        XCTAssertEqual(badge.toolTip, "Arrange the stack", "the tooltip names what it does")
        XCTAssertFalse(badge.refusesFirstResponder, "Tab can reach it when keyboard navigation is on")
        XCTAssertEqual(try XCTUnwrap(stack(width: wide, count: 1).badge as? NSButton).accessibilityLabel(),
                       "1 card in the stack", "one card is singular")
    }

    func testAtZeroCardsTheBadgeDoesNothingAndLeavesAPressToWhatIsUnderIt() throws {
        for visibility in [Visibility.all, .hideAll] {
            let stack = stack(width: wide, visibility, count: 0)
            let badge = try XCTUnwrap(stack.badge as? NSButton)
            XCTAssertEqual(badge.title, "0", "it still counts")
            XCTAssertFalse(badge.isEnabled, "but is not a live button")
            let hit = stack.view.hitTest(center(of: badge, in: stack))
            XCTAssertFalse(hit === badge, "a press does not land on it, \(visibility)")
            if visibility == .hideAll {
                XCTAssertTrue(hit === stack.view, "in the ribbon the press drags the stack as before")
            }
        }
    }

    func testTheBadgeClearsTheFormattingBarsButtons() throws {
        for width in [wide, narrow] {
            let stack = stack(width: width)
            let cardView = try XCTUnwrap(stack.view.subviews.first { String(describing: type(of: $0)) == "CardView" })
            let bar = try XCTUnwrap(cardView.subviews.first { $0 is FormatBar } as? FormatBar)
            bar.layoutSubtreeIfNeeded()
            let buttonsEnd = bar.arrangedSubviews.map { stack.view.convert($0.frame, from: bar).maxX }.max()!
            XCTAssertLessThan(buttonsEnd, stack.badge.frame.minX, "at width \(width)")
        }
    }

    func testDesktopFullTruncatesBeforeAnyButtonMoves() {
        for visibility in [Visibility.all, .hideAll] {
            let without = stack(width: wide, visibility)
            let with = stack(width: wide, visibility, full: true)
            XCTAssertEqual(with.ribbonButtons.map(\.frame), without.ribbonButtons.map(\.frame), "the toolbar stays put")
            XCTAssertEqual(with.menu.frame, without.menu.frame, "and so does the menu button")
            let label = with.desktopFull.frame
            let rightEdge = visibility == .all ? with.menu.frame.minX : with.badge.frame.minX
            XCTAssertGreaterThanOrEqual(label.minX, with.toolbarEnd, "the label stays right of the toolbar")
            XCTAssertLessThanOrEqual(label.maxX, rightEdge, "and left of what is at its right")
        }
    }

    func testTheRibbonOnlyBadgeGivesWayRatherThanCoverTheToolbar() {
        let wideRibbon = stack(width: wide, .hideAll)
        XCTAssertFalse(wideRibbon.badge.isHidden, "with room the count shows beside the menu button")
        let narrowRibbon = stack(width: belowAnyCell, .hideAll)
        XCTAssertTrue(narrowRibbon.badge.isHidden || narrowRibbon.badge.frame.minX >= narrowRibbon.toolbarEnd + 8,
                      "it shows only clear of the toolbar")
        XCTAssertGreaterThan(narrowRibbon.menu.frame.minX, narrowRibbon.toolbarEnd, "and the buttons stay apart")
        let cramped = stack(width: tooNarrowForBadge, .hideAll)
        XCTAssertTrue(cramped.badge.isHidden, "without room it goes instead of covering the Clarity button")
    }
}
