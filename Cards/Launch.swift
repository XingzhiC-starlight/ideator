import Foundation

struct Launch {
    let folder: URL?
    /// From the environment, not an argument, so the command line verify-cards matches its pid by
    /// stays as it is.
    let forcesWelcome: Bool
    /// The AI tools helper started this run to hand it a card: Ideator stays behind the tool.
    let inBackground: Bool

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
        inBackground = environment[HandOff.backgroundVariable] == "1"
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

    var welcomeTakesFocus: Bool { !inBackground }

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

    // MARK: The welcome and the tour

    /// The whole launch decision, one function of the two records and how this process started:
    /// - forced: the full tour, or its last page in a background start; the records are not read;
    /// - the tour not yet offered: the full tour, or its last page in a background start;
    /// - the tour offered but the disclosures newer than the acknowledged ones: the welcome alone;
    /// - both current: nil, the notes open at once.
    /// A scratch run's preferences read as both current, so it shows nothing unless forced.
    func welcome(for records: LaunchRecords) -> WelcomeKind? {
        if forcesWelcome || !records.tourSeen { return inBackground ? .endOnly : .fullTour }
        return records.disclosureCurrent ? nil : .noTour
    }

    /// The launch order, effects passed in so a test can watch it: the welcome, then `openNotes`
    /// once however often a button is pressed, then both records, then the tour if the kind and the
    /// button lead to one. The records are written as the notes open, never at page 9, so a run that
    /// quits mid-tour does not replay it.
    func run(preferences: Preferences,
             welcome: (_ kind: WelcomeKind, _ choose: @escaping (WelcomeChoice) -> Void) -> Void,
             openNotes: @escaping () -> Void,
             startTour: @escaping (TourStart) -> Void) {
        guard let kind = self.welcome(for: preferences.records) else { return openNotes() }
        var chosen = false
        welcome(kind) { choice in
            guard !chosen else { return }
            chosen = true
            openNotes()
            preferences.markWelcomeSeen()
            if let start = kind.tourStart(after: choice) { startTour(start) }
        }
    }
}

/// What the welcome window offers. The button the reader presses plus the kind say whether a tour
/// follows and where it starts.
enum WelcomeKind: Equatable {
    /// "Skip the tour" and "Start the tour": a fresh Mac, an owner's first launch of this build, or
    /// `CARDS_SHOW_WELCOME=1`.
    case fullTour
    /// "Continue" alone, then the last page: a background start by the AI tools helper while the tour is due.
    case endOnly
    /// "Continue" alone and no tour: the tour was offered but the disclosures are newer.
    case noTour

    /// Where the tour starts after `choice`; nil: no tour.
    func tourStart(after choice: WelcomeChoice) -> TourStart? {
        switch (self, choice) {
        case (.fullTour, .skip): .lastPage
        case (.fullTour, _): .firstPage
        case (.endOnly, _): .lastPage
        case (.noTour, _): nil
        }
    }
}

/// The welcome's buttons: "Start the tour", "Skip the tour", "Continue".
enum WelcomeChoice: Equatable { case start, skip, proceed }

/// Where a tour begins. Page numbers stay inside `TourScript`.
enum TourStart: Equatable { case firstPage, lastPage }
