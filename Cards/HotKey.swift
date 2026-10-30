import AppKit
import Carbon.HIToolbox

/// A global key combination: a virtual key code and Carbon modifier bits (`controlKey`,
/// `optionKey`, `shiftKey`, `cmdKey`). Always legal: the failable inits are the only way in, so
/// every `Shortcut` in the app can be registered, shown and stored without a second check.
/// Legal means ⌘ or ⌃ plus at least one more modifier: a bare ⌘C or ⌃A would break copy and
/// text editing everywhere, because a Carbon hotkey is taken before the focused app sees the key.
struct Shortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let standard = Shortcut(valid: UInt32(kVK_ANSI_I), UInt32(controlKey | optionKey))

    static let requirement = "Use ⌃ or ⌘ with at least one other modifier key, so typing never triggers it."

    private static let mask = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    private init(valid keyCode: UInt32, _ modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(keyCode: UInt32, modifiers: UInt32) {
        let modifiers = modifiers & Self.mask
        guard modifiers & UInt32(cmdKey | controlKey) != 0, modifiers.nonzeroBitCount >= 2 else { return nil }
        self.init(valid: keyCode, modifiers)
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    init?(stored: Any?) {
        guard let dict = stored as? [String: Int], let code = dict["keyCode"], let modifiers = dict["modifiers"],
              let code = UInt32(exactly: code), let modifiers = UInt32(exactly: modifiers) else { return nil }
        self.init(keyCode: code, modifiers: modifiers)
    }

    var stored: [String: Int] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers)] }

    var display: String { Self.describe(keyCode: keyCode, modifiers: modifiers) }

    /// The combination spelled out for VoiceOver, in the glyphs' order: "Control-Option-I".
    var spoken: String {
        let names: [(Int, String)] = [(controlKey, "Control"), (optionKey, "Option"), (shiftKey, "Shift"), (cmdKey, "Command")]
        let held = names.filter { modifiers & UInt32($0.0) != 0 }.map(\.1)
        return (held + [Self.keyName(keyCode)]).joined(separator: "-")
    }

    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        glyphs(modifiers) + keyName(keyCode)
    }

    static func describe(_ event: NSEvent) -> String {
        let held = glyphs(carbonModifiers(event.modifierFlags))
        return event.type == .flagsChanged ? held : held + keyName(UInt32(event.keyCode))
    }

    typealias Binding = (keyCode: UInt32, modifiers: UInt32)

    /// True when an enabled macOS shortcut (System Settings › Keyboard › Keyboard Shortcuts) is on
    /// this combination, as ⌃⌥Space is for "Select next source in Input menu". An advisory, not a
    /// refusal: Carbon registers it either way and which one fires is up to macOS.
    func isUsedByMacOS(in bindings: [Binding] = Shortcut.macOSBindings()) -> Bool {
        bindings.contains { $0.keyCode == keyCode && $0.modifiers & Self.mask == modifiers }
    }

    static func macOSBindings() -> [Binding] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int, code >= 0, code < 0xFFFF,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int, modifiers >= 0
            else { return nil }
            return (UInt32(code), UInt32(modifiers))
        }
    }

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
/// The handler's user data is an unretained `self`, so the handler lives exactly as long as the
/// object: installed in `init`, removed in `deinit` with the registration. Each instance has its
/// own hotkey id and ignores other ids.
///
/// Every operation is idempotent and a failed one changes nothing: the working shortcut stays.
final class HotKey {
    enum Problem: Error, Equatable {
        /// Carbon says the combination is already registered (`eventHotKeyExistsErr`). Only this
        /// process can cause it: two apps registering one combination both get `noErr`.
        case taken
        case refused(OSStatus)

        func text(for shortcut: Shortcut) -> String {
            switch self {
            case .taken: "\(shortcut.display) is already taken."
            case .refused(let status): "macOS refused \(shortcut.display) (error \(status))."
            }
        }
    }

    private static let signature = OSType(0x4352_4453)   // "CRDS"
    private static var lastID: UInt32 = 0

    private(set) var shortcut: Shortcut
    private(set) var problem: Problem?
    let id: UInt32

    private let preferences: Preferences
    private let action: () -> Void
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?

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

    func register() {
        guard registration == nil else { return }
        switch Self.claim(shortcut, id) {
        case .success(let ref): registration = ref; problem = nil
        case .failure(let failure): problem = failure
        }
    }

    @discardableResult
    func unregister() -> Bool {
        guard let registration else { return false }
        UnregisterEventHotKey(registration)
        self.registration = nil
        return true
    }

    /// Claims `new` before it drops the old registration, so a refusal leaves the working shortcut
    /// live and the preference untouched.
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
