import Foundation

/// How this process was started, and the order of its first moments. Pure: no AppKit, no disk.
/// Arguments are never persisted, so none of this survives the process.
struct Launch {
    /// `-CardsFolder <path>`: a scratch run on another folder (unit tests, verify-cards). It shows
    /// no welcome and persists nothing of the owner's (see `preferences`).
    let folder: URL?
    /// `CARDS_SHOW_WELCOME=1` in the environment: show the welcome even so, for a screenshot. An
    /// environment variable, not an argument, so the command line verify-cards matches stays as is.
    let forcesWelcome: Bool

    /// `arguments` is where `-CardsFolder` shows up (the argument domain of `UserDefaults.standard`).
    init(arguments: UserDefaults, environment: [String: String]) {
        folder = arguments.string(forKey: "CardsFolder").map { URL(filePath: $0, directoryHint: .isDirectory) }
        forcesWelcome = environment["CARDS_SHOW_WELCOME"] == "1"
    }

    var isScratch: Bool { folder != nil }

    /// Where notes live: the scratch folder, or ~/Documents/Ideator.
    var notesFolder: URL { folder ?? Library.defaultFolder }

    /// The owner's preferences, or none at all in a scratch run: reads give the factory values
    /// and writes go nowhere, so a verify-cards run can't change the owner's shortcut or welcome flag.
    func preferences(standard: UserDefaults) -> Preferences {
        Preferences(defaults: isScratch ? nil : standard)
    }

    /// The first-launch rule. Its one input is a UserDefaults flag: reading it touches
    /// ~/Library/Preferences, never ~/Documents, which would start macOS's Documents prompt.
    func showsWelcome(seen: Bool) -> Bool { forcesWelcome || !seen }

    /// The launch order, with both effects passed in so a test can watch the order:
    /// - welcome due: `welcome` shows it and hands back `onContinue`. `openNotes` runs only when
    ///   that is called, once however many times it is called, and the "seen" flag is set after it
    ///   returns, so a launch killed on the way in shows the welcome again, not a bare prompt;
    /// - otherwise: `openNotes` runs now.
    /// `openNotes` is where the app first touches the notes folder (it builds `DeskController`,
    /// whose `Library.load` creates the folder), so this is the folder gate.
    func run(preferences: Preferences, welcome: (_ onContinue: @escaping () -> Void) -> Void,
             openNotes: @escaping () -> Void) {
        guard showsWelcome(seen: preferences.welcomeSeen) else { return openNotes() }
        var opened = false
        welcome {
            guard !opened else { return }
            opened = true
            openNotes()
            preferences.markWelcomeSeen()
        }
    }
}
