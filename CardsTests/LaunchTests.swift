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

    func testAFreshOwnerSeesTheWelcomeUntilItIsAcknowledged() {
        let owners = suites.make()
        let launch = launch()

        XCTAssertTrue(launch.showsWelcome(seen: launch.preferences(standard: owners).welcomeSeen))

        launch.preferences(standard: owners).markWelcomeSeen()

        XCTAssertFalse(launch.showsWelcome(seen: launch.preferences(standard: owners).welcomeSeen))
    }

    func testAnOwnerWhoSawAnOlderWelcomeSeesTheCurrentOneOnce() {
        let owners = suites.make()
        owners.set(true, forKey: "WelcomeSeen")   // what every build before the card was versioned wrote
        var shown = 0
        var opened = 0

        launch().run(preferences: launch().preferences(standard: owners),
                     welcome: { onContinue in shown += 1; onContinue() }, openNotes: { opened += 1 })
        XCTAssertEqual([shown, opened], [1, 1], "the old flag is not consent to what the card says now")

        launch().run(preferences: launch().preferences(standard: owners),
                     welcome: { _ in shown += 1 }, openNotes: { opened += 1 })
        XCTAssertEqual([shown, opened], [1, 2], "Continue is remembered")
    }

    func testAnOwnerWhoSawAWelcomeWithMoreInItIsNotAskedAgain() {
        let owners = suites.make()
        owners.set(99, forKey: "WelcomeSeen")
        var shown = 0
        var opened = 0

        launch().run(preferences: launch().preferences(standard: owners),
                     welcome: { _ in shown += 1 }, openNotes: { opened += 1 })

        XCTAssertEqual([shown, opened], [0, 1], "an older build run after a newer one stays quiet")
    }

    func testAScratchRunShowsNoWelcome() {
        let scratch = launch(folder: "/tmp/scratch-folder")

        XCTAssertFalse(scratch.showsWelcome(seen: scratch.preferences(standard: suites.make()).welcomeSeen))
    }

    func testTheEnvironmentForcesTheWelcomeEvenInAScratchRunAndEvenAfterItWasSeen() {
        let owners = suites.make()
        let forced = launch(folder: "/tmp/scratch-folder", environment: ["CARDS_SHOW_WELCOME": "1"])
        var shown = 0
        var opened = 0

        forced.run(preferences: forced.preferences(standard: owners),
                   welcome: { onContinue in shown += 1; onContinue() }, openNotes: { opened += 1 })

        XCTAssertEqual([shown, opened], [1, 1])
        XCTAssertNil(owners.object(forKey: "WelcomeSeen"), "Continue in a scratch run writes nothing")

        let seen = Preferences(defaults: suites.make())
        seen.markWelcomeSeen()
        launch(environment: ["CARDS_SHOW_WELCOME": "1"]).run(preferences: seen,
                                                              welcome: { _ in shown += 1 }, openNotes: { opened += 1 })
        XCTAssertEqual([shown, opened], [2, 1], "an owner who has seen it sees it again on request")
    }

    func testTheFolderStaysClosedUntilContinueAndOpensOnce() {
        let preferences = Preferences(defaults: suites.make())
        var onContinue: (() -> Void)?
        var opened = 0

        launch().run(preferences: preferences, welcome: { onContinue = $0 }, openNotes: { opened += 1 })
        XCTAssertNotNil(onContinue, "the welcome is shown first")
        XCTAssertEqual(opened, 0, "nothing opens the folder before Continue")

        onContinue?()
        onContinue?()
        XCTAssertEqual(opened, 1, "Return and a click on Continue open it once")
    }

    func testTheFlagIsSetAfterTheNotesOpenAndNotBeforeContinue() {
        let preferences = Preferences(defaults: suites.make())
        var onContinue: (() -> Void)?
        var seenWhileOpening: Bool?

        launch().run(preferences: preferences, welcome: { onContinue = $0 },
                     openNotes: { seenWhileOpening = preferences.welcomeSeen })
        XCTAssertFalse(preferences.welcomeSeen, "showing the welcome acknowledges nothing")

        onContinue?()

        XCTAssertEqual(seenWhileOpening, false, "a launch killed in the Documents prompt shows the welcome again")
        XCTAssertTrue(preferences.welcomeSeen)
    }

    func testAnOwnerWhoQuitDuringTheWelcomeSeesItAgainAndNothingWasOpened() {
        let owners = suites.make()
        var shown = 0
        var opened = 0

        for _ in 1...2 {
            launch().run(preferences: launch().preferences(standard: owners),
                         welcome: { _ in shown += 1 }, openNotes: { opened += 1 })
        }

        XCTAssertEqual([shown, opened], [2, 0])
    }

    func testNoWelcomeOpensTheNotesStraightAway() {
        let preferences = Preferences(defaults: suites.make())
        preferences.markWelcomeSeen()
        var shown = 0
        var opened = 0

        launch().run(preferences: preferences, welcome: { _ in shown += 1 }, openNotes: { opened += 1 })

        XCTAssertEqual([shown, opened], [0, 1])
    }
}
