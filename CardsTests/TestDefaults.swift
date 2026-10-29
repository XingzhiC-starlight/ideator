import Foundation

/// Each suite is a plist inside a temporary folder, named by absolute path. A suite named like an
/// app domain is written to `~/Library/Preferences`, and `removePersistentDomain` empties that file
/// but never deletes it.
final class TestDefaults {
    private(set) var names: [String] = []
    private var folders: [URL] = []

    func make() -> UserDefaults {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IdeatorTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = folder.appendingPathComponent("defaults").path
        folders.append(folder)
        names.append(name)
        return UserDefaults(suiteName: name)!
    }

    func removeAll() {
        for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        names = []
        folders = []
    }
}
