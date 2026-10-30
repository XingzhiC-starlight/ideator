import Foundation

/// The six sections in sidebar order. This is the one list: the sidebar's rows, the pane host's
/// children, `SettingsWindow.pane(_:)` and the panes' titles and accessibility labels all derive from
/// `allCases`. A new case fails the build at `title`, `lead` and the pane switch in `SettingsWindow`'s
/// initializer, so nothing can be half-added.
enum SettingsSection: Int, CaseIterable {
    case shortcut, spread, aiSummary, mcp, updates, privacy

    var title: String {
        switch self {
        case .shortcut: "Shortcut"
        case .spread: "Spread"
        case .aiSummary: "AI Summary"
        case .mcp: "MCP"
        case .updates: "Updates"
        case .privacy: "Privacy"
        }
    }

    var lead: String? {
        switch self {
        case .shortcut: "Hides or shows every card, from any app."
        case .spread: "Spread, on the stack's ribbon, puts a new card in each ticked cell."
        case .aiSummary: "A collapsed card shows a summary that Anthropic or OpenAI writes, using your own key."
        case .mcp: "Let AI tools like Claude Code add cards to Ideator. They connect through MCP, a standard way "
            + "for AI tools to reach apps."
        case .updates: "Ideator gets new versions from GitHub."
        case .privacy: nil
        }
    }

    static let opening: SettingsSection = .shortcut
}

/// What a status line says and how. `kind` alone decides the glyph and the VoiceOver prefix, so no
/// caller can pair an error text with a success glyph, and "announce on change" is a value comparison.
struct SettingsStatus: Equatable {
    enum Kind: Equatable {
        case neutral, success, warning, error

        var glyph: String? {
            switch self {
            case .neutral: nil
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }

        var spokenPrefix: String? {
            switch self {
            case .neutral: nil
            case .success: "Done:"
            case .warning: "Warning:"
            case .error: "Error:"
            }
        }
    }

    let kind: Kind
    let text: String

    var spoken: String { kind.spokenPrefix.map { "\($0) \(text)" } ?? text }

    static func neutral(_ text: String) -> SettingsStatus { SettingsStatus(kind: .neutral, text: text) }
    static func success(_ text: String) -> SettingsStatus { SettingsStatus(kind: .success, text: text) }
    static func warning(_ text: String) -> SettingsStatus { SettingsStatus(kind: .warning, text: text) }
    static func error(_ text: String) -> SettingsStatus { SettingsStatus(kind: .error, text: text) }
}

struct PrivacyPage: Equatable {
    struct Item: Equatable {
        let term: String
        let text: String
    }

    let headline: String
    let items: [Item]
}

/// Every string Settings shows, one nested enum per section in sidebar order, as constants and pure
/// functions. A pane holds no literal: the functions that take model state return the finished
/// `SettingsStatus` or `String`, so a pane's `refresh()` has no wording logic. Tests assert here, and
/// the docs quote from here.
enum SettingsCopy {
    static let windowTitle = "Ideator Settings"
    /// The sidebar's accessibility label, which the harness's `section` verb looks for.
    static let sections = "Settings sections"

    enum Shortcut {
        static let useDefault = "Use Default"
        static let caption = "Click the shortcut, then press the new keys."
        static let prompt = "Type shortcut…"
        static let recording = "Recording. Press the new keys, or Escape to cancel."

        static func status(shortcut: Ideator.Shortcut, problem: HotKey.Problem?, usedByMacOS: Bool,
                           refusal: String?) -> SettingsStatus? {
            if let refusal { return .error(refusal) }
            if let problem { return .error(problem.text(for: shortcut) + " There is no shortcut until you pick another.") }
            if usedByMacOS {
                return .warning("macOS also has a shortcut on \(shortcut.display) (System Settings › Keyboard › Keyboard "
                    + "Shortcuts). If it fires instead of Ideator, pick another here.")
            }
            return nil
        }

        static func rejection(_ problem: HotKey.Problem, wanted: Ideator.Shortcut, kept: Ideator.Shortcut) -> String {
            "\(problem.text(for: wanted)) Still using \(kept.display)."
        }
    }

