import Foundation

/// `nil` defaults is a scratch run: reads give the factory values (welcome seen, default shortcut)
/// and writes go nowhere, so a verify run can't change the owner's preferences.
///
/// A struct, not a class: a MainActor class released inside an XCTest assertion crashes the test
/// host on macOS 15 (its implicit deinit hops to the main executor).
struct Preferences {
    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    var shortcut: Shortcut {
        get { Shortcut(stored: defaults?.object(forKey: "Shortcut")) ?? .standard }
        nonmutating set { defaults?.set(newValue.stored, forKey: "Shortcut") }
    }

    var welcomeSeen: Bool { defaults?.bool(forKey: "WelcomeSeen") ?? true }

    func markWelcomeSeen() { defaults?.set(true, forKey: "WelcomeSeen") }
}
