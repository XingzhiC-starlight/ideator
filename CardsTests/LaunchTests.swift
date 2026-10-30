import XCTest
@testable import Ideator

final class LaunchTests: XCTestCase {
    private let suites = TestDefaults()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    /// `folder` is the `-CardsFolder` launch argument. `defaultFolder` is a `CardsFolder` key in the
    /// preferences, as `defaults write` leaves it.
    private func launch(folder: String? = nil, defaultFolder: String? = nil, updateTest: Bool = false,
                        environment: [String: String] = [:]) -> Launch {
        let defaults = suites.make()
        if let defaultFolder { defaults.set(defaultFolder, forKey: "CardsFolder") }
        return Launch(arguments: folder.map { ["CardsFolder": $0] } ?? [:], defaults: defaults,
                      build: BuildInfo(info: updateTest ? ["IdeatorUpdateTest": "YES"] : [:]),
                      environment: environment)
    }

    func testTheNotesAreInTheDocumentsFolderUnlessARunNamesAnother() {
        XCTAssertEqual(launch().notesFolder, Library.defaultFolder)
        XCTAssertFalse(launch().isScratch)

        let scratch = launch(folder: "/tmp/scratch-folder")
        XCTAssertEqual(scratch.notesFolder.path, "/tmp/scratch-folder")
        XCTAssertTrue(scratch.isScratch)
    }

    func testACardsFolderDefaultInThePreferencesIsNotAScratchRun() {
        let stray = launch(defaultFolder: "/tmp/stray-folder")

        XCTAssertFalse(stray.isScratch)
        XCTAssertEqual(stray.notesFolder, Library.defaultFolder)
    }

    func testALaunchArgumentIsAScratchRunWhateverThePreferencesHold() {
        let both = launch(folder: "/tmp/scratch-folder", defaultFolder: "/tmp/stray-folder")

        XCTAssertTrue(both.isScratch)
        XCTAssertEqual(both.notesFolder.path, "/tmp/scratch-folder")
    }

    func testAnUpdateTestCopyAlsoKeepsItsFolderInItsOwnPreferences() {
        let relaunchedBySparkle = launch(defaultFolder: "/tmp/update-test-folder", updateTest: true)

        XCTAssertTrue(relaunchedBySparkle.isScratch)
        XCTAssertEqual(relaunchedBySparkle.notesFolder.path, "/tmp/update-test-folder")
        XCTAssertFalse(launch(updateTest: true).isScratch)
    }

    func testAScratchRunReadsTheFactoryShortcutAndWritesNothingToTheOwnersDefaults() {
        let owners = suites.make()
        let preferences = launch(folder: "/tmp/scratch-folder").preferences(standard: owners)

        preferences.shortcut = Shortcut(keyCode: 4, modifiers: 4352)!
        preferences.markWelcomeSeen()

        XCTAssertEqual(preferences.shortcut, .standard)
        XCTAssertNil(owners.object(forKey: "Shortcut"))
        XCTAssertNil(owners.object(forKey: "WelcomeSeen"))
        XCTAssertNil(owners.object(forKey: "TourSeen"))
    }

    func testAScratchRunGetsAnEmptyKeyStoreThatNeverTouchesTheKeychain() {
        let keys = launch(folder: "/tmp/scratch-folder").keys()

        XCTAssertFalse(keys.inKeychain)
        XCTAssertNil(keys.apiKey)
    }

    func testAKeySavedInAScratchRunIsHeldForThatRunOnly() {
        let keys = launch(folder: "/tmp/scratch-folder").keys()

        XCTAssertTrue(keys.set("  sk-ant-test\n"))
        XCTAssertEqual(keys.apiKey, "sk-ant-test")
        XCTAssertNil(launch(folder: "/tmp/scratch-folder").keys().apiKey)

        XCTAssertTrue(keys.set(""))
        XCTAssertNil(keys.apiKey)
    }

