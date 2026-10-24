import XCTest
import Carbon.HIToolbox
@testable import Ideator

/// Real Carbon registrations, on combinations no app uses (⌃⌥⇧⌘ + F13 to F20). A press is
/// simulated with `SendEventToEventTarget`, so no Accessibility permission is needed.
final class HotKeyTests: XCTestCase {
    private let suites = TestDefaults()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func combo(_ key: Int) -> Shortcut {
        Shortcut(keyCode: UInt32(key), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))!
    }

    private func preferences(shortcut: Shortcut? = nil) -> Preferences {
        let preferences = Preferences(defaults: suites.make())
        if let shortcut { preferences.shortcut = shortcut }
        return preferences
    }

    private func press(_ hotKey: HotKey) {
        var event: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event)
        var pressed = EventHotKeyID(signature: OSType(0x4352_4453), id: hotKey.id)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          MemoryLayout<EventHotKeyID>.size, &pressed)
        SendEventToEventTarget(event, GetApplicationEventTarget())
    }

    private func key(_ type: NSEvent.EventType, keyCode: Int, _ flags: NSEvent.ModifierFlags,
                     isARepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: isARepeat,
                         keyCode: UInt16(keyCode))!
    }

    // MARK: Shortcut

    func testTheStandardShortcutIsControlOptionSpace() {
        XCTAssertEqual(Shortcut.standard.display, "⌃⌥Space")
        XCTAssertEqual(Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | cmdKey))?.display, "⌥⌘C",
                       "modifiers come in Apple's order, then the key")
    }

    func testAShortcutNeedsCommandOrControlPlusAnotherModifier() {
        let c = UInt32(kVK_ANSI_C)
        XCTAssertNil(Shortcut(keyCode: c, modifiers: UInt32(cmdKey)), "⌘C alone would break copy everywhere")
        XCTAssertNil(Shortcut(keyCode: c, modifiers: UInt32(controlKey)), "⌃C alone would break typing")
        XCTAssertNil(Shortcut(keyCode: c, modifiers: UInt32(optionKey)), "⌥C types a character")
        XCTAssertNil(Shortcut(keyCode: c, modifiers: UInt32(optionKey | shiftKey)), "no ⌘ or ⌃")
        XCTAssertNil(Shortcut(keyCode: c, modifiers: 0), "a bare key")
        XCTAssertNotNil(Shortcut(keyCode: c, modifiers: UInt32(cmdKey | shiftKey)))
        XCTAssertNotNil(Shortcut(keyCode: c, modifiers: UInt32(controlKey | optionKey)))
    }

    func testAKeyEventMapsToCarbonModifiersAndIgnoresCapsLockAndFn() {
        let down = key(.keyDown, keyCode: kVK_Space, [.control, .option, .capsLock, .function])
        XCTAssertEqual(Shortcut(event: down), .standard)
        XCTAssertNil(Shortcut(event: key(.keyUp, keyCode: kVK_Space, [.control, .option])), "a key-up")
        XCTAssertNil(Shortcut(event: key(.keyDown, keyCode: kVK_Space, [.control, .option], isARepeat: true)),
                     "a held key repeating")
    }

    func testAStoredShortcutRoundTripsAndDamagedValuesAreRefused() {
        XCTAssertEqual(Shortcut(stored: Shortcut.standard.stored), .standard)
        XCTAssertNil(Shortcut(stored: ["keyCode": -1, "modifiers": 6144]), "a negative key code")
        XCTAssertNil(Shortcut(stored: ["keyCode": 49]), "no modifiers key")
        XCTAssertNil(Shortcut(stored: ["keyCode": 49, "modifiers": 2048]), "an illegal combination")
        XCTAssertNil(Shortcut(stored: "junk"))
        XCTAssertNil(Shortcut(stored: nil))
    }

    func testTheRecorderNamesWhatWasPressedEvenWhenItIsRefused() {
        let refused = key(.keyDown, keyCode: kVK_ANSI_K, [.command])
        XCTAssertNil(Shortcut(event: refused))
        XCTAssertEqual(Shortcut.refusal(of: refused),
                       "⌘K can't be the shortcut. Use ⌃ or ⌘ with at least one other modifier key, so typing never triggers it.")
        XCTAssertEqual(Shortcut.describe(key(.flagsChanged, keyCode: kVK_Option, [.control, .option])), "⌃⌥",
                       "holding modifiers shows just the modifiers")
    }

    func testMacOSBindingsMatchOnKeyAndTheFourModifiersOnly() {
        let space = UInt32(kVK_Space)
        let controlOption = UInt32(controlKey | optionKey)
        XCTAssertTrue(Shortcut.standard.isUsedByMacOS(in: [(space, controlOption)]))
        XCTAssertFalse(Shortcut.standard.isUsedByMacOS(in: [(space, UInt32(controlKey))]), "⌃Space is another shortcut")
        XCTAssertFalse(Shortcut.standard.isUsedByMacOS(in: [(UInt32(kVK_Return), controlOption)]), "another key")
        XCTAssertTrue(Shortcut.standard.isUsedByMacOS(in: [(space, controlOption | 0x20_000)]),
                      "the fn bit macOS adds to its own entries does not make it a different shortcut")
    }

    // MARK: HotKey

    func testRegisterTakesTheChosenShortcutAndAnotherHotKeyCannotHaveIt() {
        let first = HotKey(preferences: preferences(shortcut: combo(kVK_F13))) {}
        let second = HotKey(preferences: preferences(shortcut: combo(kVK_F13))) {}
        first.register()
        second.register()

        XCTAssertNil(first.problem)
        XCTAssertEqual(second.problem, .taken)
        XCTAssertEqual(second.problem?.text(for: second.shortcut), "⌃⌥⇧⌘F13 is already taken.")
    }

    func testAFailedChooseKeepsTheWorkingShortcutAndThePreference() {
        let holder = HotKey(preferences: preferences(shortcut: combo(kVK_F13))) {}
        holder.register()
        let prefs = preferences(shortcut: combo(kVK_F14))
        let mine = HotKey(preferences: prefs) {}
        mine.register()

        XCTAssertEqual(mine.choose(combo(kVK_F13)), .taken)

        XCTAssertEqual(mine.shortcut, combo(kVK_F14))
        XCTAssertEqual(prefs.shortcut, combo(kVK_F14), "the stored choice did not change")
        XCTAssertNil(mine.problem, "a refused pick is the caller's to show; the working shortcut is fine")
        XCTAssertEqual(HotKey(preferences: preferences()) {}.choose(combo(kVK_F14)), .taken,
                       "the old shortcut is still live")
    }

    func testChooseSwapsPersistsAndFreesTheOldCombination() {
        let prefs = preferences(shortcut: combo(kVK_F13))
        let mine = HotKey(preferences: prefs) {}
        mine.register()

        XCTAssertNil(mine.choose(combo(kVK_F15)))
        XCTAssertNil(mine.choose(combo(kVK_F15)), "choosing the live shortcut again is fine")

        XCTAssertEqual(mine.shortcut, combo(kVK_F15))
        XCTAssertEqual(prefs.shortcut, combo(kVK_F15))
        XCTAssertNil(HotKey(preferences: preferences()) {}.choose(combo(kVK_F13)), "the old combination is free")
    }

    func testUnregisterFreesTheCombinationAndRegisterTakesItBackTwiceOver() {
        let mine = HotKey(preferences: preferences(shortcut: combo(kVK_F13))) {}
        mine.register()

        mine.unregister()
        mine.unregister()
        let other = HotKey(preferences: preferences()) {}
        XCTAssertNil(other.choose(combo(kVK_F13)), "released while recording")
        other.unregister()

        mine.register()
        mine.register()
        XCTAssertNil(mine.problem)
        XCTAssertEqual(HotKey(preferences: preferences()) {}.choose(combo(kVK_F13)), .taken, "taken back")
    }

    func testAReleasedHotKeyGivesItsCombinationBack() {
        var mine: HotKey? = HotKey(preferences: preferences(shortcut: combo(kVK_F13))) {}
        mine?.register()
        mine = nil

        XCTAssertNil(HotKey(preferences: preferences()) {}.choose(combo(kVK_F13)))
    }

    func testAPressRunsTheActionOfItsOwnHotKeyOnly() {
        var firstFired = 0, secondFired = 0
        let first = HotKey(preferences: preferences(shortcut: combo(kVK_F13))) { firstFired += 1 }
        let second = HotKey(preferences: preferences(shortcut: combo(kVK_F14))) { secondFired += 1 }
        first.register()
        second.register()

        press(first)
        XCTAssertEqual([firstFired, secondFired], [1, 0])
        press(second)
        XCTAssertEqual([firstFired, secondFired], [1, 1], "no double fire")
    }

    func testAStoredShortcutTakenAtLaunchStaysChosenWithAProblemUntilAnotherIsChosen() {
        let holder = HotKey(preferences: preferences(shortcut: combo(kVK_F13))) {}
        holder.register()
        let prefs = preferences(shortcut: combo(kVK_F13))
        let late = HotKey(preferences: prefs) {}

        late.register()

        XCTAssertEqual(late.shortcut, combo(kVK_F13))
        XCTAssertEqual(late.problem, .taken)
        XCTAssertNil(late.choose(combo(kVK_F16)))
        XCTAssertNil(late.problem)
        XCTAssertEqual(prefs.shortcut, combo(kVK_F16))
    }
}
