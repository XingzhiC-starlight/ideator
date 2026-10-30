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

    /// Whether each card the windows would show is collapsed: the popped cards, then the stack's.
    private func collapsedFaces(_ desk: Desk) -> [Bool] {
        desk.cardFaces(hasKey: false).map(\.face.collapsed) + (desk.stackFace(hasKey: false).selected.map { [$0.collapsed] } ?? [])
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

    func testAVersionOneSidecarLoadsAsNoSidecarEvenWithASlotPastAnyInteger() async throws {
        try Data("# A\n".utf8).write(to: folder.appending(path: "a.md"))
        try Data("# B\n".utf8).write(to: folder.appending(path: "b.md"))
        let old = #"{"version":1,"clarity":true,"stackSlot":7,"placements":[{"slot":9223372036854775807,"card":"a"},{"slot":3,"card":"b"}],"stack":[],"collapsed":["a"],"summaries":[]}"#
        try Data(old.utf8).write(to: folder.appending(path: ".cards.json"))

        let desk = Library(folder: folder).load()

        XCTAssertEqual(desk.poppedCards, [], "no card is placed from it")
        XCTAssertEqual(desk.stack.map(\.id.rawValue), ["a", "b"], "every card is in the stack, in id order")
        XCTAssertEqual(desk.stackPlace, .slot(Slot.stackHome), "the stack is at its home")
        XCTAssertFalse(desk.clarity, "Clarity is off")
        XCTAssertEqual(desk.stackFace(hasKey: false).selected?.collapsed, false, "and no card shows collapsed")
    }

    func testASidecarWithAPerCardCollapsedListStillLoadsAndTheListChangesNothing() async throws {
        try Data("# A\n".utf8).write(to: folder.appending(path: "a.md"))
        try Data("# B\n".utf8).write(to: folder.appending(path: "b.md"))
        let sidecar = folder.appending(path: ".cards.json")
        func load(clarity: Bool) throws -> Desk {
            let json = #"{"version":2,"clarity":\#(clarity),"stackSlot":7,"placements":[{"slot":3,"card":"b"}],"stack":["a"],"collapsed":["a"],"summaries":[]}"#
            try Data(json.utf8).write(to: sidecar)
            return Library(folder: folder).load()
        }

        let off = try load(clarity: false)
        XCTAssertEqual(off.place(of: .card(CardID(rawValue: "b"))), .slot(Slot(index: 3)!), "the places load")
        XCTAssertEqual(off.stack.map(\.id.rawValue), ["a"], "so does the stack")
        XCTAssertFalse(off.clarity)
        XCTAssertEqual(collapsedFaces(off), [false, false], "card a was listed as collapsed, and Clarity off shows it expanded")

        let on = try load(clarity: true)
        XCTAssertTrue(on.clarity)
        XCTAssertEqual(collapsedFaces(on), [true, true], "and Clarity on shows card b collapsed, though the list never named it")
    }

    func testASidecarFromBeforeSpreadStillLoadsItsPlaces() async throws {
        try Data("# A\n".utf8).write(to: folder.appending(path: "a.md"))
        try Data("# B\n".utf8).write(to: folder.appending(path: "b.md"))
        let json = #"{"version":2,"clarity":true,"stackSlot":7,"placements":[{"slot":3,"card":"b"}],"stack":["a"],"summaries":[]}"#
        try Data(json.utf8).write(to: folder.appending(path: ".cards.json"))

        let desk = Library(folder: folder).load()

        XCTAssertEqual(desk.place(of: .card(CardID(rawValue: "b"))), .slot(Slot(index: 3)!), "the places load")
        XCTAssertEqual(desk.stackPlace, .slot(Slot(index: 7)!), "so does the stack's")
        XCTAssertTrue(desk.clarity, "and Clarity")
        XCTAssertNil(desk.spreadSet, "with no Spread set")
    }

    func testASpreadSetSurvivesARelaunchInTheSameFormatVersion() async throws {
        try Data("# Groceries\n".utf8).write(to: cardFile)   // shown on top, as a relaunch shows it
        let library = Library(folder: folder)
        var desk = library.load()
        let cells = SpreadCells(indices: [0, 1])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        desk.apply(.spread(cells, fresh: false, at: now))
        desk.apply(.edit(desk.popped[1].card.id, Note(header: "Written", body: [])))
        desk.apply(.move(.card(desk.popped[0].card.id), to: .free(GridPoint(x: 0.47, y: 0.71))))
        desk.apply(.spread(cells, fresh: false, at: now))
        XCTAssertTrue(library.save(desk))

        let reopened = Library(folder: folder).load()
        XCTAssertEqual(reopened, desk, "the gathered set and where each card was come back")
        XCTAssertEqual(reopened.spreadSet?.cells, cells)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: ".cards.json"))) as? [String: Any]
        XCTAssertEqual(saved?["version"] as? Int, 2, "in the same format version")
    }

    func testASidecarsSetDropsJunkButKeepsAHomeAnotherCardNowTakes() async throws {
        for name in ["a", "s1", "s2"] { try Data("# \(name)\n".utf8).write(to: folder.appending(path: "\(name).md")) }
        let json = #"""
            {"version":2,"clarity":false,"placements":[{"slot":0,"card":"a"}],"stack":["s1","s2"],"summaries":[],
             "spread":{"cells":[1,0,99,1],"members":[{"slot":0,"card":"s1"},{"slot":3,"card":"ghost"},{"slot":5,"card":"s1"},
                                                     {"slot":25,"card":"s2"},{"free":{"x":0.31,"y":0.12},"card":"s2"}]}}
            """#
        try Data(json.utf8).write(to: folder.appending(path: ".cards.json"))

        let desk = Library(folder: folder).load()

        XCTAssertEqual(desk.place(of: .card(CardID(rawValue: "a"))), .slot(Slot(index: 0)!), "the places load")
        XCTAssertEqual(desk.spreadSet?.cells, SpreadCells(indices: [0, 1]), "a cell past the grid and a repeat are dropped")
        XCTAssertEqual(desk.spreadSet?.homes, [CardID(rawValue: "s1"): .slot(Slot(index: 0)!),
                                               CardID(rawValue: "s2"): .free(GridPoint(x: 0.31, y: 0.12))],
                       "so are a card that isn't there, a second entry and a slot past the grid, but s1 keeps the cell a holds")
    }

    func testClarityIsWhatTheSidecarSavesAndTheListIsGone() async throws {
        try Data("# Groceries\n".utf8).write(to: cardFile)
        let library = Library(folder: folder)
        var desk = library.load()
        desk.apply(.setClarity(true))
        XCTAssertTrue(library.save(desk))

        let reopened = Library(folder: folder).load()
        XCTAssertTrue(reopened.clarity, "Clarity is on after a relaunch")
        XCTAssertEqual(reopened.stackFace(hasKey: false).selected?.collapsed, true, "and the card shows collapsed")
        XCTAssertEqual(reopened, desk)

        desk.apply(.setClarity(false))
        XCTAssertTrue(library.save(desk))
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: ".cards.json"))) as? [String: Any]
        XCTAssertEqual(saved?["clarity"] as? Bool, false, "Clarity off is saved too")
        XCTAssertNil(saved?["collapsed"], "and no list of collapsed cards is written")
        XCTAssertEqual(saved?["version"] as? Int, 2, "in the same format version")
    }

    func testASidecarANewerIdeatorWritesAfterLaunchIsNotOverwritten() async throws {
        try Data("# Groceries\n".utf8).write(to: cardFile)
        let library = Library(folder: folder)
        var desk = library.load()
        desk.apply(.pop)
        XCTAssertTrue(library.save(desk), "this build writes its own sidecar first")
        XCTAssertFalse(library.sidecarIsNewer)
        // Another Mac's newer Ideator arranges the shared folder while this one keeps running.
        let sidecar = folder.appending(path: ".cards.json")
        let newer = Data(#"{"version":3,"layout":{"kind":"something this build has never seen"}}"#.utf8)
        try newer.write(to: sidecar)

        desk.apply(.setClarity(true))
        desk.apply(.edit(CardID(rawValue: "card"), Note(header: "Groceries", body: [Line(runs: [Run(text: "eggs")])])))
        XCTAssertTrue(library.save(desk), "leaving the newer sidecar alone is not a failed save")

        XCTAssertTrue(library.sidecarIsNewer, "the save noticed the newer sidecar")
        XCTAssertEqual(try Data(contentsOf: sidecar), newer, "and left it byte for byte")
        XCTAssertEqual(try String(contentsOf: cardFile, encoding: .utf8), "# Groceries\n\neggs\n",
                       "while the card still saved")
    }

    func testAFolderThatCannotBeListedOpensEmptyAndNeverOverwritesItsSidecar() async throws {
        try Data("# Groceries\n".utf8).write(to: cardFile)
        let arranged = Library(folder: folder)
        var earlier = arranged.load()
        earlier.apply(.pop)
        arranged.save(earlier)
        let sidecar = folder.appending(path: ".cards.json")
        let original = try Data(contentsOf: sidecar)
        // Writable but not listable, as a folder macOS has not let the app see yet.
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: folder.path)

        let library = Library(folder: folder)
        var desk = library.load()
        XCTAssertTrue(desk.allCards.isEmpty, "a folder that can't be listed opens empty rather than guessing")
        let written = Note(markdown: "# Written meanwhile\n")
        desk.apply(.writeBlank(written, at: Date()))
        library.save(desk)
        XCTAssertEqual(try Data(contentsOf: sidecar), original,
                       "a save never writes the sidecar over an arrangement it never read")

        // The folder becomes readable: the app saves, rescans and takes the files in, as on activation.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertTrue(library.save(desk), "the card written meanwhile saves once the folder allows it")
        let found = try XCTUnwrap(library.rescan(), "a rescan now lists the folder")
        XCTAssertEqual(found.count, 2, "and finds both cards")
        desk.apply(.syncFiles(found))
        XCTAssertTrue(library.save(desk), "saving the merged desk succeeds")
        XCTAssertEqual(try Data(contentsOf: sidecar), original,
                       "but still leaves the sidecar for the next launch, which read it, to update")

        let reopened = Library(folder: folder).load()
        XCTAssertEqual(reopened.popped.map(\.card.id), [CardID(rawValue: "card")],
                       "the next launch finds Groceries where it was")
        XCTAssertEqual(reopened.stack.map(\.note), [written], "and the card written meanwhile in the stack")
    }
}