    func testAnOrdinaryRunKeepsTheShortcutAcrossLaunches() {
        let owners = suites.make()
        let chosen = Shortcut(keyCode: 4, modifiers: 4352)!

        launch().preferences(standard: owners).shortcut = chosen

        XCTAssertEqual(launch().preferences(standard: owners).shortcut, chosen)
    }

    func testADamagedStoredShortcutFallsBackToTheStandardOne() {
        let owners = suites.make()
        owners.set(["keyCode": 1], forKey: "Shortcut")

        XCTAssertEqual(Preferences(defaults: owners).shortcut, .standard)
    }

    // MARK: Which welcome a launch shows

    private let forced = ["CARDS_SHOW_WELCOME": "1"]
    private let background = [HandOff.backgroundVariable: "1"]

    /// Preferences as an owner's Mac holds them: the disclosure version they acknowledged (nil: never)
    /// and whether the tour was offered.
    private func owner(disclosure: Int? = nil, tour: Bool = false) -> (preferences: Preferences, defaults: UserDefaults) {
        let defaults = suites.make()
        if let disclosure { defaults.set(disclosure, forKey: "WelcomeSeen") }
        if tour { defaults.set(true, forKey: "TourSeen") }
        return (Preferences(defaults: defaults), defaults)
    }

    /// What a launch did, in order, and the welcome's button. Bind it to a `let` before asserting on
    /// it: a main-actor object released inside an assertion crashes the test host.
    private final class Run {
        var steps: [String] = []
        var kind: WelcomeKind?
        var choose: ((WelcomeChoice) -> Void)?
    }

    private func run(_ launch: Launch, _ preferences: Preferences) -> Run {
        let run = Run()
        launch.run(preferences: preferences,
                   welcome: { kind, choose in
                       run.steps.append("welcome")
                       run.kind = kind
                       run.choose = { choice in
                           run.steps.append("button")
                           choose(choice)
                       }
                   },
                   openNotes: { run.steps.append("openNotes") },
                   startTour: { run.steps.append("tour \($0)") })
        return run
    }

    func testAFreshMacGetsTheFullTourWelcome() {
        let fresh = owner()

        XCTAssertEqual(launch().welcome(for: fresh.preferences.records), .fullTour)
    }

    func testAnOwnerOfAnEarlierBuildGetsTheFullTourOnceEvenWithTheCurrentDisclosureAcknowledged() {
        let earlier = owner(disclosure: WelcomeCopy.version)
        XCTAssertEqual(launch().welcome(for: earlier.preferences.records), .fullTour,
                       "the tour flag is absent on every owner's first launch of the build that has the tour")

        let first = run(launch(), earlier.preferences)
        first.choose?(.start)
        XCTAssertEqual(first.kind, .fullTour)
        let second = run(launch(), earlier.preferences)
        XCTAssertEqual(second.steps, ["openNotes"], "offered once, then quiet")
    }

    func testAnOwnerWhoSawAnOlderWelcomeIsAskedAgainOnce() {
        let old = owner()
        old.defaults.set(true, forKey: "WelcomeSeen")   // what every build before the card was versioned wrote

        let first = run(launch(), old.preferences)
        XCTAssertEqual(first.kind, .fullTour, "the old flag is not consent to what the welcome says now")
        first.choose?(.skip)
        let second = run(launch(), old.preferences)
        XCTAssertEqual(second.steps, ["openNotes"], "Skip is remembered")
    }

    func testAnOwnerWhoSawTheTourButAnOlderDisclosureGetsTheContinueOnlyWelcomeAndNoTour() {
        let owners = owner(disclosure: 1, tour: true)
        XCTAssertEqual(launch().welcome(for: owners.preferences.records), .noTour)

        let shown = run(launch(), owners.preferences)
        shown.choose?(.proceed)

        XCTAssertEqual(shown.kind, .noTour)
        XCTAssertEqual(shown.steps, ["welcome", "button", "openNotes"], "no tour follows")
        XCTAssertEqual(owners.defaults.integer(forKey: "WelcomeSeen"), WelcomeCopy.version, "Continue is remembered")
        let again = run(launch(), owners.preferences)
        XCTAssertEqual(again.steps, ["openNotes"])
    }

