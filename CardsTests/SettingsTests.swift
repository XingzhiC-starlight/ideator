import XCTest
@testable import Ideator

final class SettingsTests: XCTestCase {
    private func caption(problem: HotKey.Problem? = nil, usedByMacOS: Bool = false, rejected: String? = nil) -> String {
        SettingsWindow.shortcutCaption(shortcut: .standard, problem: problem, usedByMacOS: usedByMacOS,
                                       rejected: rejected)
    }

    func testTheShortcutCaptionSaysTheLastVerdictFirstThenWhyThereIsNoShortcutThenTheMacOSNote() {
        XCTAssertEqual(caption(problem: .taken, usedByMacOS: true, rejected: "⌘K can't be the shortcut."),
                       "⌘K can't be the shortcut.")
        XCTAssertEqual(caption(problem: .taken, usedByMacOS: true),
                       "⌃⌥Space is already taken. There is no shortcut until you pick another.")
        XCTAssertEqual(caption(problem: .refused(-9879)),
                       "macOS refused ⌃⌥Space (error -9879). There is no shortcut until you pick another.")
        XCTAssertTrue(caption(usedByMacOS: true).hasPrefix("macOS also has a shortcut on ⌃⌥Space"))
        XCTAssertEqual(caption(), "Hides or shows every card, from any app. Click it, then press the new keys.")
    }

    func testThePrivacyLineSaysWhatIsSentAndThatNothingElseLeaves() {
        let line = SettingsWindow.privacy
        XCTAssertTrue(line.contains("sends a card's text to Anthropic"), "what is sent, and to whom")
        XCTAssertTrue(line.contains("using your own key"))
        XCTAssertTrue(line.contains("Nothing else leaves your Mac"))
        XCTAssertTrue(line.contains("no analytics, no crash reports"))
        XCTAssertTrue(line.contains("login Keychain"), "where the key stays")
    }

    func testTheShortcutFieldShowsThatItIsRecordingEvenWhenTheHandlerRefreshesTheShortcut() {
        let field = ShortcutField()
        field.shortcut = .standard
        field.onRecordingChange = { [unowned field] _ in field.shortcut = .standard }

        field.performClick(nil)
        XCTAssertEqual(field.title, "Type shortcut…")

        field.cancelRecording()
        XCTAssertEqual(field.title, Shortcut.standard.display)
    }
}
