import Foundation

/// What this build says about itself in its Info.plist. Only scripts/package.sh stamps the commit
/// it built from. A build from Xcode keeps the project's defaults ("none" and "unknown"), so it has
/// no stamp.
struct BuildInfo: Equatable {
    let version: String
    let number: String
    let stamp: Stamp?
    /// nil when the plist has no feed, or one this build may not use.
    let feed: Feed?
    /// A copy of the shipped app that a test pointed at a feed on this Mac. It has a bundle id of its
    /// own, so it never shares the owner's defaults.
    let isUpdateTest: Bool

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

    struct Feed: Equatable {
        let url: URL
        let publicKey: String

        /// Strict: https, or plain http to this Mac in an update-test build only, so a misbuilt
        /// release can never check over plain http. The key is a base64 Ed25519 public key.
        init?(url: String?, publicKey: String?, isUpdateTest: Bool) {
            guard let url, let parsed = URL(string: url), let host = parsed.host(), !host.isEmpty,
                  let publicKey, Data(base64Encoded: publicKey)?.count == 32 else { return nil }
            switch parsed.scheme {
            case "https": break
            case "http" where isUpdateTest && ["localhost", "127.0.0.1"].contains(host): break
            default: return nil
            }
            self.url = parsed
            self.publicKey = publicKey
        }
    }

    init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? "?"
        number = info["CFBundleVersion"] as? String ?? "?"
        stamp = Stamp(commit: info["IdeatorCommit"] as? String, dirty: info["IdeatorTreeDirty"] as? String)
        isUpdateTest = info["IdeatorUpdateTest"] as? String == "YES"
        feed = Feed(url: info["SUFeedURL"] as? String, publicKey: info["SUPublicEDKey"] as? String,
                    isUpdateTest: isUpdateTest)
    }

    static let current = BuildInfo(info: Bundle.main.infoDictionary ?? [:])

    /// "0.9 (57)". The version stays 0.9 across many builds, so the number tells them apart.
    static func label(version: String, number: String) -> String { "\(version) (\(number))" }
    var label: String { Self.label(version: version, number: number) }

    /// "Version 0.9 (57), commit 1a2b3c4", "… with local changes", or "Version 0.9 (1), a development build".
    var versionLine: String {
        guard let stamp else { return "Version \(label), a development build" }
        return "Version \(label), commit \(stamp.commit.prefix(7))" + (stamp.dirty ? " with local changes" : "")
    }

    /// A build without a stamp keeps build number 1, so every release would look newer and Sparkle
    /// would replace the copy Xcode built. Sparkle keeps its state in UserDefaults.standard, which in
    /// a scratch run of the real app is the owner's domain.
    func plan(isScratch: Bool) -> UpdatePlan {
        guard stamp != nil, let feed else { return .off(.notPackaged) }
        if isScratch && !isUpdateTest { return .off(.scratchRun) }
        return .check(feed)
    }
}

enum UpdatePlan: Equatable {
    case check(BuildInfo.Feed)
    case off(Reason)

    enum Reason: Equatable { case notPackaged, scratchRun }

    var checks: Bool { if case .check = self { true } else { false } }
}