    func testAnOwnerWithBothRecordsCurrentSeesNothing() {
        let current = owner(disclosure: WelcomeCopy.version, tour: true)

        XCTAssertNil(launch().welcome(for: current.preferences.records))
        let opened = run(launch(), current.preferences)
        XCTAssertEqual(opened.steps, ["openNotes"], "the notes open at once")
    }

    func testBothRecordsNewerThanThisBuildsShowNothingAndStayNewer() {
        let newer = owner(disclosure: 99, tour: true)

        let quiet = run(launch(), newer.preferences)
        XCTAssertEqual(quiet.steps, ["openNotes"], "an older build run after a newer one stays quiet")
        XCTAssertEqual(newer.defaults.integer(forKey: "WelcomeSeen"), 99)

        let forcedRun = run(launch(environment: forced), newer.preferences)
        forcedRun.choose?(.start)
        XCTAssertEqual(newer.defaults.integer(forKey: "WelcomeSeen"), 99, "a forced welcome never lowers the acknowledged version")
    }

    func testABackgroundStartWhileTheTourIsDueShowsContinueAloneAndEndsOnTheLastPage() {
        let fresh = owner()
        let helper = launch(environment: background)
        XCTAssertEqual(helper.welcome(for: fresh.preferences.records), .endOnly)

        let shown = run(helper, fresh.preferences)
        shown.choose?(.proceed)

        XCTAssertEqual(shown.steps, ["welcome", "button", "openNotes", "tour lastPage"])
        XCTAssertFalse(helper.welcomeTakesFocus, "a Return typed in the AI tool never presses Continue")
        XCTAssertTrue(fresh.defaults.bool(forKey: "TourSeen"), "and the tour is not offered again")
    }

    func testABackgroundStartForAnOwnerWhoOnlyNeedsTheNewDisclosureHasNoTourAndSomeoneUpToDateSeesNothing() {
        let stale = owner(disclosure: 1, tour: true)
        XCTAssertEqual(launch(environment: background).welcome(for: stale.preferences.records), .noTour)

        let current = owner(disclosure: WelcomeCopy.version, tour: true)
        XCTAssertNil(launch(environment: background).welcome(for: current.preferences.records))
    }

    func testAScratchRunShowsNoWelcomeAndNoTour() {
        let scratch = launch(folder: "/tmp/scratch-folder")
        let preferences = scratch.preferences(standard: suites.make())

        XCTAssertEqual(preferences.records, LaunchRecords(disclosureCurrent: true, tourSeen: true))
        XCTAssertNil(scratch.welcome(for: preferences.records))
        let opened = run(scratch, preferences)
        XCTAssertEqual(opened.steps, ["openNotes"])
    }

    func testTheEnvironmentForcesTheFullTourEvenInAScratchRunAndRecordsNothing() {
        let owners = suites.make()
        let scratch = launch(folder: "/tmp/scratch-folder", environment: forced)
        let preferences = scratch.preferences(standard: owners)

        let shown = run(scratch, preferences)
        XCTAssertEqual(shown.kind, .fullTour)
        shown.choose?(.start)

        XCTAssertEqual(shown.steps, ["welcome", "button", "openNotes", "tour firstPage"])
        XCTAssertNil(owners.object(forKey: "WelcomeSeen"), "a scratch run writes nothing")
        XCTAssertNil(owners.object(forKey: "TourSeen"))
    }

    func testAnOwnerWhoHasSeenEverythingSeesTheFullTourAgainOnRequest() {
        let current = owner(disclosure: WelcomeCopy.version, tour: true)

        let shown = run(launch(environment: forced), current.preferences)
        shown.choose?(.start)

        XCTAssertEqual(shown.kind, .fullTour)
        XCTAssertEqual(shown.steps, ["welcome", "button", "openNotes", "tour firstPage"])
    }

