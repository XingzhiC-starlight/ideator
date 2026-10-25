import Foundation

/// What this build says about itself in its Info.plist. Only scripts/package.sh stamps the commit
/// it built from. A build from Xcode keeps the project's defaults ("none" and "unknown"), so it has
/// no stamp.
struct BuildInfo: Equatable {
    let version: String
    let number: String
    let stamp: Stamp?

    struct Stamp: Equatable {
        let commit: String
        let dirty: Bool

        /// Strict: a commit is 40 lowercase hex digits and the tree state is exactly YES or NO.
        /// "unknown" is the project default and never reads as clean.
        init?(commit: String?, dirty: String?) {
            guard let commit, commit.count == 40, commit.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
            switch dirty {
            case "YES": self.dirty = true
            case "NO": self.dirty = false
            default: return nil
            }
            self.commit = commit
        }
    }

    init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? "?"
        number = info["CFBundleVersion"] as? String ?? "?"
        stamp = Stamp(commit: info["IdeatorCommit"] as? String, dirty: info["IdeatorTreeDirty"] as? String)
    }

    static let current = BuildInfo(info: Bundle.main.infoDictionary ?? [:])

    /// "0.9 (57)". The version stays 0.9 across many builds, so the number tells them apart.
    var label: String { "\(version) (\(number))" }

    /// "Version 0.9 (57), commit 1a2b3c4", "… with local changes", or "Version 0.9 (1), a development build".
    var versionLine: String {
        guard let stamp else { return "Version \(label), a development build" }
        return "Version \(label), commit \(stamp.commit.prefix(7))" + (stamp.dirty ? " with local changes" : "")
    }
}
