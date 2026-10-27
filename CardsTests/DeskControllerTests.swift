import XCTest
@testable import Ideator

/// The controller in front of a folder that refuses: every alert goes through the `present` seam,
/// so a test answers it instead of a modal loop waiting for a click.
final class DeskControllerTests: XCTestCase {
    private var folder: URL!
    private var cardFile: URL { folder.appending(path: "card.md") }
    private let card = CardID(rawValue: "card")
    /// The message of each alert shown, in order.
    private var shown: [String] = []
    /// The answer to each coming alert, in order; the first button when the queue runs dry.
    private var answers: [NSApplication.ModalResponse] = []

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "CardsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# Groceries\n".utf8).write(to: cardFile)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeController() -> DeskController {
        DeskController(library: Library(folder: folder), keys: KeyStore(inKeychain: false), appMenu: { NSMenu() },
                       present: { [self] alert in
                           shown.append(alert.messageText)
                           return answers.isEmpty ? .alertFirstButtonReturn : answers.removeFirst()
                       })
    }

    private func makeFolder(writable: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: writable ? 0o755 : 0o555], ofItemAtPath: folder.path)
    }

    func testQuitWaitsWhileASaveFailsUnlessTheUserInsists() async throws {
        let controller = makeController()
        controller.send(.edit(card, Note(markdown: "# Groceries\n\neggs\n")))
        try makeFolder(writable: false)

        answers = [.alertFirstButtonReturn, .alertFirstButtonReturn]   // OK to the failure, then Cancel
        XCTAssertFalse(controller.shouldQuit(), "Cancel keeps Ideator open")
        XCTAssertEqual(shown, ["Ideator can't save your notes", "Quit without saving?"],
                       "the failed save is reported, then the question")
        XCTAssertEqual(try String(contentsOf: cardFile, encoding: .utf8), "# Groceries\n", "nothing reached the disk")

        answers = [.alertSecondButtonReturn]   // Quit Anyway
        XCTAssertTrue(controller.shouldQuit(), "Quit Anyway quits")
        XCTAssertEqual(shown, ["Ideator can't save your notes", "Quit without saving?", "Quit without saving?"],
                       "the failure is reported once per run, the question at every quit")
    }

    func testQuitSavesAndAsksNothingOnceTheFolderIsWritableAgain() async throws {
        let controller = makeController()
        controller.send(.edit(card, Note(markdown: "# Groceries\n\neggs\n")))
        try makeFolder(writable: false)
        XCTAssertFalse(controller.flush(), "the first save fails")
        try makeFolder(writable: true)

        XCTAssertTrue(controller.shouldQuit(), "the save at quit succeeds, so quitting goes ahead")

        XCTAssertEqual(shown, ["Ideator can't save your notes"], "and no question was asked")
        XCTAssertEqual(try String(contentsOf: cardFile, encoding: .utf8), "# Groceries\n\neggs\n",
                       "the edit is on disk")
    }

    func testQuitWithNothingToSaveAsksNothing() async throws {
        let controller = makeController()
        XCTAssertTrue(controller.shouldQuit())
        XCTAssertEqual(shown, [])
    }

    func testAFolderThatCannotBeListedIsReportedOnceAtLaunch() async throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: folder.path)
        let controller = makeController()
        XCTAssertEqual(shown, [], "the notice waits for launch to finish, like the newer-sidecar one")
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(shown, ["Ideator couldn't read your notes"])

        controller.send(.writeBlank(Note(markdown: "# Written meanwhile\n"), at: Date()))
        controller.flush()
        XCTAssertEqual(shown, ["Ideator couldn't read your notes"], "saving does not repeat it")
    }
}
