import XCTest
@testable import Ideator

/// SETTINGS-DESIGN.md's look: the palette's contrast (A1).
final class SettingsLookTests: XCTestCase {
    private let palette = Palette.Settings.self

    override func tearDown() {
        Palette.Settings.increaseContrastOverride = nil
    }

    func testEveryTextPairReadsAtFourAndAHalfToOneAndEveryEdgeAndGlyphAtThree() {
        Palette.Settings.increaseContrastOverride = false
        let text: [(String, NSColor, NSColor)] = [
            ("ink on canvas", palette.ink, palette.canvas),
            ("ink on surface", palette.ink, palette.surface),
            ("ink on wash", palette.ink, palette.wash),
            ("inkInverse on inverse", palette.inkInverse, palette.inverse),
            ("inkInverse on inverseRaised", palette.inkInverse, palette.inverseRaised),
            ("inkMuted on canvas", palette.inkMuted, palette.canvas),
            ("inkMuted on surface", palette.inkMuted, palette.surface),
            ("inkInverseMuted on inverse", palette.inkInverseMuted, palette.inverse),
        ]
        let graphics: [(String, NSColor, NSColor)] = [
            ("border on canvas", palette.border, palette.canvas),
            ("border on surface", palette.border, palette.surface),
            ("accent on canvas", palette.accent, palette.canvas),
            ("the check on accent", palette.inkInverse, palette.accent),
            ("successStrong on canvas", palette.successStrong, palette.canvas),
            ("warningStrong on canvas", palette.warningStrong, palette.canvas),
            ("dangerStrong on canvas", palette.dangerStrong, palette.canvas),
        ]
        for (pair, foreground, background) in text {
            XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5, pair)
        }
        for (pair, foreground, background) in graphics {
            XCTAssertGreaterThanOrEqual(contrast(foreground, background), 3, pair)
        }
    }

    func testIncreaseContrastTurnsBordersAndMutedInkToInk() {
        Palette.Settings.increaseContrastOverride = false
        XCTAssertNotEqual(srgb(palette.border), srgb(palette.ink))
        XCTAssertNotEqual(srgb(palette.inkMuted), srgb(palette.ink))

        Palette.Settings.increaseContrastOverride = true

        XCTAssertEqual(srgb(palette.border), srgb(palette.ink))
        XCTAssertEqual(srgb(palette.inkMuted), srgb(palette.ink))
        XCTAssertEqual(srgb(palette.inkInverseMuted), srgb(palette.inkInverse))
    }

    func testEveryButtonIsDrawnBySettingsAndNoControlKeepsTheSystemRing() throws {
        let window = settings()
        let views = descendants(of: try XCTUnwrap(window.contentView))
        let buttons = views.compactMap { $0 as? NSButton }

        XCTAssertGreaterThan(buttons.count, 30, "every pane's buttons, the 20 Spread cells among them")
        for button in buttons {
            XCTAssertTrue(button.cell is SettingsButtonCell, "\(button.title) \(button.accessibilityLabel() ?? "")")
        }
        let focusable = views.filter { view in
            switch view {
            case is NSButton, is NSTextView, is NSTableView, is SpreadCellPicker, is SettingsEditorWell: true
            case let field as NSTextField: field.isEditable || field.isSelectable
            default: false
            }
        }
        for view in focusable {
            XCTAssertEqual(view.focusRingType, .none, "\(type(of: view))")
        }
    }

    func testEveryTargetIsAtLeastTwentyFourPointsEachWay() throws {
        let window = settings()
        window.contentView?.layoutSubtreeIfNeeded()
        let views = descendants(of: try XCTUnwrap(window.contentView))
        var targets: [(String, NSSize)] = views.compactMap { view in
            switch view {
            case let button as SettingsButton: ("\(button.title)\(button.accessibilityLabel() ?? "")", button.targetRect.size)
            case let field as NSTextField where field.isEditable: ("key field", field.frame.size)
            case let well as SettingsEditorWell: ("editor", well.frame.size)
            default: nil
            }
        }
        let table = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first)
        targets += (0..<table.numberOfRows).map { ("sidebar row \($0)", table.rect(ofRow: $0).size) }

        XCTAssertGreaterThan(targets.count, 30)
        for (name, size) in targets {
            XCTAssertGreaterThanOrEqual(size.width, SettingsStyle.minTarget, name)
            XCTAssertGreaterThanOrEqual(size.height, SettingsStyle.minTarget, name)
        }
    }

    /// A button's role comes from its cell, as for AppKit's own buttons.
    func testTheDrawnControlsKeepTheirRolesSoVoiceOverReadsThemAsBefore() throws {
        let window = settings()
        let mcp = window.pane(.mcp)
        let roles: [(String, NSView, NSAccessibility.Role)] = [
            ("Let AI tools add cards", mcp, .checkBox), ("Top", mcp, .radioButton), ("Bottom", mcp, .radioButton),
            ("Reset to Default", mcp, .button), ("Save", window.pane(.aiSummary), .button),
            ("Check for updates automatically", window.pane(.updates), .checkBox),
        ]
        for (title, pane, role) in roles {
            XCTAssertEqual(try button(title, in: pane).cell?.accessibilityRole(), role, title)
        }
    }

    func testATickedSpreadCellIsClayAndAnUntickedOneIvoryInsideItsBorder() throws {
        let window = settings()
        let cells = descendants(of: window.pane(.spread)).compactMap { $0 as? SpreadCellButton }
        let ticked = try XCTUnwrap(cells.first { $0.accessibilityLabel() == "Spread cell 1" })
        let unticked = try XCTUnwrap(cells.first { $0.accessibilityLabel() == "Spread cell 4" })
        let stack = try XCTUnwrap(cells.first { $0.accessibilityLabel() == "Spread cell 5" })

        assertColor(pixel(of: ticked, at: corner(of: ticked, inset: 3)), palette.accent)
        assertColor(pixel(of: unticked, at: corner(of: unticked, inset: 3)), palette.canvas)
        assertColor(pixel(of: unticked, at: corner(of: unticked, inset: 0.5)), palette.border)
        assertColor(pixel(of: stack, at: corner(of: stack, inset: 0.5)), palette.inkDisabled, "the stack's cell is dimmed")
    }

    func testSaveIsSlateWhenItWouldSaveAndAnOutlineWhenNot() throws {
        let window = settings()
        window.select(.aiSummary)
        let pane = window.pane(.aiSummary)
        let save = try XCTUnwrap(button("Save", in: pane) as? SettingsButton)
        let field = try XCTUnwrap(descendants(of: pane).compactMap { $0 as? SettingsKeyField }.first)

        XCTAssertNotEqual(pixel(of: save, at: corner(of: save, inset: 3)).last, 1, "dimmed: no fill")
        assertColor(pixel(of: save, at: corner(of: save, inset: 0.5)), palette.inkDisabled)

        window.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertText("sk-ant-test", replacementRange: NSRange(location: NSNotFound, length: 0))

        assertColor(pixel(of: save, at: corner(of: save, inset: 3)), palette.inverse)
    }

    func testTheKeyFieldsBorderTurnsRedWhileTheKeychainRefusesTheKey() throws {
        let keys = RefusingKeyStore()
        keys.set("sk-ant-test")
        let window = settings(keys: keys)
        let pane = window.pane(.aiSummary)
        let field = try XCTUnwrap(descendants(of: pane).compactMap { $0 as? SettingsKeyField }.first)
        assertColor(pixel(of: field, at: NSPoint(x: 0.5, y: 14)), palette.border)

        keys.refuses = true
        try button("Remove Key", in: pane).performClick(nil)

        assertColor(pixel(of: field, at: NSPoint(x: 0.5, y: 14)), palette.dangerStrong)
        assertColor(pixel(of: field, at: NSPoint(x: 1.5, y: 14)), palette.dangerStrong, "2 points wide, inside the field")
    }

    func testTheEditorsBorderTurnsRedWhileItRefusesAnEdit() throws {
        let choice = AIToolsChoice(preferences: Preferences(defaults: nil))
        choice.value.instruction.edit(to: String(repeating: "a", count: Instruction.byteLimit))
        let window = settings(aiTools: choice)
        let well = try XCTUnwrap(descendants(of: window.pane(.mcp)).compactMap { $0 as? SettingsEditorWell }.first)
        let editor = try XCTUnwrap(well.documentView as? NSTextView)
        assertColor(pixel(of: well, at: NSPoint(x: 0.5, y: 50)), palette.border)

        window.makeFirstResponder(editor)
        editor.insertText("b", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))

        assertColor(pixel(of: well, at: NSPoint(x: 1.5, y: 50)), palette.dangerStrong)
    }

    /// Measured on screen rects, which reads the editor's own text system without switching it.
    func testTheInstructionEditorsLinesAreTwentyPointsApart() throws {
        let window = settings()
        window.select(.mcp)
        let editor = try XCTUnwrap(descendants(of: window.pane(.mcp)).compactMap { $0 as? NSTextView }.first)
        editor.string = "one\ntwo\nthree"
        window.contentView?.layoutSubtreeIfNeeded()
        let tops = [0, 4, 8].map { editor.firstRect(forCharacterRange: NSRange(location: $0, length: 1), actualRange: nil).maxY }

        XCTAssertEqual(tops[0] - tops[1], SettingsStyle.lineHeight(.body))
        XCTAssertEqual(tops[1] - tops[2], SettingsStyle.lineHeight(.body))
    }

    func testTheKeyFieldsWellLinesUpWithItsLabelAndTheColumn() throws {
        let window = settings()
        window.contentView?.layoutSubtreeIfNeeded()
        let pane = window.pane(.aiSummary)
        let field = try XCTUnwrap(descendants(of: pane).compactMap { $0 as? SettingsKeyField }.first)
        let label = try XCTUnwrap(descendants(of: pane).compactMap { $0 as? NSTextField }.first { $0.stringValue == "API key" })

        XCTAssertEqual(field.frame.minX, label.alignmentRect(forFrame: label.frame).minX)
        XCTAssertEqual(field.frame.width, SettingsStyle.contentWidth)
    }

    func testAControlFocusedBelowTheFoldScrollsFullyIntoView() throws {
        let window = SettingsWindow(keys: KeyStore(inKeychain: false), hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                                    updates: Updates(build: .current, isScratch: false), maxContentHeight: 300) {}
        window.select(.mcp)
        window.contentView?.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(window.pane(.mcp).enclosingScrollView)
        let well = try XCTUnwrap(descendants(of: window.pane(.mcp)).compactMap { $0 as? SettingsEditorWell }.first)
        let editor = try XCTUnwrap(well.documentView)
        let shown = { scroll.documentVisibleRect.contains(well.convert(well.bounds, to: scroll.documentView)) }
        XCTAssertFalse(shown(), "the editor starts below the fold")

        XCTAssertTrue(window.makeFirstResponder(editor))

        XCTAssertTrue(shown())
    }

    func testTypingShowsAnInkCaretAndSlateSelectionNeverTheAccentColor() throws {
        let window = settings()
        let field = try XCTUnwrap(descendants(of: window.pane(.aiSummary)).compactMap { $0 as? SettingsKeyField }.first)
        let editor = try XCTUnwrap(descendants(of: window.pane(.mcp)).compactMap { $0 as? NSTextView }.first)
        window.select(.aiSummary)
        window.makeFirstResponder(field)
        let fieldEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)

        for text in [fieldEditor, editor] {
            assertColor(srgb(text.insertionPointColor), palette.ink)
            assertColor(srgb(try XCTUnwrap(text.selectedTextAttributes[.backgroundColor] as? NSColor)), palette.inverse)
            assertColor(srgb(try XCTUnwrap(text.selectedTextAttributes[.foregroundColor] as? NSColor)), palette.inkInverse)
        }
    }

    func testTurningOnIncreaseContrastRedrawsCaptionsInInk() throws {
        let window = settings()
        let caption = try XCTUnwrap(descendants(of: window.pane(.shortcut)).compactMap { $0 as? SettingsText }
            .first { $0.stringValue == SettingsCopy.Shortcut.caption })
        let color = { self.srgb(caption.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor) }
        Palette.Settings.increaseContrastOverride = false
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        assertColor(color(), palette.inkMuted)

        Palette.Settings.increaseContrastOverride = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

        assertColor(color(), palette.ink)
    }

    func testThePrivacyCardIsSlateWithIvoryTextAndHoldsTheWindowsOnlySerif() throws {
        let window = settings()
        window.contentView?.layoutSubtreeIfNeeded()
        let card = try XCTUnwrap(descendants(of: window.pane(.privacy)).compactMap { $0 as? PrivacyCardView }.first)
        let texts = descendants(of: try XCTUnwrap(window.contentView)).compactMap { $0 as? SettingsText }.filter { !$0.stringValue.isEmpty }
        let attribute = { (text: SettingsText, key: NSAttributedString.Key) in text.attributedStringValue.attribute(key, at: 0, effectiveRange: nil) }
        let serif = SettingsStyle.font(.display).familyName

        assertColor(pixel(of: card, at: NSPoint(x: 4, y: 4)), palette.inverse)
        let inCard = texts.filter { $0.isDescendant(of: card) }
        XCTAssertEqual(inCard.count, 1 + 2 * 4, "the headline, then four terms over their texts")
        for text in inCard {
            assertColor(srgb(try XCTUnwrap(attribute(text, .foregroundColor) as? NSColor)), palette.inkInverse, text.stringValue)
        }
        let serifs = texts.filter { (attribute($0, .font) as? NSFont)?.familyName == serif }
        XCTAssertEqual(serifs.map(\.stringValue), [SettingsCopy.Privacy.card(for: nil).headline])
    }

    func testTheWindowKeepsItsLightLookWhenTheAppIsDark() throws {
        let appearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer { NSApp.appearance = appearance }
        let window = settings()
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let height = content.bounds.height
        let selectedRow = height - SettingsStyle.contentTop - SettingsStyle.sidebarRowHeight / 2

        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        assertColor(pixel(of: content, at: NSPoint(x: 84, y: 40)), palette.inverse, "the sidebar")
        assertColor(pixel(of: content, at: NSPoint(x: 150, y: selectedRow)), palette.canvas, "the selected row")
        assertColor(pixel(of: content, at: NSPoint(x: SettingsStyle.sidebarWidth - 1, y: selectedRow - 40)), palette.inverse,
                    "no separator at the sidebar's edge")
        assertColor(pixel(of: content, at: NSPoint(x: SettingsStyle.sidebarWidth, y: 40)), palette.canvas, "the pane")
    }

    private func settings(keys: KeyStore = KeyStore(inKeychain: false),
                          aiTools: AIToolsChoice = AIToolsChoice(preferences: Preferences(defaults: nil))) -> SettingsWindow {
        SettingsWindow(keys: keys, hotKey: HotKey(preferences: Preferences(defaults: nil)) {},
                       updates: Updates(build: .current, isScratch: false), aiTools: aiTools) {}
    }

    private func button(_ title: String, in view: NSView) throws -> NSButton {
        try XCTUnwrap(descendants(of: view).compactMap { $0 as? NSButton }.first { $0.title == title }, title)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    /// The top-left corner of a button's control, past its ring's room, moved in by `inset` points.
    private func corner(of button: SettingsButton, inset: CGFloat) -> NSPoint {
        let rect = button.controlRect
        return NSPoint(x: rect.minX + inset, y: (button.isFlipped ? rect.minY : rect.maxY) + (button.isFlipped ? inset : -inset))
    }

    /// The color `view` draws at `point`, a point in its own coordinates, drawn into an sRGB bitmap at 2x.
    private func pixel(of view: NSView, at point: NSPoint) -> [CGFloat] {
        view.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(view.bounds.width * scale), height: Int(view.bounds.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
        context.scaleBy(x: scale, y: scale)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext(cgContext: context, flipped: false))
        let row = Int((view.isFlipped ? point.y : view.bounds.height - point.y) * scale)
        let i = row * context.bytesPerRow + Int(point.x * scale) * 4
        return (0..<4).map { CGFloat(data[i + $0]) / 255 }
    }

    /// Within 2 of 255 per channel, for rounding.
    private func assertColor(_ pixel: [CGFloat], _ expected: NSColor, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        let want = srgb(expected)
        XCTAssertEqual(pixel.count, 4, "no pixel", file: file, line: line)
        guard pixel.count == 4 else { return }
        let close = zip(pixel, want).allSatisfy { abs($0 - $1) <= 2.0 / 255 }
        XCTAssertTrue(close, "\(pixel.map { Int($0 * 255) }) is not \(want.map { Int($0 * 255) }) \(message)", file: file, line: line)
    }

    private func srgb(_ color: NSColor) -> [CGFloat] {
        let c = color.usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }

    /// WCAG 2.2's contrast ratio, from relative luminance.
    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = srgb(color).prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

private final class RefusingKeyStore: KeyStore {
    var refuses = false

    init() { super.init(inKeychain: false) }

    @discardableResult
    override func set(_ key: String?) -> Bool { refuses ? false : super.set(key) }
}
