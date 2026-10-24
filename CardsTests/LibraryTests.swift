import XCTest
@testable import Ideator

final class LibraryTests: XCTestCase {
    private var folder: URL!
    private var cardFile: URL { folder.appending(path: "card.md") }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "CardsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    func testSaveRecreatesADeletedFolderWithEveryFile() async throws {
        let original = "# Groceries\n\n- eggs\n- milk\n"
        try Data(original.utf8).write(to: cardFile)
        let library = Library(folder: folder)
        var desk = library.load()
        desk.apply(.pop)
        library.save(desk)
        try FileManager.default.removeItem(at: folder)

        library.save(desk)

        XCTAssertEqual(try? String(contentsOf: cardFile, encoding: .utf8), original,
                       "the card file is back, byte for byte")
        XCTAssertEqual(Library(folder: folder).load(), desk,
                       "the sidecar is back too: a fresh load puts the card in the same slot")
    }

    func testSaveReportsFailureInAReadOnlyFolderAndSucceedsOnceItIsWritable() async throws {
        try Data("# Groceries\n".utf8).write(to: cardFile)
        let library = Library(folder: folder)
        var desk = library.load()
        desk.apply(.edit(CardID(rawValue: "card"), Note(header: "Groceries", body: [Line(runs: [Run(text: "eggs")])])))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        XCTAssertFalse(library.save(desk), "a changed card can't be written into a read-only folder")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertTrue(library.save(desk), "the same save succeeds once the folder is writable")
        XCTAssertEqual(try String(contentsOf: cardFile, encoding: .utf8), "# Groceries\n\neggs\n",
                       "and the card file holds the new text")
    }

    func testSaveOfAnUnchangedDeskWritesNothing() async throws {
        try Data("# Groceries\n\n- eggs\n".utf8).write(to: cardFile)
        let library = Library(folder: folder)
        var desk = library.load()
        desk.apply(.pop)
        XCTAssertTrue(library.save(desk), "the first save writes the sidecar")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2, "the card file and the sidecar are all there is")
        let longAgo = Date(timeIntervalSince1970: 1_000_000_000)
        for file in files {
            try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: file.path)
        }

        XCTAssertTrue(library.save(desk), "saving again succeeds")

        for file in files {
            let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
            XCTAssertEqual(modified, longAgo, "\(file.lastPathComponent) was not rewritten")
        }
    }

    func testANewerSidecarIsNeverOverwrittenWhileCardFilesStillSave() async throws {
        try Data("# Groceries\n".utf8).write(to: cardFile)
        let sidecar = folder.appending(path: ".cards.json")
        let newer = Data(#"{"version":3,"layout":{"kind":"something this build has never seen"}}"#.utf8)
        try newer.write(to: sidecar)
        let library = Library(folder: folder)
        var desk = library.load()
        XCTAssertTrue(library.sidecarIsNewer, "version 3 is newer than this build's sidecar")
        XCTAssertEqual(desk.stack.map(\.id), [CardID(rawValue: "card")], "the card still opens, in the stack")

        desk.apply(.pop)
        desk.apply(.edit(CardID(rawValue: "card"), Note(header: "Groceries", body: [Line(runs: [Run(text: "eggs")])])))

        XCTAssertTrue(library.save(desk), "leaving the sidecar alone is not a failed save")
        XCTAssertEqual(try Data(contentsOf: sidecar), newer, "the newer sidecar is byte for byte what it was")
        XCTAssertEqual(try String(contentsOf: cardFile, encoding: .utf8), "# Groceries\n\neggs\n",
                       "the edited card is saved")
    }

    func testOwnSidecarIsNotNewer() async throws {
        try Data("# Groceries\n".utf8).write(to: cardFile)
        let library = Library(folder: folder)
        var desk = library.load()
        desk.apply(.pop)
        library.save(desk)

        let reopened = Library(folder: folder)
        XCTAssertEqual(reopened.load(), desk, "the sidecar this build wrote places the card again")
        XCTAssertFalse(reopened.sidecarIsNewer, "and is not mistaken for a newer one")
    }
}
