import XCTest
@testable import Ideator

/// The stack's ribbon, count badge and shown card's buttons, in a window that is never shown.
final class StackLayoutTests: XCTestCase {
    /// The cell width a 1512-point screen gives, and a 1366-point one.
    private let wide: CGFloat = 302.4
    private let narrow: CGFloat = 273
    private let belowAnyCell: CGFloat = 180

    private struct Stack {
        let window: StackWindow
        let toggled: () -> Int
        let sent: () -> [Command]

        var view: NSView { window.contentView!.subviews[0] }   // the glass holds the stack view
        func control(_ tooltip: String) -> NSView {
            view.subviews.first { $0.toolTip == tooltip }!
        }
        var toggle: NSView { view.subviews.first { $0.toolTip == "Hide all" || $0.toolTip == "Show all" }! }
        var menu: NSView { control("Settings and quit") }
        var badge: NSView { control("Arrange the stack") }
        var toolbar: NSView { view.subviews.first { $0 is NSStackView }! }
        var desktopFull: NSView { view.subviews.first { ($0 as? NSTextField)?.stringValue == "Desktop full" }! }
        var ribbonButtons: [NSButton] { (toolbar as! NSStackView).arrangedSubviews.compactMap { $0 as? NSButton } }
        var card: CardView { view.subviews.compactMap { $0 as? CardView }.first! }
    }

    private func hoverButton(_ title: String, in card: CardView) -> NSButton? {
        let row = card.subviews.first { type(of: $0) == NSStackView.self } as? NSStackView
        return row?.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.title == title }
    }

    private func stack(width: CGFloat, _ visibility: Visibility = .all, full: Bool = false,
                       clarity: Bool = false, count: Int = 12) -> Stack {
        var toggles = 0
        var commands: [Command] = []
        let window = StackWindow(send: { commands.append($0) }, menu: { NSMenu() }, toggleHidden: { toggles += 1 },
                                 drag: WindowDrag(moved: { _ in }, dropped: { _ in }))
        let card = CardFace(id: CardID(rawValue: "a"), note: Note(header: "Title", body: []), collapsed: false,
                            summary: .body(""))
        let rows = (0..<count).map { StackRow(id: CardID(rawValue: "row\($0)"), title: "Card \($0)") }
        let face = StackFace(stacked: rows, selected: card, clarity: clarity, desktopFull: full)
        window.apply(face, cell: CGRect(x: 0, y: 0, width: width, height: (width * 0.78).rounded()), visibility: visibility)
        window.contentView!.layoutSubtreeIfNeeded()
        return Stack(window: window, toggled: { toggles }, sent: { commands })
    }

    func testTheRibbonHasNewAndClarityButNoPop() {
        XCTAssertEqual(stack(width: wide).ribbonButtons.map(\.title), ["New", "Clarity"])
    }

    func testClaritySaysItsStateByColorAndValueWhileTheLabelStaysPut() throws {
        let off = try XCTUnwrap(stack(width: wide).ribbonButtons.last)
        let on = try XCTUnwrap(stack(width: wide, clarity: true).ribbonButtons.last)
        XCTAssertEqual([off.title, on.title], ["Clarity", "Clarity"])
        XCTAssertEqual(off.font, on.font, "same weight both ways")
        XCTAssertEqual(off.contentTintColor, Palette.inkSoft)
        XCTAssertEqual(on.contentTintColor, Palette.accent)
        XCTAssertEqual(off.accessibilityValue() as? String, "off")
        XCTAssertEqual(on.accessibilityValue() as? String, "on")
        XCTAssertEqual(off.toolTip, "Clarity is off: click to collapse every card")
        XCTAssertEqual(on.toolTip, "Clarity is on: click to expand every card")
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
        let hidden = stack(width: wide, .hideAll)
        XCTAssertEqual(hidden.toggle.toolTip, "Show all", "under Hide all it shows them again")
        try XCTUnwrap(hidden.toggle as? NSButton).performClick(nil)
        XCTAssertEqual(hidden.toggled(), 1, "one click toggles")
    }

    func testTheBadgeIsInTheCardsBottomRightUnlessHideAllRemovedTheCard() {
        let shown = stack(width: wide)
        XCTAssertGreaterThan(shown.badge.frame.midX, shown.view.bounds.midX, "on the right")
        XCTAssertLessThan(shown.badge.frame.maxY, shown.toggle.frame.minY, "below the ribbon, in the card area")
        XCTAssertLessThan(shown.badge.frame.minY, shown.view.bounds.height * 0.2, "near the bottom")
        let hidden = stack(width: wide, .hideAll)
        XCTAssertEqual(hidden.badge.frame.midY, hidden.toggle.frame.midY, accuracy: 2, "in the ribbon")
        XCTAssertLessThanOrEqual(hidden.badge.frame.maxX, hidden.toggle.frame.minX, "left of the toggle")
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
            XCTAssertEqual(with.toggle.frame, without.toggle.frame, "the toggle stays put")
            XCTAssertEqual(with.menu.frame, without.menu.frame, "and so does the menu button")
            XCTAssertEqual(with.toolbar.frame, without.toolbar.frame, "and the toolbar")
            let label = with.desktopFull.frame
            let rightEdge = visibility == .all ? with.toggle.frame.minX : with.badge.frame.minX
            XCTAssertGreaterThanOrEqual(label.minX, with.toolbar.frame.maxX, "the label stays right of the toolbar")
            XCTAssertLessThanOrEqual(label.maxX, rightEdge, "and left of what is at its right")
        }
    }

    func testTheRibbonOnlyBadgeGivesWayRatherThanCoverTheToolbar() {
        let wideRibbon = stack(width: wide, .hideAll)
        XCTAssertFalse(wideRibbon.badge.isHidden, "with room the count shows beside the toggle")
        let narrowRibbon = stack(width: belowAnyCell, .hideAll)
        XCTAssertTrue(narrowRibbon.badge.isHidden, "without room it goes instead of covering the Clarity button")
        XCTAssertGreaterThan(narrowRibbon.toggle.frame.minX, narrowRibbon.toolbar.frame.maxX, "and the buttons stay apart")
    }
}
