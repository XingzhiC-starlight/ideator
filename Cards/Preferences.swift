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

    /// Whether the owner has acknowledged a welcome card at least as new as this build's. The key
    /// holds the `WelcomeCopy.version` last acknowledged; the Boolean `true` written before the card
    /// was versioned reads as 1, because `integer(forKey:)` turns a stored true into 1.
    var welcomeSeen: Bool { defaults.map { $0.integer(forKey: "WelcomeSeen") >= WelcomeCopy.version } ?? true }

    /// Whether this Mac has been offered the tour. Reads as seen in a scratch run, like `welcomeSeen`,
    /// so only `CARDS_SHOW_WELCOME=1` shows the welcome there.
    var tourSeen: Bool { defaults.map { $0.bool(forKey: "TourSeen") } ?? true }

    var records: LaunchRecords { LaunchRecords(disclosureCurrent: welcomeSeen, tourSeen: tourSeen) }

    /// Writes both records at once, right after the notes open. The acknowledged version never goes
    /// down, so an older build forced after a newer one keeps the newer acknowledgement.
    func markWelcomeSeen() {
        guard let defaults else { return }
        defaults.set(max(defaults.integer(forKey: "WelcomeSeen"), WelcomeCopy.version), forKey: "WelcomeSeen")
        defaults.set(true, forKey: "TourSeen")
    }

    /// Settings › Spread's ticked cells, as slot indices. A missing key reads as the factory cells.
    /// Junk is dropped, since defaults can be edited by hand, and an empty list stays empty, since
    /// no cells is a choice.
    var spreadCells: SpreadCells {
        get {
            guard let stored = defaults?.object(forKey: "SpreadCells") as? [Any] else { return .standard }
            return SpreadCells(indices: stored.compactMap { $0 as? Int })
        }
        nonmutating set { defaults?.set(newValue.indices, forKey: "SpreadCells") }
    }

    var aiTools: AIToolSettings {
        get {
            AIToolSettings(enabled: defaults?.object(forKey: "AIToolsEnabled") as? Bool ?? true,
                           landing: defaults?.string(forKey: "AIToolsLanding") == "bottom" ? .bottom : .top,
                           instruction: Instruction(edited: defaults?.string(forKey: Instruction.preferenceKey)))
        }
        nonmutating set {
            defaults?.set(newValue.enabled, forKey: "AIToolsEnabled")
            defaults?.set(newValue.landing == .bottom ? "bottom" : "top", forKey: "AIToolsLanding")
            if let edited = newValue.instruction.edited {
                defaults?.set(edited, forKey: Instruction.preferenceKey)
            } else {
                defaults?.removeObject(forKey: Instruction.preferenceKey)
            }
        }
    }
}

/// The two records that decide a launch, read together so the decision is one function of them.
struct LaunchRecords: Equatable {
    /// The acknowledged disclosure version is at least `WelcomeCopy.version`.
    var disclosureCurrent: Bool
    /// The tour has been offered once on this Mac.
    var tourSeen: Bool
}
