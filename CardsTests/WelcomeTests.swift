import XCTest
import Carbon.HIToolbox
@testable import Ideator

final class WelcomeTests: XCTestCase {
    private let copy = WelcomeCopy()

    private func window(_ kind: WelcomeKind = .fullTour, choose: @escaping (WelcomeChoice) -> Void = { _ in }) -> WelcomeWindow {
        WelcomeWindow(copy: copy, kind: kind, choose: choose)
    }

    private var text: String { ([copy.intro] + copy.disclosures.map { $0.lead + " " + $0.text }).joined(separator: "\n") }

    func testTheCopyNamesTheDefaultFolderAndAnnouncesTheDocumentsPrompt() {
        XCTAssertTrue(text.contains("~/Documents/Ideator"))
        XCTAssertTrue(text.contains("Choose Allow."), "the Documents prompt comes right after the button")
    }

    func testTheVersionStaysWithTheParagraphsThatSayWhatLeavesTheMac() {
        let disclosed = copy.disclosures.filter { ["Updates come from GitHub.", "AI is optional."].contains($0.lead) }.map(\.text)

        XCTAssertEqual(WelcomeCopy.version, 3)
        XCTAssertEqual(disclosed, [
            "Once a day Ideator asks GitHub whether a newer version exists, and asks you before installing. "
                + "Turn the check off in Settings.",
            "Summaries need your own API key in Settings. Only then does a card's text "
                + "leave your Mac.",
        ], "These paragraphs are what an owner agreed to. If they now say something else, raise "
            + "WelcomeCopy.version and the number above together, so a Mac that saw the old card sees this one.")
    }

    func testTheWelcomeIsAsLargeAsThePrototypesAndEverythingFitsInside() {
        for kind in [WelcomeKind.fullTour, .noTour] {
            let window = window(kind)

            let size = window.fit(width: 446)
            window.contentView?.layoutSubtreeIfNeeded()

            XCTAssertEqual(size, NSSize(width: 446, height: 326),
                           "the prototype's welcome measures 440 × 338 visible; its AI paragraph had a third line, "
                               + "cut when the sentence about Claude Code cards (they need no key) went")
            let content = window.contentView!
            XCTAssertEqual(content.frame.size, size)
            let face = content.bounds.insetBy(dx: CardShape.gap + 1, dy: CardShape.gap + 1)
            for view in descendants(of: content) where !view.isHidden && (view is TourText || view is NSControl) {
                let frame = (view as? TourText).map { content.convert($0.textFrame, from: $0.superview) }
                    ?? content.convert(view.bounds, from: view)
                XCTAssertTrue(face.contains(frame), "\(type(of: view)) sits inside the face: \(frame)")
            }
        }
    }

    func testTheFullTourOffersStartAndSkipAndReturnStarts() {
        var choices: [WelcomeChoice] = []
        let window = window(.fullTour) { choices.append($0) }
        window.fit(width: 446)

        XCTAssertEqual(window.defaultButton.title, "Start the tour")
        XCTAssertEqual(window.skipButton?.title, "Skip the tour")
        window.skipButton?.performClick(nil)
        window.defaultButton.performClick(nil)
        XCTAssertTrue(window.performKeyEquivalent(with: returnKey(for: window)))
        XCTAssertEqual(choices, [.skip, .start, .start])
    }

    func testTheOtherKindsOfferContinueAlone() {
        for kind in [WelcomeKind.endOnly, .noTour] {
            var choices: [WelcomeChoice] = []
            let window = window(kind) { choices.append($0) }
            window.fit(width: 446)
            window.contentView?.layoutSubtreeIfNeeded()

            XCTAssertEqual(window.defaultButton.title, "Continue")
            XCTAssertNil(window.skipButton)
            XCTAssertEqual(descendants(of: window.contentView!).compactMap { $0 as? NSButton }.map(\.title), ["Continue"])
            XCTAssertTrue(window.performKeyEquivalent(with: returnKey(for: window)))
            XCTAssertEqual(choices, [.proceed])
        }
    }

    func testTheWelcomeIsCenteredOnTheMenuBarScreenAndFloatsOnlyWhenAsked() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).frame
        let atLaunch = window()
        defer { atLaunch.close() }

        atLaunch.present(takingFocus: false, floating: false)

        XCTAssertEqual(atLaunch.frame.midX, screen.midX, accuracy: 1)
        let face = atLaunch.frame.insetBy(dx: CardShape.gap, dy: CardShape.gap)
        XCTAssertEqual(screen.maxY - face.maxY, screen.height / 2 - 0.52 * face.height, accuracy: 1,
                       "a little above the middle, as the prototype's translate(-50%, -52%)")
        XCTAssertEqual(atLaunch.level, .normal)

        let again = window()
        defer { again.close() }
        again.present(takingFocus: false, floating: true)
        XCTAssertEqual(again.level, .floating, "shown again over cards that keep reordering")
    }

    func testABackgroundStartShowsTheWelcomeWithoutTakingTheKeyWindow() {
        let window = window(.endOnly)
        defer { window.close() }
        let keyBefore = NSApp.keyWindow

        window.present(takingFocus: false, floating: false)

        XCTAssertTrue(window.isVisible, "the welcome still shows")
        XCTAssertFalse(window.isKeyWindow, "so a Return typed in the AI tool can never press Continue")
        XCTAssertTrue(NSApp.keyWindow === keyBefore)
    }

    func testOnlyAStartByTheHelperShowsTheWelcomeWithoutFocus() {
        let byHelper = Launch(arguments: [:], build: BuildInfo(info: [:]), environment: [HandOff.backgroundVariable: "1"])
        let byUser = Launch(arguments: [:], build: BuildInfo(info: [:]), environment: [:])
        XCTAssertFalse(byHelper.welcomeTakesFocus)
        XCTAssertTrue(byUser.welcomeTakesFocus)
    }

    private func returnKey(for window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
                         keyCode: UInt16(kVK_Return))!
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}
