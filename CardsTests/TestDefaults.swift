import Foundation

final class TestDefaults {
    private var names: [String] = []

    func make() -> UserDefaults {
        let name = "IdeatorTests-\(UUID().uuidString)"
        names.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func removeAll() {
        for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        names = []
    }
}
