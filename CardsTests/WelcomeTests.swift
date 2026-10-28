import XCTest
import Carbon.HIToolbox
@testable import Ideator

final class WelcomeTests: XCTestCase {
    private func copy(shortcutWorks: Bool = true, shortcut: Shortcut = .standard) -> WelcomeCopy {
        WelcomeCopy(shortcut: shortcut, shortcutWorks: shortcutWorks)
    }

    func testTheCopyNamesTheCurrentShortcutAndTheDefaultFolder() {
        let f13 = Shortcut(keyCode: UInt32(kVK_F13), modifiers: UInt32(controlKey | cmdKey))!
        let text = copy(shortcut: f13).paragraphs.map { $0.lead + " " + $0.text }.joined(separator: "\n")

        XCTAssertTrue(text.contains("Press ⌃⌘F13 from any app"), "the user's shortcut, not a literal")
        XCTAssertTrue(text.contains("~/Documents/Ideator"))
        XCTAssertTrue(text.contains("Choose Allow."), "the Documents prompt is announced")
    }

    func testTheCopyDoesNotPromiseAShortcutThatFailed() {
        let text = copy(shortcutWorks: false).paragraphs.map(\.text).joined(separator: "\n")

        XCTAssertTrue(text.contains("Ideator couldn't claim ⌃⌥I, so there is no shortcut yet."))
        XCTAssertFalse(text.contains("Press ⌃⌥I"))
    }

    func testTheCopyAnnouncesTheDailyCheckWithGitHubAndPromisesNothingElseLeavesAfterBothServices() throws {
        let paragraphs = copy().paragraphs
        let text = paragraphs.map { $0.lead + " " + $0.text }.joined(separator: "\n")

        XCTAssertTrue(text.contains("Only a card's text goes to that company."))
        XCTAssertTrue(text.contains("Once a day Ideator asks GitHub whether a newer version exists, and it asks you before it installs one."))
        XCTAssertTrue(text.contains("You can turn the daily check off in Settings."))
        XCTAssertTrue(try XCTUnwrap(paragraphs.last).text.hasSuffix("Nothing else leaves your Mac."))
        XCTAssertEqual(text.components(separatedBy: "Nothing else leaves your Mac").count, 2, "said once, last")
    }

    func testTheVersionIsRaisedWithTheParagraphsThatSayWhatLeavesTheMac() {
        let disclosed = copy().paragraphs
            .filter { ["Summaries are optional.", "Updates come from GitHub."].contains($0.lead) }.map(\.text)

        XCTAssertEqual(WelcomeCopy.version, 3)
        XCTAssertEqual(disclosed, [
            "To show a short summary when you collapse a card, add your own Anthropic or OpenAI API key in Settings. "
                + "Ideator then sends a card's text to Anthropic or OpenAI, whichever your key is for, whenever the card "
                + "has no summary for its text as it is now, such as when you save the key or change the card. "
                + "Only a card's text goes to that company.",
            "Once a day Ideator asks GitHub whether a newer version exists, and it asks you before it "
                + "installs one. You can turn the daily check off in Settings. Nothing else leaves your Mac.",
        ], "These paragraphs are what an owner agreed to. If they now say something else, raise "
            + "WelcomeCopy.version and the number above together, so a Mac that saw the old card sees this one.")
    }

    func testTheCopyAndSettingsSayWhenACardIsSentInTheSameWordsAndNameBothCompanies() {
        let rule = "whenever the card has no summary for its text as it is now"
        let summaries = copy().paragraphs.first { $0.lead == "Summaries are optional." }

        XCTAssertTrue(summaries?.text.contains(rule) == true)
        XCTAssertTrue(summaries?.text.contains("Anthropic or OpenAI API key") == true)
        XCTAssertTrue(SettingsWindow.privacy(for: nil).contains(rule))
    }

    func testTheCardFitsItsCopyAtTheStackWidth() {
        let window = WelcomeWindow(copy: copy()) {}

        let size = window.fit(width: 342)
        window.contentView?.layoutSubtreeIfNeeded()

        let content = window.contentView!
        XCTAssertEqual(content.frame.size, size, accuracy: 0.5)
        XCTAssertLessThan(size.height, NSScreen.screens.first?.visibleFrame.height ?? 800)
        for view in descendants(of: content) where view is NSTextField || view is NSButton {
            let frame = content.convert(view.bounds, from: view)
            XCTAssertTrue(content.bounds.contains(frame), "\(type(of: view)) sits inside the card, not clipped: \(frame)")
        }
    }

    func testContinueRunsTheHandlerForTheButtonAndForReturn() {
        var continued = 0
        let window = WelcomeWindow(copy: copy()) { continued += 1 }
        window.fit(width: 342)

        window.continueButton.performClick(nil)
        XCTAssertEqual(continued, 1)

        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false,
                                         keyCode: UInt16(kVK_Return))!
        XCTAssertTrue(window.performKeyEquivalent(with: returnKey))
        XCTAssertEqual(continued, 2)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}

private func XCTAssertEqual(_ a: NSSize, _ b: NSSize, accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.width, b.width, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(a.height, b.height, accuracy: accuracy, file: file, line: line)
}
