import XCTest
@testable import Ideator

/// Settings › Spread: the grid of cells, its caption, and where the ticked cells are kept.
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

    func testTheSpreadBlockComesRightAfterTheShortcutAndBeforeTheKey() throws {
        let window = settings(SpreadChoice(preferences: Preferences(defaults: nil)))
        let views = descendants(of: try XCTUnwrap(window.contentView))
        func index(_ match: (NSView) -> Bool, _ name: String) throws -> Int { try XCTUnwrap(views.firstIndex(where: match), name) }
        func label(_ text: String) throws -> Int { try index({ ($0 as? NSTextField)?.stringValue == text }, text) }
        let firstCell = try index({ ($0 as? NSButton)?.accessibilityLabel() == "Spread cell 1" }, "the first cell")
        XCTAssertLessThan(try label("Shortcut"), try label("Spread"))
        XCTAssertLessThan(try label("Spread"), firstCell)
        XCTAssertLessThan(firstCell, try label(SettingsWindow.spreadCaption(cells: .standard)), "the caption is under the grid")
        XCTAssertLessThan(try label(SettingsWindow.spreadCaption(cells: .standard)), try label("API key (Anthropic or OpenAI)"))
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

        for n in [2, 3, 6, 7, 8, 20] { try cell(n, in: window).performClick(nil) }
        XCTAssertEqual(choice.cells, .empty, "no cells is a choice too")
        XCTAssertTrue(texts().contains(SettingsWindow.spreadCaption(cells: .empty)), "and the caption says so")
    }

    func testTheCaptionSaysWhatSpreadDoesOrThatNoCellIsTicked() {
        XCTAssertEqual(SettingsWindow.spreadCaption(cells: .standard),
                       "Spread on the stack's ribbon puts a new card in each ticked cell. Its next click gathers them into the "
                       + "stack, and the click after puts them back. Option-click starts a new set. The dimmed cell is the stack's.")
        XCTAssertEqual(SettingsWindow.spreadCaption(cells: .empty),
                       "No cell is ticked, so Spread makes no card. Tick the cells it should fill. The dimmed cell is the stack's.")
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
