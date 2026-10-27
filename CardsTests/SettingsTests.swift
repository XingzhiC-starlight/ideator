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
                       "⌃⌥I is already taken. There is no shortcut until you pick another.")
        XCTAssertEqual(caption(problem: .refused(-9879)),
                       "macOS refused ⌃⌥I (error -9879). There is no shortcut until you pick another.")
        XCTAssertTrue(caption(usedByMacOS: true).hasPrefix("macOS also has a shortcut on ⌃⌥I"))
        XCTAssertEqual(caption(), "Hides or shows every card, from any app. Click it, then press the new keys.")
    }

    func testThePrivacyLineNamesBothServicesAndWhatEachGetsThenPromisesNothingElseLeaves() {
        let line = SettingsWindow.privacy
        XCTAssertTrue(line.contains("sends a card's text to Anthropic, using your own key"), "what, to whom, whose key")
        XCTAssertTrue(line.contains("login Keychain"), "where the key stays")
        XCTAssertTrue(line.contains("whenever you click Check Now, Ideator asks GitHub whether a newer version exists"))
        XCTAssertTrue(line.contains("GitHub sees your IP address and which version you have"))
        XCTAssertTrue(line.hasSuffix("Nothing else leaves your Mac: no analytics, no crash reports."),
                      "the promise comes after both services")
    }

    func testTheUpdatesCaptionFollowsTheVersionLineWithWhetherThisRunChecks() {
        let release = BuildInfo(info: ["CFBundleShortVersionString": "0.9", "CFBundleVersion": "57",
                                       "IdeatorCommit": "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d", "IdeatorTreeDirty": "NO",
                                       "SUFeedURL": "https://github.com/XingzhiC-starlight/ideator/releases/latest/download/appcast.xml",
                                       "SUPublicEDKey": "aU79Ryz97RGp9XiQfDRmXkV4198Z8g6cp+8nhrIpaJ4="])
        let xcode = BuildInfo(info: ["CFBundleShortVersionString": "0.9", "CFBundleVersion": "1",
                                     "IdeatorCommit": "none", "IdeatorTreeDirty": "unknown"])

        XCTAssertEqual(SettingsWindow.updatesCaption(build: release, plan: release.plan(isScratch: false)),
                       "Version 0.9 (57), commit 1a2b3c4. Ideator asks before it installs an update.")
        XCTAssertEqual(SettingsWindow.updatesCaption(build: release, plan: release.plan(isScratch: true)),
                       "Version 0.9 (57), commit 1a2b3c4. A scratch run (-CardsFolder) doesn't check for updates.")
        XCTAssertEqual(SettingsWindow.updatesCaption(build: xcode, plan: xcode.plan(isScratch: false)),
                       "Version 0.9 (1), a development build. Only builds made by scripts/package.sh check for updates.")
    }

    func testABuildThatNeverChecksDimsTheUpdateControlsAndTheMenuItem() throws {
        let updates = Updates(build: .current, isScratch: false)
        XCTAssertEqual(updates.plan, .off(.notPackaged), "the test host is a Debug build, which package.sh did not stamp")
        let window = SettingsWindow(keys: KeyStore(inKeychain: false), hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                                    updates: updates) {}
        let buttons = descendants(of: try XCTUnwrap(window.contentView)).compactMap { $0 as? NSButton }

        let autoCheck = try XCTUnwrap(buttons.first { $0.title == "Check for updates automatically" })
        let checkNow = try XCTUnwrap(buttons.first { $0.title == "Check Now" })
        XCTAssertFalse(autoCheck.isEnabled)
        XCTAssertEqual(autoCheck.state, .off)
        XCTAssertFalse(checkNow.isEnabled)
        XCTAssertFalse(updates.canCheck, "Check for Updates… is validated by canCheck")
        XCTAssertEqual(updates.menuTitle, "Check for Updates…")
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

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}
