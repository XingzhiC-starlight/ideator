import AppKit
import Carbon.HIToolbox

// The global shortcut, as a value (`Shortcut`) and as a registration (`HotKey`).
// Nothing outside this file knows Carbon exists.

/// A global key combination: a virtual key code and Carbon modifier bits (`controlKey`,
/// `optionKey`, `shiftKey`, `cmdKey`). Always legal: the failable inits are the only way in, so
/// every `Shortcut` in the app can be registered, shown and stored without a second check.
/// Legal means ⌘ or ⌃ plus at least one more modifier: a bare ⌘C or ⌃A would break copy and
/// text editing everywhere, because a Carbon hotkey is taken before the focused app sees the key.
struct Shortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// ⌃⌥Space. (The old ⌥⌘C was Finder's Copy as Pathname.)
    static let standard = Shortcut(valid: UInt32(kVK_Space), UInt32(controlKey | optionKey))

    /// What Settings tells a user whose combination was refused.
    static let requirement = "Use ⌃ or ⌘ with at least one other modifier key, so typing never triggers it."

    private static let mask = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    private init(valid keyCode: UInt32, _ modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// nil unless `modifiers` (Carbon bits; anything but the four is dropped) holds ⌘ or ⌃ and at
    /// least two modifiers in all.
    init?(keyCode: UInt32, modifiers: UInt32) {
        let modifiers = modifiers & Self.mask
        guard modifiers & UInt32(cmdKey | controlKey) != 0, modifiers.nonzeroBitCount >= 2 else { return nil }
        self.init(valid: keyCode, modifiers)
    }

    /// A key-down (not a repeat) with its modifier flags mapped to Carbon bits. The recorder's
    /// only way to make a `Shortcut`.
    init?(event: NSEvent) {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    /// Reads what `stored` wrote. nil for anything else (missing keys, wrong types, an illegal
    /// combination), so a damaged default falls back to `standard` instead of crashing or sticking.
    init?(stored: Any?) {
        guard let dict = stored as? [String: Int], let code = dict["keyCode"], let modifiers = dict["modifiers"],
              let code = UInt32(exactly: code), let modifiers = UInt32(exactly: modifiers) else { return nil }
        self.init(keyCode: code, modifiers: modifiers)
    }

    /// A property list: ["keyCode": 49, "modifiers": 6144]. Readable with `defaults read`.
    var stored: [String: Int] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers)] }

    /// "⌃⌥Space": the one string the welcome, Settings and every message use.
    var display: String { Self.describe(keyCode: keyCode, modifiers: modifiers) }

    /// Modifiers in Apple's order (⌃⌥⇧⌘), then the key. Also names combinations that are not
    /// legal shortcuts, for the message that refuses them.
    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        glyphs(modifiers) + keyName(keyCode)
    }

    /// What the recorder shows for `event`: the modifiers held, then the key unless the event is
    /// only a modifier changing.
    static func describe(_ event: NSEvent) -> String {
        let held = glyphs(carbonModifiers(event.modifierFlags))
        return event.type == .flagsChanged ? held : held + keyName(UInt32(event.keyCode))
    }

    /// "⌘K can't be the shortcut. Use ⌃ or ⌘ with at least one other modifier key, …"
    static func refusal(of event: NSEvent) -> String {
        "\(describe(event)) can't be the shortcut. \(requirement)"
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        return UInt32(modifiers)
    }

    private static func glyphs(_ modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        kVK_F20: "F20",
    ]

    /// Space, Return, arrows and F-keys come from a table; the rest from the current layout.
    private static func keyName(_ code: UInt32) -> String {
        if let name = named[Int(code)] { return name }
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)?
            .keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        return length > 0 ? String(utf16CodeUnits: buffer, count: length).uppercased() : "Key \(code)"
    }
}

/// The app's one global shortcut: the combination the user chose (persisted), whether it is
/// registered with Carbon right now, and why not when it isn't. The single owner of all three.
/// Carbon's RegisterEventHotKey needs no Accessibility permission.
///
/// One Carbon handler for the whole life of the object, installed in `init` and removed in
/// `deinit` together with the registration, so a released `HotKey` can't be called and can't
/// keep its combination. Each instance has its own hotkey id and ignores other ids.
///
/// Every operation is idempotent and a failed one changes nothing: the working shortcut stays.
final class HotKey {
    enum Problem: Error, Equatable {
        /// Carbon says the combination is already registered (`eventHotKeyExistsErr`). Only this
        /// process can cause it: two apps registering one combination both get `noErr`.
        case taken
        /// Any other status.
        case refused(OSStatus)

        /// "⌃⌘H is already taken." / "macOS refused ⌃⌘H (error -9879)."
        func text(for shortcut: Shortcut) -> String {
            switch self {
            case .taken: "\(shortcut.display) is already taken."
            case .refused(let status): "macOS refused \(shortcut.display) (error \(status))."
            }
        }
    }

    private static let signature = OSType(0x4352_4453)   // "CRDS"
    private static var lastID: UInt32 = 0

    /// The chosen combination: what Settings shows and the welcome names. Registered unless `problem`
    /// is set or `unregister()` is in effect.
    private(set) var shortcut: Shortcut
    /// Why `shortcut` isn't registered, as of the last attempt. nil while registered or released.
    private(set) var problem: Problem?
    /// Tells this object's presses from another's; tests simulate a press with it.
    let id: UInt32

    private let preferences: Preferences
    private let action: () -> Void
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Installs the handler and reads the chosen shortcut; registers nothing (`register()` does).
    init(preferences: Preferences, action: @escaping () -> Void) {
        self.preferences = preferences
        self.action = action
        shortcut = preferences.shortcut
        Self.lastID += 1
        id = Self.lastID
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            // A C callback, delivered on the main thread.
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard pressed.signature == HotKey.signature, pressed.id == hotKey.id else {
                return OSStatus(eventNotHandledErr)   // another HotKey's: let its handler have it
            }
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Makes sure `shortcut` is registered (launch, and after recording). No-op while it is.
    func register() {
        guard registration == nil else { return }
        switch Self.claim(shortcut, id) {
        case .success(let ref): registration = ref; problem = nil
        case .failure(let failure): problem = failure
        }
    }

    /// Releases the combination so the Settings recorder sees the keys instead of the hotkey
    /// swallowing them. No-op when released. `register()` takes it back.
    func unregister() {
        guard let registration else { return }
        UnregisterEventHotKey(registration)
        self.registration = nil
    }

    /// Switches to `new` and persists it, or changes nothing and says why. `new` is claimed
    /// BEFORE the old registration is dropped, so a refusal leaves the old shortcut live
    /// (nothing to restore) and the preference untouched.
    @discardableResult
    func choose(_ new: Shortcut) -> Problem? {
        guard new != shortcut || registration == nil else { return nil }
        switch Self.claim(new, id) {
        case .failure(let failure):
            return failure
        case .success(let next):
            if let old = registration { UnregisterEventHotKey(old) }
            registration = next
            shortcut = new
            problem = nil
            preferences.shortcut = new
            return nil
        }
    }

    private static func claim(_ shortcut: Shortcut, _ id: UInt32) -> Result<EventHotKeyRef, Problem> {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         EventHotKeyID(signature: signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { return .success(ref) }
        return .failure(status == OSStatus(eventHotKeyExistsErr) ? .taken : .refused(status))
    }
}
