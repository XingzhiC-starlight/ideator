import Carbon.HIToolbox
import XCTest
@testable import Ideator

final class SpreadSettingsTests: XCTestCase {
    private let suites = TestDefaults()

    override func tearDown() {
        suites.removeAll()
    }

    private func settings(_ choice: SpreadChoice, stackCell: @escaping () -> Slot = { Slot.stackHome }) -> SettingsWindow {
        SettingsWindow(keys: KeyStore(inKeychain: false), hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                       updates: Updates(build: .current, isScratch: true), spread: choice, stackCell: stackCell) {}
    }

    /// Every view under `view` in reading order: each view, then what it holds.
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    /// The grid's cell `n`, 1 to 20 in reading order, as VoiceOver and cards-verify name it.
    private func cell(_ n: Int, in window: SettingsWindow) throws -> NSButton {
        try XCTUnwrap(descendants(of: window.contentView!).compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Spread cell \(n)" }, "Spread cell \(n)")
    }

    private func ticked(in window: SettingsWindow) throws -> [Int] {
        try (1...20).filter { try cell($0, in: window).state == .on }
    }

    private func picker(in window: SettingsWindow) throws -> SpreadCellPicker {
        try XCTUnwrap(descendants(of: window.pane(.spread)).compactMap { $0 as? SpreadCellPicker }.first)
    }

    private func key(_ code: Int, _ characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                       characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                                       keyCode: UInt16(code)))
    }

    func testTheGridsCellsSitOnAnEvenLatticeAtTheLeftOfTheSection() throws {
        let window = settings(SpreadChoice(preferences: Preferences(defaults: nil)))
        let frames = try (1...20).map { n -> NSRect in
            let button = try cell(n, in: window)
            return button.superview!.convert(button.alignmentRect(forFrame: button.frame), to: nil)
        }
        let columns = Slot.columns
        let step = SpreadCellPicker.cellSize.width + SpreadCellPicker.spacing
        for (n, frame) in frames.enumerated() {
            XCTAssertEqual(frame.size, SpreadCellPicker.cellSize, "cell \(n + 1) keeps its size")
            if n % columns > 0 {
                XCTAssertEqual(frame.minX - frames[n - 1].minX, step, accuracy: 0.5, "cell \(n + 1) is one step right of cell \(n)")
            } else if n > 0 {
                XCTAssertEqual(frame.minX, frames[0].minX, accuracy: 0.5, "cell \(n + 1) starts its row under cell 1")
            }
        }
        let rowStep = frames[columns].minY - frames[0].minY
        for row in 1..<Slot.rows {
            XCTAssertEqual(frames[row * columns].minY - frames[(row - 1) * columns].minY, rowStep, accuracy: 0.5, "row \(row + 1)")
        }
    }

    func testTheSpreadPaneHasItsTitleAndLeadThenTheGridThenTheCaption() throws {
        let window = settings(SpreadChoice(preferences: Preferences(defaults: nil)))
        let views = descendants(of: window.pane(.spread))
        func index(_ match: (NSView) -> Bool, _ name: String) throws -> Int { try XCTUnwrap(views.firstIndex(where: match), name) }
        func label(_ text: String) throws -> Int { try index({ ($0 as? NSTextField)?.stringValue == text }, text) }
        let firstCell = try index({ ($0 as? NSButton)?.accessibilityLabel() == "Spread cell 1" }, "the first cell")
        XCTAssertLessThan(try label("Spread"), try label("Spread, on the stack's ribbon, puts a new card in each ticked cell."))
        XCTAssertLessThan(try label("Spread, on the stack's ribbon, puts a new card in each ticked cell."), firstCell)
        XCTAssertLessThan(firstCell, try label(SettingsCopy.Spread.caption), "the caption is under the grid")
    }

    func testTheGridShowsTheTickedCellsAndTheStacksCellCantBeTicked() throws {
        var stackCell = Slot.stackHome
        let choice = SpreadChoice(preferences: Preferences(defaults: nil))
        let window = settings(choice, stackCell: { stackCell })
        XCTAssertEqual(try ticked(in: window), [1, 2, 3, 6, 7, 8], "the factory cells")
        XCTAssertFalse(try cell(5, in: window).isEnabled, "the stack's cell, top right")
        XCTAssertNotNil(try cell(5, in: window).image, "shows the stack")

        stackCell = Slot(index: 7)!   // the stack moved onto a ticked cell while Settings was closed
        window.becomeKey()
        XCTAssertFalse(try cell(8, in: window).isEnabled, "the stack's cell is read again")
        XCTAssertEqual(try ticked(in: window), [1, 2, 3, 6, 7], "and shows unticked")
        XCTAssertTrue(try cell(5, in: window).isEnabled, "the cell it left can be ticked")
        XCTAssertEqual(choice.cells, .standard, "nothing is unticked in storage")
    }

    func testAClickTicksOrUnticksACellAndTheCaptionFollows() throws {
        let choice = SpreadChoice(preferences: Preferences(defaults: nil))
        let window = settings(choice)
        let texts = { self.descendants(of: window.contentView!).compactMap { ($0 as? NSTextField)?.stringValue } }

        try cell(1, in: window).performClick(nil)
        try cell(20, in: window).performClick(nil)
        XCTAssertEqual(choice.cells, SpreadCells(indices: [1, 2, 5, 6, 7, 19]))
        XCTAssertEqual(try ticked(in: window), [2, 3, 6, 7, 8, 20])

        let empty = "No cell is ticked, so Spread makes no card. Tick the cells it should fill."
        XCTAssertFalse(texts().contains(empty))
        for n in [2, 3, 6, 7, 8, 20] { try cell(n, in: window).performClick(nil) }
        XCTAssertEqual(choice.cells, .empty, "no cells is a choice too")
        XCTAssertTrue(texts().contains(empty), "and a status line says so")
        XCTAssertTrue(texts().contains(SettingsCopy.Spread.caption), "under the caption, which stays")
    }

    func testTheStacksCellReadsAsTheStackAndTheOthersAsTickedOrNot() throws {
        let window = settings(SpreadChoice(preferences: Preferences(defaults: nil)))

        XCTAssertEqual(try cell(5, in: window).accessibilityValueDescription(), "The stack, dimmed")
        XCTAssertEqual(try cell(1, in: window).accessibilityRole(), .checkBox)
        XCTAssertEqual(try cell(1, in: window).accessibilityValue() as? Int, 1)
        XCTAssertEqual(try cell(4, in: window).accessibilityValue() as? Int, 0)
    }

    func testTheGridIsOneTabStop() throws {
        let window = settings(SpreadChoice(preferences: Preferences(defaults: nil)))
        window.select(.spread)
        let table = try XCTUnwrap(descendants(of: window.contentView!).compactMap { $0 as? NSTableView }.first)

        XCTAssertTrue(try picker(in: window) === table.nextKeyView, "Tab from the sidebar lands on the grid")
        XCTAssertTrue(try picker(in: window).nextKeyView === table, "and the next Tab leaves it")
        XCTAssertTrue(try (1...20).allSatisfy { try cell($0, in: window).refusesFirstResponder })
    }

    func testAnArrowMovesToTheNextCellThatWayPastTheStacksAndStopsAtTheEdge() {
        func step(_ from: Int, _ dx: Int, _ dy: Int, stack: Int = 4) -> Int {
            SpreadCellPicker.step(from: Slot(index: from)!, dx: dx, dy: dy, skipping: Slot(index: stack)!).index
        }
        XCTAssertEqual(step(0, 1, 0), 1)
        XCTAssertEqual(step(0, 0, 1), 5)
        XCTAssertEqual(step(0, -1, 0), 0, "nothing left of the first cell")
        XCTAssertEqual(step(0, 0, -1), 0)
        XCTAssertEqual(step(19, 1, 0), 19)
        XCTAssertEqual(step(19, 0, 1), 19)
        XCTAssertEqual(step(3, 1, 0), 3, "the stack's cell ends the row")
        XCTAssertEqual(step(9, 0, -1), 9, "and the column")
        XCTAssertEqual(step(6, 1, 0, stack: 7), 8, "a cell past the stack's is reached")
        XCTAssertEqual(step(2, 0, 1, stack: 7), 12)
    }

    func testSpaceTicksTheFocusedCellAndTheArrowsMoveIt() throws {
        let choice = SpreadChoice(preferences: Preferences(defaults: nil))
        let window = settings(choice)
        let picker = try picker(in: window)

        picker.keyDown(with: try key(kVK_Space, " "))
        XCTAssertEqual(choice.cells, SpreadCells(indices: [1, 2, 5, 6, 7]), "cell 1 had the focus")

        picker.keyDown(with: try key(kVK_DownArrow, "\u{F701}"))
        picker.keyDown(with: try key(kVK_RightArrow, "\u{F703}"))
        picker.keyDown(with: try key(kVK_Space, " "))
        XCTAssertEqual(choice.cells, SpreadCells(indices: [1, 2, 5, 7]), "cell 7 is down one and right one")
        XCTAssertEqual(try ticked(in: window), [2, 3, 6, 8])
    }

    func testTheFocusLeavesTheStacksCellWhenTheStackMovesOntoIt() throws {
        var stackCell = Slot.stackHome
        let window = settings(SpreadChoice(preferences: Preferences(defaults: nil)), stackCell: { stackCell })
        let picker = try picker(in: window)

        stackCell = Slot(index: 0)!
        window.becomeKey()

        XCTAssertEqual(picker.focusedCell.index, 1)
    }

    func testTheFactoryCellsAreTheLeftThreeOfTheTopTwoRows() {
        XCTAssertEqual(SpreadCells.standard.indices, [0, 1, 2, 5, 6, 7])
        XCTAssertEqual(Preferences(defaults: nil).spreadCells, .standard)
        XCTAssertEqual(Preferences(defaults: suites.make()).spreadCells, .standard)
    }

    func testAnOrdinaryRunKeepsTheCellsAcrossLaunches() {
        let owners = suites.make()
        SpreadChoice(preferences: Preferences(defaults: owners)).cells = SpreadCells(indices: [9, 3])
        XCTAssertEqual(SpreadChoice(preferences: Preferences(defaults: owners)).cells, SpreadCells(indices: [3, 9]))
        SpreadChoice(preferences: Preferences(defaults: owners)).cells = .empty
        XCTAssertEqual(SpreadChoice(preferences: Preferences(defaults: owners)).cells, .empty, "an empty list stays empty")
    }

    func testJunkInTheStoredCellsIsDropped() {
        let owners = suites.make()
        owners.set([0, 25, -1, "x", 3, 3], forKey: "SpreadCells")
        XCTAssertEqual(Preferences(defaults: owners).spreadCells, SpreadCells(indices: [0, 3]), "cells past the grid, words and repeats go")
        owners.set("nonsense", forKey: "SpreadCells")
        XCTAssertEqual(Preferences(defaults: owners).spreadCells, .standard, "something that is not a list reads as the factory cells")
    }

    func testAScratchRunKeepsAChangeForTheRunAndWritesNothing() {
        let owners = suites.make()
        let launch = Launch(arguments: ["CardsFolder": "/tmp/scratch"], defaults: owners, build: BuildInfo(info: [:]), environment: [:])
        let choice = SpreadChoice(preferences: launch.preferences(standard: owners))

        choice.cells = SpreadCells(indices: [12])

        XCTAssertEqual(choice.cells, SpreadCells(indices: [12]), "the change lasts for the run")
        XCTAssertNil(owners.object(forKey: "SpreadCells"))
        XCTAssertEqual(SpreadChoice(preferences: launch.preferences(standard: owners)).cells, .standard)
    }
}
