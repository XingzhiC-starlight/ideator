import XCTest
@testable import Ideator

final class LaunchTests: XCTestCase {
    private let suites = TestDefaults()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func scratchRun() -> Launch {
        let arguments = suites.make()
        arguments.set("/tmp/scratch-folder", forKey: "CardsFolder")
        return Launch(arguments: arguments)
    }

    func testTheNotesAreInTheDocumentsFolderUnlessARunNamesAnother() {
        XCTAssertEqual(Launch(arguments: suites.make()).notesFolder, Library.defaultFolder)
        XCTAssertFalse(Launch(arguments: suites.make()).isScratch)

        let scratch = scratchRun()
        XCTAssertEqual(scratch.notesFolder.path, "/tmp/scratch-folder")
        XCTAssertTrue(scratch.isScratch)
    }

    func testAScratchRunReadsTheFactoryShortcutAndWritesNothingToTheOwnersDefaults() {
        let owners = suites.make()
        let preferences = scratchRun().preferences(standard: owners)

        preferences.shortcut = Shortcut(keyCode: 4, modifiers: 4352)!

        XCTAssertEqual(preferences.shortcut, .standard)
        XCTAssertNil(owners.object(forKey: "Shortcut"))
    }

    func testAnOrdinaryRunKeepsTheShortcutAcrossLaunches() {
        let owners = suites.make()
        let launch = Launch(arguments: suites.make())
        let chosen = Shortcut(keyCode: 4, modifiers: 4352)!

        launch.preferences(standard: owners).shortcut = chosen

        XCTAssertEqual(launch.preferences(standard: owners).shortcut, chosen)
    }

    func testADamagedStoredShortcutFallsBackToTheStandardOne() {
        let owners = suites.make()
        owners.set(["keyCode": 1], forKey: "Shortcut")

        XCTAssertEqual(Preferences(defaults: owners).shortcut, .standard)
    }
}
