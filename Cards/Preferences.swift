import Foundation

/// What survives a quit: the global shortcut and whether the welcome was acknowledged. The only
/// code that reads or writes these UserDefaults keys. `nil` defaults is a scratch run: reads give
/// the factory values and writes go nowhere. A struct, not a class: a MainActor class released
/// inside an XCTest assertion crashes the test host on macOS 15 (its implicit deinit hops to the
/// main executor).
struct Preferences {
    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    /// `Shortcut.standard` when nothing is stored or what is stored isn't legal.
    var shortcut: Shortcut {
        get { Shortcut(stored: defaults?.object(forKey: "Shortcut")) ?? .standard }
        nonmutating set { defaults?.set(newValue.stored, forKey: "Shortcut") }
    }

    /// Scratch runs count as seen. Absent means never: a first launch.
    var welcomeSeen: Bool { defaults?.bool(forKey: "WelcomeSeen") ?? true }

    func markWelcomeSeen() { defaults?.set(true, forKey: "WelcomeSeen") }
}
