import XCTest
@testable import Ideator

/// What Settings says, apart from the window that shows it.
final class SettingsCopyTests: XCTestCase {
    func testTheSectionsAreSixInTheSidebarOrderAndTheWindowOpensOnTheFirst() {
        XCTAssertEqual(SettingsSection.allCases.map(\.title), ["Shortcut", "Spread", "AI Summary", "MCP", "Updates", "Privacy"])
        XCTAssertEqual(SettingsSection.opening, .shortcut)
        XCTAssertEqual(SettingsSection.allCases.map(\.rawValue), Array(0..<6), "the position in the list is the raw value")
    }

    func testEverySectionButPrivacyOpensWithALeadAndPrivacyLetsItsCardOpen() {
        for section in SettingsSection.allCases where section != .privacy {
            XCTAssertFalse(try XCTUnwrap(section.lead, section.title).isEmpty, section.title)
        }
        XCTAssertNil(SettingsSection.privacy.lead)
        XCTAssertEqual(SettingsSection.shortcut.lead, "Hides or shows every card, from any app.")
        XCTAssertTrue(try XCTUnwrap(SettingsSection.mcp.lead).hasSuffix("through MCP, a standard way for AI tools to reach apps."),
                      "jargon is explained once, where it first appears")
    }

    func testAStatusSpeaksItsPrefixThenItsTextAndANeutralOneOnlyItsText() {
        XCTAssertEqual(SettingsStatus.success("A key is saved.").spoken, "Done: A key is saved.")
        XCTAssertEqual(SettingsStatus.warning("macOS also has it.").spoken, "Warning: macOS also has it.")
        XCTAssertEqual(SettingsStatus.error("Not registered.").spoken, "Error: Not registered.")
        XCTAssertEqual(SettingsStatus.neutral("No key saved.").spoken, "No key saved.")
    }

    func testAStatusShowsAGlyphUnlessItIsNeutral() {
        XCTAssertNil(SettingsStatus.Kind.neutral.glyph)
        XCTAssertEqual([SettingsStatus.Kind.success, .warning, .error].compactMap(\.glyph),
                       ["checkmark.circle", "exclamationmark.triangle", "xmark.octagon"])
    }

    private func shortcut(problem: HotKey.Problem? = nil, usedByMacOS: Bool = false, rejected: String? = nil) -> SettingsStatus? {
        SettingsCopy.Shortcut.status(shortcut: .standard, problem: problem, usedByMacOS: usedByMacOS, rejected: rejected)
    }

    func testTheShortcutStatusSaysTheLastVerdictFirstThenWhyThereIsNoShortcutThenTheMacOSNoteElseNothing() {
        XCTAssertEqual(shortcut(problem: .taken, usedByMacOS: true, rejected: "⌘K can't be the shortcut."),
                       .error("⌘K can't be the shortcut."))
        XCTAssertEqual(shortcut(problem: .taken, usedByMacOS: true),
                       .error("⌃⌥I is already taken. There is no shortcut until you pick another."))
        XCTAssertEqual(shortcut(problem: .refused(-9879)),
                       .error("macOS refused ⌃⌥I (error -9879). There is no shortcut until you pick another."))
        XCTAssertEqual(shortcut(usedByMacOS: true)?.kind, .warning)
        XCTAssertTrue(shortcut(usedByMacOS: true)?.text.hasPrefix("macOS also has a shortcut on ⌃⌥I") == true)
        XCTAssertNil(shortcut(), "the caption above already says what to do")
    }

    func testARefusedCombinationNamesTheShortcutStillInUse() {
        let text = SettingsCopy.Shortcut.rejection(.taken, wanted: .standard, kept: .standard)
        XCTAssertEqual(text, "⌃⌥I is already taken. Still using ⌃⌥I.")
    }

    func testTheSpreadStatusSaysSoOnlyWhileNoCellIsTicked() {
        XCTAssertEqual(SettingsCopy.Spread.status(cells: .empty),
                       .neutral("No cell is ticked, so Spread makes no card. Tick the cells it should fill."))
        XCTAssertNil(SettingsCopy.Spread.status(cells: .standard))
    }

    func testTheKeyStatusSaysWhoseKeyIsSavedAndWhereItIsHeld() {
        let replace = "Paste a new one to replace it."
        func status(_ provider: Provider?, inKeychain: Bool, refused: Bool = false) -> SettingsStatus {
            SettingsCopy.AISummary.status(provider: provider, inKeychain: inKeychain, keychainRefused: refused)
        }
        XCTAssertEqual(status(nil, inKeychain: true),
                       .neutral("No key saved. Ideator works without one; collapsed cards show “Summary unavailable”."))
        XCTAssertEqual(status(.anthropic, inKeychain: true), .success("An Anthropic key is saved in your Keychain. \(replace)"))
        XCTAssertEqual(status(.openAI, inKeychain: true), .success("An OpenAI key is saved in your Keychain. \(replace)"))
        XCTAssertEqual(status(.openAI, inKeychain: false), .success("An OpenAI key is held for this run only. \(replace)"))
        XCTAssertEqual(status(.anthropic, inKeychain: false), .success("An Anthropic key is held for this run only. \(replace)"))
    }

    func testAKeychainRefusalIsAnErrorThatStillSaysWhetherAKeyIsSaved() {
        let refused = SettingsCopy.AISummary.status(provider: .anthropic, inKeychain: true, keychainRefused: true)
        XCTAssertEqual(refused, .error("The Keychain refused the change. An Anthropic key is saved in your Keychain. "
                                       + "Paste a new one to replace it."))
        let none = SettingsCopy.AISummary.status(provider: nil, inKeychain: true, keychainRefused: true)
        XCTAssertEqual(none.kind, .error)
        XCTAssertTrue(none.text.hasPrefix("The Keychain refused the change. No key saved."))
    }