    enum Spread {
        static let caption = "Its next click gathers them into the stack, and the one after puts them back. "
            + "Option-click starts a new set. The dimmed cell is the stack's."
        static let stackCell = "The stack, dimmed"

        /// What VoiceOver, the tests and the recipes call cell `n`, 1 to 20 in reading order.
        static func cell(_ n: Int) -> String { "Spread cell \(n)" }

        static func status(cells: SpreadCells) -> SettingsStatus? {
            cells.isEmpty ? .neutral("No cell is ticked, so Spread makes no card. Tick the cells it should fill.") : nil
        }
    }

    enum AISummary {
        static let label = "API key"
        static let placeholder = "sk-ant-… or sk-…"
        static let save = "Save"
        static let remove = "Remove Key"
        static let keychainRefused = "The Keychain refused the change."

        static func status(provider: Provider?, inKeychain: Bool, keychainRefused refused: Bool) -> SettingsStatus {
            let line: String
            if let provider {
                line = "An \(provider.name) key \(inKeychain ? "is saved in your Keychain" : "is held for this run only"). "
                    + "Paste a new one to replace it."
            } else {
                line = "No key saved. Ideator works without one; collapsed cards show “Summary unavailable”."
            }
            if refused { return .error("\(keychainRefused) \(line)") }
            return provider == nil ? .neutral(line) : .success(line)
        }
    }

    enum MCP {
        static let connectLabel = "Connect an AI tool"
        static let connectCaption = "Each button copies a tool's setup, for you to paste. Ideator never edits another app's config files."
        static let copied = "Copied"
        static let allow = "Let AI tools add cards"
        static let landingLabel = "Cards from AI tools go to:"
        static let top = "Top"
        static let bottom = "Bottom"
        static let instructionLabel = "Instruction for AI tools"
        static let limitName = "\(Instruction.byteLimit / 1_000) KB"
        static let instructionCaption = "Ideator gives an AI tool this text when a session starts, so an edit reaches it at its next "
            + "session. It holds up to \(limitName)."
        static let reset = "Reset to Default"

        static func copyLabel(for tool: AITool) -> String { "Copy setup for \(tool.name)" }

        static func connectStatus(isTemporary: Bool, copied: AITool?) -> SettingsStatus? {
            if isTemporary {
                return .warning("Ideator is running from a disk image, another volume or a quarantined download, so a "
                    + "setup copied now would point at a path that goes away. Move Ideator to Applications, open it from "
                    + "there, then copy a setup.")
            }
            return copied.map { .success("Copied for \($0.name). \($0.pasteNote)") }
        }

        static func instructionStatus(refused: Bool) -> SettingsStatus? {
            refused ? .error("That change would pass the \(limitName) limit, so Ideator did not make it.") : nil
        }
    }

    enum Updates {
        static let autoCheck = "Check for updates automatically"
        static let checkNow = "Check Now"
        static let asksBeforeInstalling = "Ideator asks before it installs an update."

        static func status(plan: UpdatePlan) -> SettingsStatus? {
            switch plan {
            case .check: nil
            case .off(.scratchRun): .neutral("A scratch run (-CardsFolder) doesn't check for updates.")
            case .off(.notPackaged): .neutral("Only builds made by scripts/package.sh check for updates.")
            }
        }
    }

    enum Privacy {
        static func page(for provider: Provider?) -> PrivacyPage {
            let who = provider?.name ?? "Anthropic or OpenAI, whichever your key is for"
            return PrivacyPage(headline: "Two things leave your Mac. Nothing else does.", items: [
                .init(term: "Card text",
                      text: "With a key saved, Ideator sends a card's text to \(who), using your own key, to write its "
                          + "summary. It does so whenever a card has no summary for its text as it is now: after you "
                          + "change a card, when you save a key, at launch after a failed try, and after an update that "
                          + "changes how Ideator asks for summaries."),
                .init(term: "Update checks",
                      text: "Once a day while automatic checks are on, and whenever you click Check Now, Ideator asks "
                          + "GitHub whether a newer version exists. GitHub sees your IP address and which version you have."),
                .init(term: "Your key", text: "The key stays in your login Keychain."),
                .init(term: "Nothing else", text: "No analytics, no crash reports."),
            ])
        }
    }
}
