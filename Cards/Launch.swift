import Foundation

struct Launch {
    let folder: URL?
    /// From the environment, not an argument, so the command line verify-cards matches its pid by
    /// stays as it is.
    let forcesWelcome: Bool

    /// Only a `-CardsFolder` launch argument starts a scratch run, so `arguments` is the argument
    /// domain: `UserDefaults.string(forKey:)` also searches the preferences, and a stray `defaults
    /// write` would turn the owner's Ideator into a scratch run. An update-test copy also reads its own
    /// `CardsFolder` default, because Sparkle relaunches an app with no arguments and the relaunched
    /// copy must stay off the owner's folder and Keychain.
    init(arguments: [String: Any], defaults: UserDefaults = .standard, build: BuildInfo = .current,
         environment: [String: String]) {
        let named = arguments["CardsFolder"] as? String
            ?? (build.isUpdateTest ? defaults.string(forKey: "CardsFolder") : nil)
        folder = named.map { URL(filePath: $0, directoryHint: .isDirectory) }
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
