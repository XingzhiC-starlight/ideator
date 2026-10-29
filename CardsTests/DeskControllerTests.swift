import XCTest
@testable import Ideator

/// A point no screen reaches, so no card is under it.
private let offScreen = NSPoint(x: -10_000, y: -10_000)

/// The controller in front of a folder that refuses: every alert goes through the `present` seam,
/// so a test answers it instead of a modal loop waiting for a click. The pointer goes through its
/// own seam, so a test places it where the real one cannot be put.
final class DeskControllerTests: XCTestCase {
    private var folder: URL!
    private var cardFile: URL { folder.appending(path: "card.md") }
    private let card = CardID(rawValue: "card")
    /// The message of each alert shown, in order.
    private var shown: [String] = []
    /// The answer to each coming alert, in order; the first button when the queue runs dry.
    private var answers: [NSApplication.ModalResponse] = []
    private var windowsBefore: [NSWindow] = []
    /// Kept until `tearDown` has closed their windows, which hold them `unowned`.
    private var controllers: [DeskController] = []

    override func setUpWithError() throws {
        windowsBefore = NSApp.windows
        folder = FileManager.default.temporaryDirectory
            .appending(path: "CardsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# Groceries\n".utf8).write(to: cardFile)
    }

    override func tearDown() async throws {
        for window in NSApp.windows where !windowsBefore.contains(window) {
            window.orderOut(nil)
            window.close()
        }
        let left = NSApp.windows.filter { $0.isVisible && !windowsBefore.contains($0) }
        XCTAssertEqual(left.map(\.className), [], "a window left on screen sends a click to a controller that is gone")
        controllers = []
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeController(pointer: @escaping () -> NSPoint = { offScreen }) -> DeskController {
        let controller = DeskController(library: Library(folder: folder), keys: KeyStore(inKeychain: false), appMenu: { NSMenu() },
                                        present: { [self] alert in
                                            shown.append(alert.messageText)
                                            return answers.isEmpty ? .alertFirstButtonReturn : answers.removeFirst()
                                        },
                                        pointer: pointer)
        controllers.append(controller)
        return controller
    }

    private func makeFolder(writable: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: writable ? 0o755 : 0o555], ofItemAtPath: folder.path)
    }

    private func write(_ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: folder.appending(path: name))
    }

    private func note(of id: CardID, in controller: DeskController) -> Note? {
        controller.desk.allCards.first { $0.id == id }?.note
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

    func testBecomingActiveAfterAFailedSaveKeepsWhatIsUnsavedInsteadOfRescanningIt() async throws {
        let controller = makeController()
        let edited = Note(markdown: "# Groceries\n\neggs\n")
        let written = Note(markdown: "# Written meanwhile\n")
        controller.send(.edit(card, edited))
        controller.send(.flipStack(.previous))   // writeBlank applies only on the blank page
        controller.send(.writeBlank(written, at: Date()))
        try makeFolder(writable: false)

        controller.appDidBecomeActive()

        XCTAssertEqual(note(of: card, in: controller), edited, "the stale file did not replace the edit")
        XCTAssertTrue(controller.desk.allCards.contains { $0.note == written }, "the unwritten card was not deleted")
        XCTAssertEqual(try String(contentsOf: cardFile, encoding: .utf8), "# Groceries\n", "nothing reached the disk")
        XCTAssertEqual(shown, ["Ideator can't save your notes"], "the failed save was reported")
    }

    func testBecomingActiveSavesTheEditThenTakesInWhatChangedOutsideTheApp() async throws {
        try write("other.md", "# Other\n")
        let controller = makeController()
        let edited = Note(markdown: "# Groceries\n\neggs\n")
        controller.send(.edit(card, edited))
        try makeFolder(writable: false)
        controller.appDidBecomeActive()
        try makeFolder(writable: true)
        try write("other.md", "# Other\n\nedited elsewhere\n")
        try write("added.md", "# Added elsewhere\n")

        controller.appDidBecomeActive()

        XCTAssertEqual(try String(contentsOf: cardFile, encoding: .utf8), "# Groceries\n\neggs\n", "the edit is on disk")
        XCTAssertEqual(note(of: card, in: controller), edited, "and the rescan did not undo it")
        XCTAssertEqual(note(of: CardID(rawValue: "other"), in: controller), Note(markdown: "# Other\n\nedited elsewhere\n"),
                       "the file edited outside replaced the card's text")
        XCTAssertEqual(note(of: CardID(rawValue: "added"), in: controller), Note(markdown: "# Added elsewhere\n"),
                       "the file added outside became a card")
    }

    func testADeletedCardLeavesTheFolderAndTheOthersStay() async throws {
        try write("doomed.md", "# Delete me (an Ideator test)\n")
        let controller = makeController()

        controller.send(.delete(CardID(rawValue: "doomed")))
        XCTAssertTrue(controller.flush())

        // The file goes to the Trash, the user's own, so the test checks only that it left the folder.
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "doomed.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cardFile.path), "the other card's file stayed")
        XCTAssertEqual(controller.desk.allCards.map(\.id), [card])
    }

    func testEveryRenderChecksHoverAgainstThePointerThatRests() async throws {
        var pointer = offScreen
        let controller = makeController(pointer: { pointer })
        let slot = controller.grid.frame(of: try XCTUnwrap(controller.desk.firstFreeSlot))
        let insideSlot = NSPoint(x: slot.midX, y: slot.midY)

        pointer = insideSlot
        controller.send(.pop)
        let windows = NSApp.windows.compactMap { $0 as? CardWindow }.filter(\.isVisible)
        XCTAssertEqual(windows.count, 1, "Pop puts the one card on the desktop")
        let window = try XCTUnwrap(windows.first)
        try expectHoverButtons(shown: true, in: window, "Pop put the card under a pointer that rests")

        pointer = offScreen
        controller.send(.toggleClarity)
        try expectHoverButtons(shown: false, in: window, "the pointer rests away from the card")

        pointer = insideSlot
        controller.send(.toggleClarity)
        try expectHoverButtons(shown: true, in: window, "the pointer rests on the card again")
    }

    /// What the user can tell about the card's buttons: a press at Delete's point reaches the button
    /// only while they are shown, and their row is opaque or clear.
    private func expectHoverButtons(shown: Bool, in window: NSWindow, _ context: String) throws {
        window.contentView!.layoutSubtreeIfNeeded()
        let delete = try XCTUnwrap(button("Delete this card", under: window.contentView!))
        let point = delete.convert(NSPoint(x: delete.bounds.midX, y: delete.bounds.midY), to: nil)
        XCTAssertEqual(window.contentView!.hitTest(point) === delete, shown,
                       "\(context): a press on Delete should \(shown ? "reach it" : "go to the card under it")")
        let row = try XCTUnwrap(delete.superview)
        XCTAssertEqual(row.alphaValue, shown ? 1 : 0, "\(context): the buttons should be \(shown ? "shown" : "hidden")")
    }

    private func button(_ tooltip: String, under view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.toolTip == tooltip { return button }
        return view.subviews.lazy.compactMap { self.button(tooltip, under: $0) }.first
    }
}
