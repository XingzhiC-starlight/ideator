import Foundation

/// How this process was started. Pure: no AppKit, no disk. Arguments are never persisted, so
/// none of this survives the process.
struct Launch {
    /// `-CardsFolder <path>`: a scratch run on another folder (unit tests, verify-cards). It
    /// persists nothing of the owner's (see `preferences`).
    let folder: URL?

    /// `arguments` is where `-CardsFolder` shows up (the argument domain of `UserDefaults.standard`).
    init(arguments: UserDefaults) {
        folder = arguments.string(forKey: "CardsFolder").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    var isScratch: Bool { folder != nil }

    /// Where notes live: the scratch folder, or ~/Documents/Ideator.
    var notesFolder: URL { folder ?? Library.defaultFolder }

    /// The owner's preferences, or none at all in a scratch run: reads give the factory values
    /// and writes go nowhere, so a verify-cards run can't change the owner's shortcut.
    func preferences(standard: UserDefaults) -> Preferences {
        Preferences(defaults: isScratch ? nil : standard)
    }
}
