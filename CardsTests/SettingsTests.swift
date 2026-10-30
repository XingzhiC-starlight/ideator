import XCTest
@testable import Ideator

final class SettingsTests: XCTestCase {
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

    func testTheWindowIsAFixedSixHundredFortySquareWithItsTitleHidden() {
        let window = settings()
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, NSSize(width: 640, height: 640))
        XCTAssertEqual(window.contentView?.frame.size, NSSize(width: 640, height: 640), "nothing inside pulls it smaller")
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertEqual(window.title, "Ideator Settings", "VoiceOver still reads it")
        XCTAssertEqual(window.titleVisibility, .hidden)
    }

    func testTheSidebarListsTheSixSectionsAndTheWindowOpensOnShortcut() throws {
        let window = settings()
        let table = try XCTUnwrap(descendants(of: window.contentView!).compactMap { $0 as? NSTableView }.first)

        XCTAssertEqual(table.accessibilityLabel(), "Settings sections")
        let rows = (0..<table.numberOfRows).map { table.view(atColumn: 0, row: $0, makeIfNecessary: true)?.accessibilityLabel() }
        XCTAssertEqual(rows, ["Shortcut", "Spread", "AI Summary", "MCP", "Updates", "Privacy"])
        XCTAssertEqual(table.selectedRow, 0)
        XCTAssertEqual(shown(in: window), [.shortcut])
    }

    func testPickingASectionShowsItsPaneAloneAndFromItsTop() throws {
        let window = settings()

        window.select(.updates)

        XCTAssertEqual(shown(in: window), [.updates])
        let table = try XCTUnwrap(descendants(of: window.contentView!).compactMap { $0 as? NSTableView }.first)
        XCTAssertEqual(table.selectedRow, SettingsSection.updates.rawValue)
        XCTAssertEqual(window.pane(.updates).enclosingScrollView?.contentView.bounds.minY, 0)
    }

    func testClosingTheWindowBringsItBackOnShortcut() {
        let window = settings()
        window.select(.mcp)
        window.becomeKey()
        XCTAssertEqual(shown(in: window), [.mcp], "the section stays while the window is open")

        window.close()
        window.becomeKey()

        XCTAssertEqual(window.selected, .shortcut)
        XCTAssertEqual(shown(in: window), [.shortcut])
    }

    func testCommandWClosesTheWindow() throws {
        let window = settings()
        window.select(.privacy)
        window.orderFront(nil)
        let commandW = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                      windowNumber: window.windowNumber, context: nil, characters: "w",
                                                      charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))

        XCTAssertTrue(window.performKeyEquivalent(with: commandW))

        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.selected, .shortcut)
    }

    func testEachPaneIsAGroupNamedForItsSectionSoVoiceOverSaysWhereItIs() {
        let window = settings()
        for section in SettingsSection.allCases {
            XCTAssertEqual(window.pane(section).accessibilityRole(), .group, section.title)
            XCTAssertEqual(window.pane(section).accessibilityLabel(), section.title)
        }
    }

    func testEverySectionNameFitsTheSidebarWithoutWrapping() {
        let selected = NSFont.systemFont(ofSize: 14, weight: .semibold)
        for section in SettingsSection.allCases {
            let width = (section.title as NSString).size(withAttributes: [.font: selected]).width
            XCTAssertLessThanOrEqual(width, 136, "\(section.title) is \(width) points in the selected row's 14/600")
        }
    }

    func testEachPaneOpensWithItsTitleThenItsLead() {
        let window = settings()
        for section in SettingsSection.allCases {
            let lines = texts(in: window.pane(section))
            XCTAssertEqual(lines.first, section.title)
            if let lead = section.lead { XCTAssertEqual(lines.dropFirst().first, lead, section.title) }
        }
    }

    func testTabGoesFromTheSidebarThroughThePaneInReadingOrderAndBack() throws {
        let window = settings(keys: KeyStore(inKeychain: false))
        let table = try XCTUnwrap(descendants(of: window.contentView!).compactMap { $0 as? NSTableView }.first)

        window.select(.mcp)
        let loop = keyLoop(from: table)
        let pane = window.pane(.mcp)
        let order: [NSView] = try ["Claude Code", "Codex", "Claude Desktop", "Let AI tools add cards", "Top", "Bottom"].map {
            try button($0, in: pane)
        } + [try XCTUnwrap(descendants(of: pane).compactMap { $0 as? NSTextView }.first), try button("Reset to Default", in: pane)]
        XCTAssertEqual(loop.map(ObjectIdentifier.init), order.filter(\.canBecomeKeyView).map(ObjectIdentifier.init),
                       "only what Tab can reach now: buttons need Full Keyboard Access, and Reset is dimmed")

        window.select(.privacy)
        XCTAssertEqual(keyLoop(from: table).count, 0, "the card has nothing to focus")
    }

    func testTheRecorderIsNamedShortcutAndSpellsTheCombinationOut() throws {
        let window = settings()
        let recorder = try XCTUnwrap(descendants(of: window.pane(.shortcut)).compactMap { $0 as? ShortcutField }.first)

        XCTAssertEqual(recorder.title, "⌃⌥I", "the harness presses it by its glyphs")
        XCTAssertEqual(recorder.accessibilityLabel(), "Shortcut")
        XCTAssertEqual(recorder.accessibilityValue() as? String, "Control-Option-I")
    }

    func testStartingARecordingIsAnnouncedAndFillingTheWindowIsNot() throws {
        var said: [String] = []
        let window = settings(announce: { said.append($0) })
        let recorder = try XCTUnwrap(descendants(of: window.pane(.shortcut)).compactMap { $0 as? ShortcutField }.first)
        window.becomeKey()
        XCTAssertEqual(said, [], "opening the window is not news")

        recorder.performClick(nil)
        recorder.cancelRecording()

        XCTAssertEqual(said, ["Recording. Press the new keys, or Escape to cancel."])
    }

    func testAStatusThatChangesIsAnnouncedWithItsPrefix() throws {
        var said: [String] = []
        let window = settings(keys: KeyStore(inKeychain: false), announce: { said.append($0) })
        window.select(.aiSummary)
        let field = try XCTUnwrap(descendants(of: window.pane(.aiSummary)).compactMap { $0 as? NSSecureTextField }.first)

        type("sk-ant-test", into: field, in: window)
        try button("Save", in: window.pane(.aiSummary)).performClick(nil)

        XCTAssertEqual(said, ["Done: An Anthropic key is held for this run only. Paste a new one to replace it."])
    }

    func testAStatusThatChangesOnAHiddenPaneIsNotAnnounced() throws {
        var said: [String] = []
        let spread = SpreadChoice(preferences: Preferences(defaults: nil))
        let window = SettingsWindow(keys: KeyStore(inKeychain: false), hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                                    updates: Updates(build: .current, isScratch: false), spread: spread,
                                    announce: { said.append($0) }) {}

        spread.cells = .empty
        window.becomeKey()
        XCTAssertEqual(said, [], "Spread is not the pane on screen")

        window.select(.spread)
        spread.cells = .standard
        window.becomeKey()
        spread.cells = .empty
        window.becomeKey()
        XCTAssertEqual(said, ["No cell is ticked, so Spread makes no card. Tick the cells it should fill."], "a neutral line has no prefix")
    }

    func testSavingAndRemovingKeysMovesTheKeyLineAndThePrivacyCardTogether() async throws {
        var changes = 0
        let window = settings(keys: KeyStore(inKeychain: false), onChange: { changes += 1 })
        let key = window.pane(.aiSummary), privacy = window.pane(.privacy)
        let field = try XCTUnwrap(descendants(of: key).compactMap { $0 as? NSSecureTextField }.first)
        XCTAssertTrue(texts(in: key).contains("API key"), "the lead names both companies")
        XCTAssertTrue(texts(in: privacy).contains { $0.hasPrefix("With a key saved, Ideator sends a card's text to Anthropic or OpenAI, whichever your key is for") })

        window.select(.aiSummary)
        type("sk-proj-test", into: field, in: window)
        try button("Save", in: key).performClick(nil)
        XCTAssertTrue(texts(in: key).contains { $0.hasPrefix("An OpenAI key is held for this run only") })
        XCTAssertTrue(texts(in: privacy).contains { $0.hasPrefix("With a key saved, Ideator sends a card's text to OpenAI, using your own key") })

        type("sk-ant-test", into: field, in: window)
        try button("Save", in: key).performClick(nil)
        XCTAssertTrue(texts(in: key).contains { $0.hasPrefix("An Anthropic key is held for this run only") })
        XCTAssertTrue(texts(in: privacy).contains { $0.hasPrefix("With a key saved, Ideator sends a card's text to Anthropic, using your own key") })

        try button("Remove Key", in: key).performClick(nil)
        XCTAssertTrue(texts(in: key).contains { $0.hasPrefix("No key saved") })
        XCTAssertTrue(texts(in: privacy).contains { $0.hasPrefix("With a key saved, Ideator sends a card's text to Anthropic or OpenAI") })
        XCTAssertEqual(changes, 3, "each save and the removal tell the controller, so failed summaries retry under the new key")
    }

    func testThePrivacyCardShowsItsHeadlineAndEachTermOverItsText() {
        let window = settings()
        let lines = texts(in: window.pane(.privacy))
        let card = SettingsCopy.Privacy.card(for: nil)

        XCTAssertEqual(lines, ["Privacy", card.headline] + card.items.flatMap { [$0.term, $0.text] })
    }

    func testTheUpdatesPaneShowsTheVersionLineThenWhyThisRunDoesNotCheck() {
        let updates = Updates(build: .current, isScratch: false)
        let window = SettingsWindow(keys: KeyStore(inKeychain: false), hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                                    updates: updates) {}
        let lines = texts(in: window.pane(.updates))

        let version = lines.firstIndex(of: updates.build.versionLine)
        XCTAssertNotNil(version)
        XCTAssertEqual(version.map { lines[$0 + 1] }, "Only builds made by scripts/package.sh check for updates.")
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
        let window = settings(keys: keys, onChange: { changes += 1 })

        keys.refuses = true
        try button("Remove Key", in: window.pane(.aiSummary)).performClick(nil)

        XCTAssertEqual(keys.apiKey, "sk-ant-test", "the key is still saved, so it still sends")
        XCTAssertEqual(changes, 0, "the summarizer must not be told the key is gone")
        XCTAssertTrue(texts(in: window.pane(.aiSummary)).contains { $0.contains("An Anthropic key is held") }, "the status line still says a key is saved")
        XCTAssertFalse(texts(in: window.pane(.aiSummary)).contains { $0.contains("No key saved") })
    }

    func testSaveIsDimmedWhileTheFieldIsEmptyAndRemoveKeyWhileNoKeyIsSaved() throws {
        let keys = KeyStore(inKeychain: false)
        let window = settings(keys: keys)
        window.select(.aiSummary)
        let pane = window.pane(.aiSummary)
        let field = try XCTUnwrap(descendants(of: pane).compactMap { $0 as? NSSecureTextField }.first)
        let save = try button("Save", in: pane), remove = try button("Remove Key", in: pane)
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(remove.isEnabled)

        type("   ", into: field, in: window)
        XCTAssertFalse(save.isEnabled, "spaces are not a key")
        type("sk-ant-test", into: field, in: window)
        XCTAssertTrue(save.isEnabled)

        save.performClick(nil)
        XCTAssertEqual(keys.provider, .anthropic)
        XCTAssertEqual(field.stringValue, "")
        XCTAssertFalse(save.isEnabled, "the field is empty again")
        XCTAssertTrue(remove.isEnabled)

        remove.performClick(nil)
        XCTAssertNil(keys.provider)
        XCTAssertFalse(remove.isEnabled)
    }

    func testAKeychainRefusalSaysSoUntilAChangeGoesThrough() throws {
        var said: [String] = []
        let keys = RefusableKeyStore()
        keys.set("sk-ant-test")
        let window = settings(keys: keys, announce: { said.append($0) })
        window.select(.aiSummary)
        let pane = window.pane(.aiSummary)
        let refused = "The Keychain refused the change. An Anthropic key is held for this run only. Paste a new one to replace it."

        keys.refuses = true
        try button("Remove Key", in: pane).performClick(nil)
        XCTAssertTrue(texts(in: pane).contains(refused))
        XCTAssertEqual(said, ["Error: \(refused)"])

        keys.refuses = false
        try button("Remove Key", in: pane).performClick(nil)
        XCTAssertFalse(texts(in: pane).contains(refused))
        XCTAssertEqual(said.last, "No key saved. Ideator works without one; collapsed cards show “Summary unavailable”.")
    }

    func testRemoveKeyDeletesTheKeyAndTellsTheControllerOnce() async throws {
        let keys = RefusableKeyStore()
        keys.set("sk-ant-test")
        var changes = 0
        let window = settings(keys: keys, onChange: { changes += 1 })

        try button("Remove Key", in: window.pane(.aiSummary)).performClick(nil)

        XCTAssertNil(keys.apiKey)
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(texts(in: window.pane(.aiSummary)).contains { $0.hasPrefix("No key saved") })
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

    private func settings(keys: KeyStore = KeyStore(inKeychain: false), announce: ((String) -> Void)? = nil,
                          onChange: @escaping () -> Void = {}) -> SettingsWindow {
        SettingsWindow(keys: keys, hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                       updates: Updates(build: .current, isScratch: false), announce: announce, onChange: onChange)
    }

    /// Keystrokes through the field editor, as typing sends them, so the pane hears each change.
    private func type(_ text: String, into field: NSTextField, in window: SettingsWindow) {
        window.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func shown(in window: SettingsWindow) -> [SettingsSection] {
        SettingsSection.allCases.filter { !window.pane($0).isHidden }
    }

    /// What Tab visits after `start`, in order, until it comes back.
    private func keyLoop(from start: NSView) -> [NSView] {
        var loop: [NSView] = []
        var view = start.nextValidKeyView
        while let current = view, current !== start, loop.count < 50 {
            loop.append(current)
            view = current.nextValidKeyView
        }
        XCTAssertTrue(view == nil || view === start, "Tab comes back to the sidebar")
        return loop
    }

    private func button(_ title: String, in view: NSView) throws -> NSButton {
        try XCTUnwrap(descendants(of: view).compactMap { $0 as? NSButton }.first { $0.title == title }, title)
    }

    /// Every label's text under `view`, in reading order.
    private func texts(in view: NSView) -> [String] {
        descendants(of: view).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
    }

    /// Every view under `view` in reading order: each view, then what it holds.
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private final class RefusableKeyStore: KeyStore {
    var refuses = false

    init() { super.init(inKeychain: false) }

    @discardableResult
    override func set(_ key: String?) -> Bool { refuses ? false : super.set(key) }
}
