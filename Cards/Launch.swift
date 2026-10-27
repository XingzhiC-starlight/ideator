import Foundation

struct Launch {
    let folder: URL?
    /// From the environment, not an argument, so the command line verify-cards matches its pid by
    /// stays as it is.
    let forcesWelcome: Bool

    /// `arguments` is where `-CardsFolder` shows up (the argument domain of `UserDefaults.standard`).
    init(arguments: UserDefaults, environment: [String: String]) {
        folder = arguments.string(forKey: "CardsFolder").map { URL(filePath: $0, directoryHint: .isDirectory) }
        forcesWelcome = environment["CARDS_SHOW_WELCOME"] == "1"
    }

    var isScratch: Bool { folder != nil }

    var notesFolder: URL { folder ?? Library.defaultFolder }

    func preferences(standard: UserDefaults) -> Preferences {
        Preferences(defaults: isScratch ? nil : standard)
    }

    func keys() -> KeyStore {
        KeyStore(inKeychain: !isScratch)
    }

    func showsWelcome(seen: Bool) -> Bool { forcesWelcome || !seen }

    /// The launch order, with both effects passed in so a test can watch the order:
    /// - welcome due: `welcome` shows it and hands back `onContinue`. `openNotes` runs only when
    ///   that is called, once however many times it is called, and the "seen" flag is set after it
    ///   returns, so a launch killed on the way in shows the welcome again, not a bare prompt;
    /// - otherwise: `openNotes` runs now.
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
