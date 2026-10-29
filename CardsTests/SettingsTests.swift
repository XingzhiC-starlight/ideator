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

    func testThePrivacyLineNamesTheSavedKeysCompanyAndBothWhenThereIsNoKey() {
        XCTAssertTrue(SettingsWindow.privacy(for: .anthropic).contains("sends a card's text to Anthropic, using your own key"),
                      "what, to whom, whose key")
        XCTAssertTrue(SettingsWindow.privacy(for: .openAI).contains("sends a card's text to OpenAI, using your own key"))
        XCTAssertTrue(SettingsWindow.privacy(for: nil).contains(
            "sends a card's text to Anthropic or OpenAI, whichever your key is for, using your own key"))
        XCTAssertFalse(SettingsWindow.privacy(for: .anthropic).contains("OpenAI"), "a saved key names its company alone")
        XCTAssertFalse(SettingsWindow.privacy(for: .openAI).contains("Anthropic"))
    }

    func testThePrivacyLineNamesTheServicesAndWhatEachGetsThenPromisesNothingElseLeaves() {
        for provider in [Provider.anthropic, .openAI, nil] {
            let line = SettingsWindow.privacy(for: provider)
            XCTAssertTrue(line.contains("login Keychain"), "where the key stays")
            XCTAssertTrue(line.contains("whenever you click Check Now, Ideator asks GitHub whether a newer version exists"))
            XCTAssertTrue(line.contains("GitHub sees your IP address and which version you have"))
            XCTAssertTrue(line.hasSuffix("Nothing else leaves your Mac: no analytics, no crash reports."),
                          "the promise comes after both services")
        }
    }

    func testThePrivacyLineSaysWhenACardIsSentAgainAndNotThatItIsSentOnce() {
        for provider in [Provider.anthropic, .openAI, nil] {
            let line = SettingsWindow.privacy(for: provider)
            XCTAssertTrue(line.contains("whenever the card has no summary for its text as it is now"), "the rule")
            XCTAssertTrue(line.contains("when you save a key"), "every card without a summary goes at once")
            XCTAssertTrue(line.contains("at launch after a failed try"), "a failure is never saved")
            XCTAssertTrue(line.contains("after an update that changes how Ideator asks for summaries"), "every card, once")
        }
    }

    func testTheKeyLineSaysWhoseKeyIsSavedAndWhereItIsHeld() {
        let replace = "Paste a new one to replace it."
        XCTAssertEqual(SettingsWindow.keyStatus(provider: nil, inKeychain: true),
                       "No key saved. Ideator works without one; collapsed cards show “Summary unavailable”.")
        XCTAssertEqual(SettingsWindow.keyStatus(provider: .anthropic, inKeychain: true), "An Anthropic key is saved in your Keychain. \(replace)")
        XCTAssertEqual(SettingsWindow.keyStatus(provider: .openAI, inKeychain: true), "An OpenAI key is saved in your Keychain. \(replace)")
        XCTAssertEqual(SettingsWindow.keyStatus(provider: .openAI, inKeychain: false), "An OpenAI key is held for this run only. \(replace)")
        XCTAssertEqual(SettingsWindow.keyStatus(provider: .anthropic, inKeychain: false), "An Anthropic key is held for this run only. \(replace)")
    }

    func testTheKeyStoreSaysWhoseKeyItHolds() {
        let keys = KeyStore(inKeychain: false)
        XCTAssertNil(keys.provider)

        keys.set("sk-ant-test")
        XCTAssertEqual(keys.provider, .anthropic)

        keys.set("  sk-proj-test\n")
        XCTAssertEqual(keys.provider, .openAI, "the other company's key replaces it, trimmed")
        XCTAssertEqual(keys.apiKey, "sk-proj-test")

        keys.set(nil)
        XCTAssertNil(keys.provider)
    }

    func testSavingAndRemovingKeysMovesTheKeyLineAndThePrivacyLineTogether() async throws {
        var changes = 0
        let window = settings(keys: KeyStore(inKeychain: false)) { changes += 1 }
        let content = try XCTUnwrap(window.contentView)
        let field = try XCTUnwrap(descendants(of: content).compactMap { $0 as? NSSecureTextField }.first)
        XCTAssertTrue(texts(in: window).contains("API key (Anthropic or OpenAI)"), "the heading says either company works")
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("With a key saved, Ideator sends a card's text to Anthropic or OpenAI, whichever your key is for") })

        field.stringValue = "sk-proj-test"
        try button("Save", in: window).performClick(nil)
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("An OpenAI key is held for this run only") })
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("With a key saved, Ideator sends a card's text to OpenAI, using your own key") })

        field.stringValue = "sk-ant-test"
        try button("Save", in: window).performClick(nil)
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("An Anthropic key is held for this run only") })
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("With a key saved, Ideator sends a card's text to Anthropic, using your own key") })

        try button("Remove Key", in: window).performClick(nil)
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("No key saved") })
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("With a key saved, Ideator sends a card's text to Anthropic or OpenAI") })
        XCTAssertEqual(changes, 3, "each save and the removal tell the controller, so failed summaries retry under the new key")
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

    func testRemoveKeyKeepsTheKeyAndTellsNobodyWhenTheKeychainRefuses() async throws {
        let keys = RefusableKeyStore()
        keys.set("sk-ant-test")
        var changes = 0
        let window = settings(keys: keys) { changes += 1 }

        keys.refuses = true
        try button("Remove Key", in: window).performClick(nil)

        XCTAssertEqual(keys.apiKey, "sk-ant-test", "the key is still saved, so it still sends")
        XCTAssertEqual(changes, 0, "the summarizer must not be told the key is gone")
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("An Anthropic key is held") }, "the status line still says a key is saved")
        XCTAssertFalse(texts(in: window).contains { $0.hasPrefix("No key saved") })
    }

    func testRemoveKeyDeletesTheKeyAndTellsTheControllerOnce() async throws {
        let keys = RefusableKeyStore()
        keys.set("sk-ant-test")
        var changes = 0
        let window = settings(keys: keys) { changes += 1 }

        try button("Remove Key", in: window).performClick(nil)

        XCTAssertNil(keys.apiKey)
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(texts(in: window).contains { $0.hasPrefix("No key saved") })
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

    private func settings(keys: KeyStore, onChange: @escaping () -> Void) -> SettingsWindow {
        SettingsWindow(keys: keys, hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                       updates: Updates(build: .current, isScratch: false), onChange: onChange)
    }

    private func button(_ title: String, in window: SettingsWindow) throws -> NSButton {
        let buttons = descendants(of: try XCTUnwrap(window.contentView)).compactMap { $0 as? NSButton }
        return try XCTUnwrap(buttons.first { $0.title == title }, title)
    }

    private func texts(in window: SettingsWindow) -> [String] {
        descendants(of: window.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}

private final class RefusableKeyStore: KeyStore {
    var refuses = false

    init() { super.init(inKeychain: false) }

    @discardableResult
    override func set(_ key: String?) -> Bool { refuses ? false : super.set(key) }
}
