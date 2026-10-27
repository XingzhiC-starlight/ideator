import AppKit
import Sparkle

/// Sparkle, for the life of the app, and the only file that imports it. With the plan off there is
/// no Sparkle object, so nothing is checked and nothing is written to the defaults. With it on, the
/// controller exists from launch, so Settings can show and change Sparkle's own setting while the
/// welcome is up, but `start()` waits for Launch.run's openNotes: no request leaves before the
/// welcome has said it will.
final class Updates: NSObject {
    let build: BuildInfo
    let plan: UpdatePlan
    private var controller: SPUStandardUpdaterController?
    /// A scheduled update Sparkle showed that the user has not looked at yet, as "0.9 (58)".
    private var waiting: String?

    init(build: BuildInfo, isScratch: Bool) {
        self.build = build
        plan = build.plan(isScratch: isScratch)
        super.init()
        if plan.checks {
            controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self,
                                                      userDriverDelegate: self)
        }
    }

    /// With no check on record, or a day since the last one, Sparkle checks right away.
    func start() { controller?.startUpdater() }

    /// Brings an update that is already showing forward instead of checking again.
    func checkNow() { controller?.checkForUpdates(nil) }

    /// False until `start()`, while Sparkle downloads in the background, and when the plan is off.
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Sparkle stores the choice in the app's defaults. Ideator keeps no copy.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var menuTitle: String { waiting.map { "Update to \($0)…" } ?? "Check for Updates…" }
}

extension Updates: SPUUpdaterDelegate {
    /// The feed in the signed Info.plist, always. Without this, a SUFeedURL default or launch
    /// argument would replace it.
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard case .check(let feed) = plan else { return nil }
        return feed.url.absoluteString
    }

    /// No system profile in the request, even if a SUSendProfileInfo default asks for one.
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
}

extension Updates: SPUStandardUserDriverDelegate {
    /// Ideator runs in the background, so a scheduled update that arrives after launch opens behind
    /// other apps, and the menu item names it until the user looks.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !state.userInitiated {
            waiting = BuildInfo.label(version: update.displayVersionString, number: update.versionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { waiting = nil }

    func standardUserDriverWillFinishUpdateSession() { waiting = nil }

    func standardUserDriverRequestsVersionDisplayer() -> (any SUVersionDisplay)? { self }
}

extension Updates: SUVersionDisplay {
    /// "0.9 (58)" against "0.9 (57)": every build is 0.9 for now, so only the numbers differ.
    func formatUpdateVersion(fromUpdate update: SUAppcastItem,
                             andBundleDisplayVersion inOutBundleDisplayVersion: AutoreleasingUnsafeMutablePointer<NSString>,
                             withBundleVersion bundleVersion: String) -> String {
        inOutBundleDisplayVersion.pointee = BuildInfo.label(version: inOutBundleDisplayVersion.pointee as String,
                                                            number: bundleVersion) as NSString
        return BuildInfo.label(version: update.displayVersionString, number: update.versionString)
    }
}