    func testTheConnectLineIsAWarningFromATemporaryPlaceASuccessAfterACopyElseTheCaptionShows() {
        XCTAssertEqual(SettingsCopy.MCP.connectStatus(isTemporary: true, copied: .codex)?.kind, .warning,
                       "a copy is not offered from there, so the move comes first")
        XCTAssertTrue(SettingsCopy.MCP.connectStatus(isTemporary: true, copied: nil)?.text
            .hasSuffix("Move Ideator to Applications, open it from there, then copy a setup.") == true)
        XCTAssertEqual(SettingsCopy.MCP.connectStatus(isTemporary: false, copied: .codex),
                       .success("Copied for Codex. \(AITool.codex.pasteNote)"))
        XCTAssertNil(SettingsCopy.MCP.connectStatus(isTemporary: false, copied: nil))
    }

    func testTheInstructionLineIsAnErrorOnlyAfterARefusedEdit() {
        XCTAssertEqual(SettingsCopy.MCP.instructionStatus(refused: true),
                       .error("That change would pass the 100 KB limit, so Ideator did not make it."))
        XCTAssertNil(SettingsCopy.MCP.instructionStatus(refused: false))
        XCTAssertEqual(SettingsCopy.MCP.copyLabel(for: .claudeDesktop), "Copy setup for Claude Desktop")
    }

    func testTheUpdatesLineSaysWhyARunDoesNotCheckAndNothingWhileItDoes() throws {
        let release = BuildInfo(info: ["CFBundleShortVersionString": "0.9", "CFBundleVersion": "57",
                                       "IdeatorCommit": "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d", "IdeatorTreeDirty": "NO",
                                       "SUFeedURL": "https://github.com/XingzhiC-starlight/ideator/releases/latest/download/appcast.xml",
                                       "SUPublicEDKey": "aU79Ryz97RGp9XiQfDRmXkV4198Z8g6cp+8nhrIpaJ4="])
        let xcode = BuildInfo(info: ["CFBundleShortVersionString": "0.9", "CFBundleVersion": "1",
                                     "IdeatorCommit": "none", "IdeatorTreeDirty": "unknown"])

        XCTAssertNil(SettingsCopy.Updates.status(plan: release.plan(isScratch: false)))
        XCTAssertEqual(SettingsCopy.Updates.asksBeforeInstalling, "Ideator asks before it installs an update.")
        XCTAssertEqual(SettingsCopy.Updates.status(plan: release.plan(isScratch: true)),
                       .neutral("A scratch run (-CardsFolder) doesn't check for updates."))
        XCTAssertEqual(SettingsCopy.Updates.status(plan: xcode.plan(isScratch: false)),
                       .neutral("Only builds made by scripts/package.sh check for updates."))
        XCTAssertEqual(release.versionLine, "Version 0.9 (57), commit 1a2b3c4", "the line the pane shows on its own")
    }

    func testThePrivacyCardOpensWithTheTwoThingsThatLeaveTheMacThenListsEachWithItsTerm() {
        let card = SettingsCopy.Privacy.card(for: nil)

        XCTAssertEqual(card.headline, "Two things leave your Mac. Nothing else does.")
        XCTAssertEqual(card.items.map(\.term), ["Card text", "Update checks", "Your key", "Nothing else"])
        XCTAssertEqual(card.items.last?.text, "No analytics, no crash reports.")
    }

    func testThePrivacyCardNamesTheSavedKeysCompanyAndBothWhenThereIsNoKey() {
        func cardText(_ provider: Provider?) -> String { SettingsCopy.Privacy.card(for: provider).items[0].text }

        XCTAssertTrue(cardText(.anthropic).contains("sends a card's text to Anthropic, using your own key"), "what, to whom, whose key")
        XCTAssertTrue(cardText(.openAI).contains("sends a card's text to OpenAI, using your own key"))
        XCTAssertTrue(cardText(nil).contains("sends a card's text to Anthropic or OpenAI, whichever your key is for, using your own key"))
        XCTAssertFalse(SettingsCopy.Privacy.card(for: .anthropic).allText.contains("OpenAI"), "a saved key names its company alone")
        XCTAssertFalse(SettingsCopy.Privacy.card(for: .openAI).allText.contains("Anthropic"))
    }

    func testThePrivacyCardSaysWhenACardIsSentAgainAndWhatTheDailyCheckSends() {
        for provider in [Provider.anthropic, .openAI, nil] {
            let card = SettingsCopy.Privacy.card(for: provider)
            let text = card.allText
            XCTAssertTrue(text.contains("whenever a card has no summary for its text as it is now"), "the rule")
            XCTAssertTrue(text.contains("when you save a key"), "every card without a summary goes at once")
            XCTAssertTrue(text.contains("at launch after a failed try"), "a failure is never saved")
            XCTAssertTrue(text.contains("after an update that changes how Ideator asks for summaries"), "every card, once")
            XCTAssertTrue(text.contains("login Keychain"), "where the key stays")
            XCTAssertTrue(card.items[1].text.hasPrefix("Once a day while automatic checks are on, and whenever you click Check Now, "
                                                       + "Ideator asks GitHub whether a newer version exists."))
            XCTAssertTrue(text.contains("GitHub sees your IP address and which version you have"))
            XCTAssertTrue(text.hasSuffix("No analytics, no crash reports."), "the promise comes after both services")
        }
    }
}