    func testAForcedBackgroundStartStillEndsOnTheLastPage() {
        let current = owner(disclosure: WelcomeCopy.version, tour: true)
        let helper = launch(environment: forced.merging(background) { $1 })

        XCTAssertEqual(helper.welcome(for: current.preferences.records), .endOnly)
    }

    func testEachButtonSaysWhereTheTourStarts() {
        XCTAssertEqual(WelcomeKind.fullTour.tourStart(after: .start), .firstPage)
        XCTAssertEqual(WelcomeKind.fullTour.tourStart(after: .skip), .lastPage)
        XCTAssertEqual(WelcomeKind.endOnly.tourStart(after: .proceed), .lastPage)
        XCTAssertNil(WelcomeKind.noTour.tourStart(after: .proceed))
    }

    func testTheFolderStaysClosedUntilAButtonAndOpensOnceWhicheverButtonsArePressed() {
        let fresh = owner()
        let shown = run(launch(), fresh.preferences)
        XCTAssertEqual(shown.steps, ["welcome"], "the welcome is shown first, and nothing opens the folder before a button")

        shown.choose?(.start)
        shown.choose?(.skip)
        shown.choose?(.start)

        XCTAssertEqual(shown.steps.filter { $0 == "openNotes" }.count, 1, "Return and a click open it once")
        XCTAssertEqual(shown.steps.filter { $0.hasPrefix("tour") }, ["tour firstPage"], "and the first button's tour is the one that starts")
    }

    func testBothRecordsAreWrittenAfterTheNotesOpenAndBeforeTheTourStarts() {
        let fresh = owner()
        var recordsWhile: [String: Bool] = [:]
        var choose: ((WelcomeChoice) -> Void)?

        launch().run(preferences: fresh.preferences, welcome: { _, button in choose = button },
                     openNotes: {
                         recordsWhile["disclosure while opening"] = fresh.preferences.welcomeSeen
                         recordsWhile["tour while opening"] = fresh.preferences.tourSeen
                     },
                     startTour: { _ in
                         recordsWhile["disclosure at the tour"] = fresh.preferences.welcomeSeen
                         recordsWhile["tour at the tour"] = fresh.preferences.tourSeen
                     })
        XCTAssertFalse(fresh.preferences.welcomeSeen, "showing the welcome acknowledges nothing")
        XCTAssertFalse(fresh.preferences.tourSeen)

        choose?(.start)

        XCTAssertEqual(recordsWhile, ["disclosure while opening": false, "tour while opening": false,
                                      "disclosure at the tour": true, "tour at the tour": true],
                       "a launch killed in the Documents prompt shows the welcome again, and a run that quits mid-tour does not replay it")
    }

    func testAnOwnerWhoQuitDuringTheWelcomeSeesItAgainAndNothingWasOpened() {
        let fresh = owner()
        var shown = 0

        for _ in 1...2 {
            let attempt = run(launch(), fresh.preferences)
            if attempt.kind == .fullTour { shown += 1 }
            XCTAssertEqual(attempt.steps, ["welcome"])
        }

        XCTAssertEqual(shown, 2)
    }

    func testMarkingTheWelcomeSeenNeverLowersTheAcknowledgedVersionAndWritesTheTourFlag() {
        let newer = owner(disclosure: 99)
        newer.preferences.markWelcomeSeen()

        XCTAssertEqual(newer.defaults.integer(forKey: "WelcomeSeen"), 99)
        XCTAssertTrue(newer.defaults.bool(forKey: "TourSeen"))

        let fresh = owner()
        fresh.preferences.markWelcomeSeen()
        XCTAssertEqual(fresh.defaults.integer(forKey: "WelcomeSeen"), WelcomeCopy.version)
        XCTAssertEqual(fresh.preferences.records, LaunchRecords(disclosureCurrent: true, tourSeen: true))
    }
}

