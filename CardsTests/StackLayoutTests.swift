import XCTest
@testable import Ideator

/// The stack's ribbon, count badge and shown card's buttons, in a window that is never shown.
final class StackLayoutTests: XCTestCase {
    /// The cell width a 1512-point screen gives, and a 1366-point one.
    private let wide: CGFloat = 302.4
    private let narrow: CGFloat = 273
    private let belowAnyCell: CGFloat = 180
    /// Less than the icon toolbar, the menu button and the badge need side by side.
    private let tooNarrowForBadge: CGFloat = 110

    private struct Stack {
        let window: StackWindow
        let toggled: () -> Int
        let sent: () -> [Command]
        /// Each Spread press, true for a fresh set.
        let spreads: () -> [Bool]

        var view: NSView { window.contentView!.subviews[0] }   // the glass holds the stack view
        func control(_ tooltip: String) -> NSView {
            view.subviews.first { $0.toolTip == tooltip }!
        }
        var toggle: NSView { view.subviews.first { $0.toolTip == "Hide all" || $0.toolTip == "Show all" }! }
        var menu: NSView { control("Settings and quit") }
        var badge: NSView { control("Arrange the stack") }
        var desktopFull: NSView { view.subviews.first { ($0 as? NSTextField)?.stringValue == "Desktop full" }! }
        /// New, the toggle, Spread and Clarity, left to right.
        var ribbonButtons: [NSButton] {
            view.subviews.compactMap { $0 as? NSButton }
                .filter { ["New", "Hide all", "Show all", "Spread", "Clarity"].contains($0.accessibilityLabel()) }
                .sorted { $0.frame.minX < $1.frame.minX }
        }
        var spread: NSButton { ribbonButtons.first { $0.accessibilityLabel() == "Spread" }! }
        var clarity: NSButton { ribbonButtons.last! }
        var toolbarEnd: CGFloat { ribbonButtons.map(\.frame.maxX).max()! }
        var card: CardView { view.subviews.compactMap { $0 as? CardView }.first! }
    }

    private func hoverButton(_ title: String, in card: CardView) -> NSButton? {
        let row = card.subviews.compactMap { $0 as? NSStackView }
            .first { $0.arrangedSubviews.contains { $0.toolTip == "Delete this card" } }
        return row?.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.title == title }
    }

    private func stack(width: CGFloat, _ visibility: Visibility = .all, full: Bool = false,
                       clarity: Bool = false, count: Int = 12, spread: SpreadButton = .spread,
                       refusal: SpreadRefusal? = nil) -> Stack {
        var toggles = 0
        var commands: [Command] = []
        var spreads: [Bool] = []
        let window = StackWindow(send: { commands.append($0) }, menu: { NSMenu() }, toggleHidden: { toggles += 1 },
                                 spread: { spreads.append($0) }, drag: WindowDrag(moved: { _ in }, dropped: { _ in }))
        let card = CardFace(id: CardID(rawValue: "a"), note: Note(header: "Title", body: []), collapsed: false,
                            summary: .body(""))
        let rows = (0..<count).map { StackRow(id: CardID(rawValue: "row\($0)"), title: "Card \($0)") }
        let face = StackFace(stacked: rows, selected: card, clarity: clarity, desktopFull: full, spreadButton: spread)
        window.apply(face, cell: CGRect(x: 0, y: 0, width: width, height: (width * 0.78).rounded()), visibility: visibility,
                     spreadRefusal: refusal)
        window.contentView!.layoutSubtreeIfNeeded()
        return Stack(window: window, toggled: { toggles }, sent: { commands }, spreads: { spreads })
    }

    func testTheRibbonIsNewTheToggleSpreadAndClarityButNoPop() {
        let shown = stack(width: wide)
        XCTAssertEqual(shown.ribbonButtons.map { $0.accessibilityLabel() }, ["New", "Hide all", "Spread", "Clarity"])
        XCTAssertTrue(shown.ribbonButtons.allSatisfy { $0.image != nil && $0.imagePosition == .imageOnly }, "icons, no words")
        XCTAssertEqual(shown.ribbonButtons.first?.toolTip, "New card")
        XCTAssertLessThan(shown.ribbonButtons.last!.frame.maxX, shown.view.bounds.midX, "all four at the left")
    }

    func testTheToolbarIconsAreEvenlySpacedByWhatTheyDraw() throws {
        for (visibility, clarity) in [(Visibility.all, false), (.hideAll, false), (.all, true), (.hideAll, true)] {
            let ribbon = stack(width: wide, visibility, clarity: clarity)
            let buttons = ribbon.ribbonButtons
            let inked = try drawnSpans(of: buttons, in: ribbon.view)
            for (left, right) in zip(inked, inked.dropFirst()) {
                XCTAssertEqual(right.lowerBound - left.upperBound, 12, accuracy: 0.5,
                               "\(visibility), clarity \(clarity), ink \(inked)")
            }
            for (left, right) in zip(buttons, buttons.dropFirst()) {
                XCTAssertLessThanOrEqual(left.frame.maxX, right.frame.minX, "hit areas never overlap")
            }
            for button in buttons {
                XCTAssertGreaterThanOrEqual(button.frame.width, 18)
            }
        }
    }

    /// Where each of `buttons` draws, as a span of `view`'s x coordinates in points. The ribbon is
    /// rendered with the buttons hidden and then with one shown at a time, and the columns that
    /// changed are that button's ink. This measures what AppKit draws in place, not an image rendered
    /// on its own: a symbol drawn into a rect other than its own size gets other side bearings, and
    /// by how much depends on the macOS version. 4x because at 2x one pixel of anti-aliasing is
    /// the whole tolerance.
    private func drawnSpans(of buttons: [NSButton], in view: NSView) throws -> [ClosedRange<CGFloat>] {
        let scale = 4
        let strip = buttons.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -4, dy: -2).integral
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(strip.width) * scale,
                                                 pixelsHigh: Int(strip.height) * scale, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = strip.size
        func render() throws -> [UInt8] {
            let bytes = try XCTUnwrap(rep.bitmapData)
            memset(bytes, 0, rep.bytesPerRow * rep.pixelsHigh)
            view.cacheDisplay(in: strip, to: rep)
            return Array(UnsafeBufferPointer(start: bytes, count: rep.bytesPerRow * rep.pixelsHigh))
        }
        buttons.forEach { $0.isHidden = true }
        defer { buttons.forEach { $0.isHidden = false } }
        let blank = try render()
        return try buttons.map { button in
            button.isHidden = false
            defer { button.isHidden = true }
            let shown = try render()
            var change = [Int](repeating: 0, count: rep.pixelsWide)
            for row in 0..<rep.pixelsHigh {
                for column in 0..<rep.pixelsWide {
                    for channel in 0..<4 {
                        let index = row * rep.bytesPerRow + column * 4 + channel
                        change[column] = max(change[column], abs(Int(shown[index]) - Int(blank[index])))
                    }
                }
            }
            let strongest = try XCTUnwrap(change.max().flatMap { $0 > 0 ? $0 : nil },
                                          "\(button.accessibilityLabel() ?? "a button") draws nothing")
            let inked = change.indices.filter { change[$0] * 10 >= strongest }
            return (strip.minX + CGFloat(inked.first!) / CGFloat(scale))...(strip.minX + CGFloat(inked.last! + 1) / CGFloat(scale))
        }
    }

    // DIAGNOSTIC, temporary: prints how this macOS places and draws each ribbon icon.
    func testRibbonDiagnostics() throws {
        func say(_ line: String) { print("RIBBON-DIAG " + line) }
        say("os \(ProcessInfo.processInfo.operatingSystemVersionString) screens \(NSScreen.screens.map { "\($0.frame) x\($0.backingScaleFactor)" }) main x\(NSScreen.main?.backingScaleFactor ?? -1)")
        func standalone(_ image: NSImage, scale: CGFloat, stretched: Bool = false) -> String {
            let columns = Int((image.size.width * scale).rounded(.up)), rows = Int((image.size.height * scale).rounded(.up))
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: columns, pixelsHigh: rows, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { return "no rep" }
            if !stretched { rep.size = NSSize(width: CGFloat(columns) / scale, height: CGFloat(rows) / scale) }
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return "no context" }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(origin: .zero, size: stretched ? NSSize(width: columns, height: rows) : rep.size))
            NSGraphicsContext.restoreGraphicsState()
            let inked = (0..<columns).filter { x in (0..<rows).contains { y in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 } }
            guard let first = inked.first, let last = inked.last else { return "blank" }
            return "\(CGFloat(first) / scale)/\(CGFloat(columns - 1 - last) / scale)"
        }
        func spans(_ buttons: [NSButton], in view: NSView, scale: Int) -> [String] {
            let strip = buttons.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -4, dy: -2).integral
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(strip.width) * scale, pixelsHigh: Int(strip.height) * scale,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return [] }
            rep.size = strip.size
            func render() -> [UInt8] {
                memset(rep.bitmapData!, 0, rep.bytesPerRow * rep.pixelsHigh)
                view.cacheDisplay(in: strip, to: rep)
                return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
            }
            buttons.forEach { $0.isHidden = true }
            defer { buttons.forEach { $0.isHidden = false } }
            let blank = render()
            return buttons.map { button in
                button.isHidden = false
                defer { button.isHidden = true }
                let shown = render()
                var change = [Int](repeating: 0, count: rep.pixelsWide)
                for row in 0..<rep.pixelsHigh { for column in 0..<rep.pixelsWide { for channel in 0..<4 {
                    let index = row * rep.bytesPerRow + column * 4 + channel
                    change[column] = max(change[column], abs(Int(shown[index]) - Int(blank[index])))
                } } }
                let strongest = change.max() ?? 0
                let inked = change.indices.filter { strongest > 0 && change[$0] * 10 >= strongest }
                guard let first = inked.first, let last = inked.last else { return "none" }
                return "\(strip.minX + CGFloat(first) / CGFloat(scale))...\(strip.minX + CGFloat(last + 1) / CGFloat(scale))"
            }
        }
        func layerSpans(_ buttons: [NSButton], window: NSWindow, view: NSView) -> [String] {
            guard let root = window.contentView?.layer else { return ["no layer"] }
            let scale = window.backingScaleFactor
            let width = Int((view.bounds.width * scale).rounded(.up)), height = Int((view.bounds.height * scale).rounded(.up))
            func render() -> [UInt8] {
                window.displayIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.scaleBy(x: scale, y: scale)
                root.render(in: context)
                return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
            }
            buttons.forEach { $0.isHidden = true }
            defer { buttons.forEach { $0.isHidden = false } }
            let blank = render()
            return buttons.map { button in
                button.isHidden = false
                defer { button.isHidden = true }
                let shown = render()
                var change = [Int](repeating: 0, count: width)
                for row in 0..<height { for column in 0..<width { for channel in 0..<4 {
                    let index = (row * width + column) * 4 + channel
                    change[column] = max(change[column], abs(Int(shown[index]) - Int(blank[index])))
                } } }
                let strongest = change.max() ?? 0
                let inked = change.indices.filter { strongest > 0 && change[$0] * 10 >= strongest }
                guard let first = inked.first, let last = inked.last else { return "none" }
                return "\(CGFloat(first) / scale)...\(CGFloat(last + 1) / scale)"
            }
        }
        for (visibility, clarity) in [(Visibility.all, false), (.hideAll, true)] {
            let ribbon = stack(width: wide, visibility, clarity: clarity)
            let buttons = ribbon.ribbonButtons
            say("state \(visibility) clarity \(clarity) window x\(ribbon.window.backingScaleFactor) screen \(String(describing: ribbon.window.screen?.frame)) view \(ribbon.view.frame) layer \(ribbon.view.layer != nil)")
            for button in buttons {
                let image = try XCTUnwrap(button.image)
                let cell = try XCTUnwrap(button.cell as? NSButtonCell)
                say("\(button.accessibilityLabel() ?? "?") size \(image.size) align \(image.alignmentRect) template \(image.isTemplate) reps \(image.representations.map { "\(type(of: $0)) \($0.size) \($0.pixelsWide)x\($0.pixelsHigh)" }) symbolConfig \(String(describing: image.symbolConfiguration)) buttonSymbolConfig \(String(describing: button.symbolConfiguration))")
                say("   frame \(button.frame) cellImageRect \(cell.imageRect(forBounds: button.bounds)) cellSize \(cell.cellSize) scaling \(cell.imageScaling.rawValue) bezel \(button.bezelStyle.rawValue) type \(button.wantsUpdateLayer) subviews \(button.subviews.map { "\(type(of: $0)) \($0.frame)" })")
                say("   standalone lead/trail own1 \(standalone(image, scale: 1)) own2 \(standalone(image, scale: 2)) own4 \(standalone(image, scale: 4)) own8 \(standalone(image, scale: 8)) stretched4 \(standalone(image, scale: 4, stretched: true))")
            }
            for scale in [1, 2, 4, 8] {
                say("cacheDisplay x\(scale) \(spans(buttons, in: ribbon.view, scale: scale))")
            }
            ribbon.window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            ribbon.window.orderFrontRegardless()
            say("on screen x\(ribbon.window.backingScaleFactor) visible \(ribbon.window.isVisible) subviews \(buttons.map { $0.subviews.map { "\($0.frame) layer \(String(describing: $0.layer?.frame)) contents \($0.layer?.contents.map { CFCopyTypeIDDescription(CFGetTypeID($0 as CFTypeRef)) as String } ?? "nil")" } })")
            say("layer render \(layerSpans(buttons, window: ribbon.window, view: ribbon.view))")
            say("on screen cacheDisplay x4 \(spans(buttons, in: ribbon.view, scale: 4))")
            ribbon.window.orderOut(nil)

            // Candidate: each icon cropped to its measured ink, as a drawing-handler image.
            let window = NSWindow(contentRect: NSRect(x: -4000, y: -3000, width: 303, height: 46), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 303, height: 46))
            configureAsCard(window, content: content)
            window.setFrame(NSRect(x: -4000, y: -3000, width: 303, height: 46), display: false)
            var edge: CGFloat = 15.15
            var centeredEdge: CGFloat = 15.15
            var centeredButtons: [NSButton] = []
            let croppedButtons: [NSButton] = try buttons.map { original in
                let symbol = try XCTUnwrap(original.image)
                let columns = Int((symbol.size.width * 4).rounded(.up)), rows = Int((symbol.size.height * 4).rounded(.up))
                let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: columns, pixelsHigh: rows, bitsPerSample: 8,
                                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                         bytesPerRow: 0, bitsPerPixel: 0))
                rep.size = NSSize(width: CGFloat(columns) / 4, height: CGFloat(rows) / 4)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                symbol.draw(in: NSRect(origin: .zero, size: rep.size))
                NSGraphicsContext.restoreGraphicsState()
                let inked = (0..<columns).filter { x in (0..<rows).contains { y in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 } }
                let lead = CGFloat(inked.first!) / 4, inkWidth = CGFloat(inked.last! + 1 - inked.first!) / 4
                let image = NSImage(size: NSSize(width: inkWidth, height: symbol.size.height), flipped: false) { _ in
                    symbol.draw(in: NSRect(x: -lead, y: 0, width: symbol.size.width, height: symbol.size.height))
                    return true
                }
                image.isTemplate = true
                let button = ActionButton(symbol: "plus", help: "")
                button.image = image
                button.contentTintColor = original.contentTintColor
                button.frame = NSRect(x: edge - 4, y: 14, width: inkWidth + 8, height: 18)
                content.addSubview(button)
                say("candidate \(original.accessibilityLabel() ?? "?") lead \(lead) ink \(inkWidth) frame \(button.frame) planned \(edge)...\(edge + inkWidth)")
                edge += inkWidth + 12

                let trail = symbol.size.width - lead - inkWidth
                let centeredImage = NSImage(size: symbol.size, flipped: false) { _ in
                    symbol.draw(in: NSRect(x: (trail - lead) / 2, y: 0, width: symbol.size.width, height: symbol.size.height))
                    return true
                }
                centeredImage.isTemplate = true
                let centered = ActionButton(symbol: "plus", help: "")
                centered.image = centeredImage
                centered.contentTintColor = original.contentTintColor
                let width = max(symbol.size.width + 6, 18)
                centered.frame = NSRect(x: centeredEdge + inkWidth / 2 - width / 2, y: 14, width: width, height: 18)
                centeredButtons.append(centered)
                centeredEdge += inkWidth + 12
                return button
            }
            content.layoutSubtreeIfNeeded()
            say("candidate subviews \(croppedButtons.map { $0.subviews.map { "\($0.frame)" } })")
            say("candidate cacheDisplay x4 \(spans(croppedButtons, in: content, scale: 4)) x2 \(spans(croppedButtons, in: content, scale: 2))")
            window.orderFrontRegardless()
            say("candidate layer render x\(window.backingScaleFactor) \(layerSpans(croppedButtons, window: window, view: content))")
            croppedButtons.forEach { $0.removeFromSuperview() }
            centeredButtons.forEach { content.addSubview($0) }
            content.layoutSubtreeIfNeeded()
            say("centered frames \(centeredButtons.map { "\($0.frame) \($0.subviews.map { "\($0.frame)" })" })")
            say("centered cacheDisplay x4 \(spans(centeredButtons, in: content, scale: 4)) x2 \(spans(centeredButtons, in: content, scale: 2))")
            say("centered layer render x\(window.backingScaleFactor) \(layerSpans(centeredButtons, window: window, view: content))")
            window.orderOut(nil)
        }
    }

    func testClaritySaysItsStateByFillColorAndValue() throws {
        let off = stack(width: wide).clarity
        let on = stack(width: wide, clarity: true).clarity
        XCTAssertEqual([off.accessibilityLabel(), on.accessibilityLabel()], ["Clarity", "Clarity"])
        XCTAssertNotEqual(off.image?.tiffRepresentation, on.image?.tiffRepresentation, "an outline off, filled on")
        XCTAssertEqual(off.frame, on.frame, "and it does not move")
        XCTAssertEqual(off.contentTintColor, Palette.ribbonInk)
        XCTAssertEqual(on.contentTintColor, Palette.accent)
        XCTAssertEqual(off.accessibilityValue() as? String, "off")
        XCTAssertEqual(on.accessibilityValue() as? String, "on")
        XCTAssertEqual(off.toolTip, "Clarity is off: click to collapse every card")
        XCTAssertEqual(on.toolTip, "Clarity is on: click to expand every card")
    }

    func testSpreadSaysWhatAClickDoesByTintTooltipAndValue() {
        let spreads = stack(width: wide)
        let gathers = stack(width: wide, spread: .gather)
        XCTAssertEqual([spreads.spread.accessibilityLabel(), gathers.spread.accessibilityLabel()], ["Spread", "Spread"],
                       "one name in both states")
        XCTAssertEqual(spreads.spread.toolTip, "Spread cards")
        XCTAssertEqual(gathers.spread.toolTip, "Gather cards")
        XCTAssertEqual(spreads.spread.contentTintColor, Palette.ribbonInk)
        XCTAssertEqual(gathers.spread.contentTintColor, Palette.accent, "tinted while its cards are out, like Clarity on")
        XCTAssertEqual(spreads.spread.accessibilityValue() as? String, "in")
        XCTAssertEqual(gathers.spread.accessibilityValue() as? String, "out")
        XCTAssertEqual(spreads.spread.frame, gathers.spread.frame, "and it does not move")
    }

    func testARefusedSpreadSaysWhyUntilAClickWouldGather() {
        XCTAssertEqual(stack(width: wide, refusal: .taken).spread.toolTip, "Your Spread cells are taken")
        XCTAssertEqual(stack(width: wide, refusal: .noCells).spread.toolTip, "Pick Spread cells in Settings")
        XCTAssertEqual(stack(width: wide, spread: .gather, refusal: .taken).spread.toolTip, "Gather cards")
    }

    func testAClickSpreadsAndTheNewSpreadActionStartsAFreshSet() throws {
        let ribbon = stack(width: wide)
        ribbon.spread.performClick(nil)
        XCTAssertEqual(ribbon.spreads(), [false], "a click carries no Option")
        let fresh = try XCTUnwrap(ribbon.spread.cell?.accessibilityCustomActions()?.first { $0.name == "New spread" },
                                  "AppKit serves a button's actions from its cell: ones set on the button never reach VoiceOver")
        XCTAssertEqual(fresh.handler?(), true)
        XCTAssertEqual(ribbon.spreads(), [false, true], "the action asks for a fresh set")
        XCTAssertEqual(ribbon.sent().count, 0, "the ribbon leaves the command to the controller")
    }

    func testTheClarityButtonSetsTheOppositeOfWhatTheRibbonShows() {
        for shown in [false, true] {
            let ribbon = stack(width: wide, clarity: shown)

            _ = ribbon.clarity.accessibilityPerformPress()

            guard case .setClarity(let on)? = ribbon.sent().last else { return XCTFail("got \(ribbon.sent())") }
            XCTAssertEqual(on, !shown, "Clarity \(shown ? "on" : "off") is pressed to \(shown ? "off" : "on")")
            XCTAssertEqual(ribbon.sent().count, 1)
        }
    }

    func testTheStackedCardPopsItselfAndADesktopCardReturnsToTheStack() throws {
        let shown = stack(width: wide)
        let pop = try XCTUnwrap(hoverButton("↗ Pop", in: shown.card))
        XCTAssertNil(hoverButton("↩ Stack", in: shown.card), "a stacked card is already on the stack")
        XCTAssertTrue(pop.isEnabled)
        XCTAssertEqual(pop.toolTip, "Bring this card out")
        pop.performClick(nil)
        guard case .pop? = shown.sent().last else { return XCTFail("Pop sends .pop, got \(shown.sent())") }

        var sent: [Command] = []
        let desktop = CardView(home: .desktop(WindowDrag(moved: { _ in }, dropped: { _ in })), send: { sent.append($0) })
        desktop.apply(CardFace(id: CardID(rawValue: "a"), note: Note(header: "Title", body: []), collapsed: false,
                               summary: .body("")))
        XCTAssertNil(hoverButton("↗ Pop", in: desktop), "a desktop card is already out")
        let back = try XCTUnwrap(hoverButton("↩ Stack", in: desktop))
        XCTAssertEqual(back.toolTip, "Return this card to the top of the stack")
        back.performClick(nil)
        guard case .returnToStack(let id)? = sent.last else { return XCTFail("↩ Stack sends .returnToStack, got \(sent)") }
        XCTAssertEqual(id, CardID(rawValue: "a"))
    }

    func testPopIsGreyedOnAFullDesktopAndSaysWhy() throws {
        let full = stack(width: wide, full: true)
        let pop = try XCTUnwrap(hoverButton("↗ Pop", in: full.card))
        XCTAssertFalse(pop.isEnabled)
        XCTAssertEqual(pop.toolTip, "Desktop full")
        let roomAgain = stack(width: wide)
        XCTAssertTrue(try XCTUnwrap(hoverButton("↗ Pop", in: roomAgain.card)).isEnabled)
    }

    func testTheToggleOffersHideAllWhileCardsShowAndShowAllWhileHidden() throws {
        let shown = stack(width: wide)
        XCTAssertEqual(shown.toggle.toolTip, "Hide all", "with cards showing it hides them")
        XCTAssertEqual(shown.toggle.accessibilityLabel(), "Hide all")
        let hidden = stack(width: wide, .hideAll)
        XCTAssertEqual(hidden.toggle.toolTip, "Show all", "under Hide all it shows them again")
        XCTAssertEqual(hidden.toggle.accessibilityLabel(), "Show all")
        XCTAssertEqual(hidden.toggle.frame.minX, shown.toggle.frame.minX, "the chevron keeps its x")
        XCTAssertEqual(hidden.toggle.frame.size, shown.toggle.frame.size, "and its size")
        XCTAssertEqual(hidden.view.bounds.maxY - hidden.toggle.frame.maxY, shown.view.bounds.maxY - shown.toggle.frame.maxY,
                       "and its distance from the top, so it flips in place within the ribbon")
        try XCTUnwrap(hidden.toggle as? NSButton).performClick(nil)
        XCTAssertEqual(hidden.toggled(), 1, "one click toggles")
    }

    func testTheBadgeIsInTheCardsBottomRightUnlessHideAllRemovedTheCard() {
        let shown = stack(width: wide)
        XCTAssertGreaterThan(shown.badge.frame.midX, shown.view.bounds.midX, "on the right")
        XCTAssertLessThan(shown.badge.frame.maxY, shown.menu.frame.minY, "below the ribbon, in the card area")
        XCTAssertLessThan(shown.badge.frame.minY, shown.view.bounds.height * 0.2, "near the bottom")
        let hidden = stack(width: wide, .hideAll)
        XCTAssertEqual(hidden.badge.frame.midY, hidden.menu.frame.midY, accuracy: 2, "in the ribbon")
        XCTAssertLessThanOrEqual(hidden.badge.frame.maxX, hidden.menu.frame.minX, "left of the menu button")
        XCTAssertGreaterThan(hidden.badge.frame.minX, hidden.toolbarEnd, "right of the toolbar")
    }

    private func center(of badge: NSView, in stack: Stack) -> CGPoint {
        stack.view.convert(CGPoint(x: badge.frame.midX, y: badge.frame.midY), to: stack.view.superview)
    }

    func testTheBadgeIsAButtonThatTakesTheClickInBothPlacements() {
        for visibility in [Visibility.all, .hideAll] {
            let stack = stack(width: wide, visibility)
            let hit = stack.view.hitTest(center(of: stack.badge, in: stack))
            XCTAssertTrue(hit === stack.badge, "the badge takes the press, \(visibility)")
            XCTAssertTrue(stack.badge is NSButton, "as a button")
            XCTAssertFalse(hit === stack.view, "so in the ribbon the press does not drag the stack")
        }
    }

    func testTheBadgeReadsItsCountToVoiceOverAndOffersTheArranger() throws {
        let badge = try XCTUnwrap(stack(width: wide).badge as? NSButton)
        XCTAssertEqual(badge.title, "12", "it shows the number")
        XCTAssertEqual(badge.accessibilityLabel(), "12 cards in the stack", "and says what it counts")
        XCTAssertEqual(badge.toolTip, "Arrange the stack", "the tooltip names what it does")
        XCTAssertFalse(badge.refusesFirstResponder, "Tab can reach it when keyboard navigation is on")
        XCTAssertEqual(try XCTUnwrap(stack(width: wide, count: 1).badge as? NSButton).accessibilityLabel(),
                       "1 card in the stack", "one card is singular")
    }

    func testAtZeroCardsTheBadgeDoesNothingAndLeavesAPressToWhatIsUnderIt() throws {
        for visibility in [Visibility.all, .hideAll] {
            let stack = stack(width: wide, visibility, count: 0)
            let badge = try XCTUnwrap(stack.badge as? NSButton)
            XCTAssertEqual(badge.title, "0", "it still counts")
            XCTAssertFalse(badge.isEnabled, "but is not a live button")
            let hit = stack.view.hitTest(center(of: badge, in: stack))
            XCTAssertFalse(hit === badge, "a press does not land on it, \(visibility)")
            if visibility == .hideAll {
                XCTAssertTrue(hit === stack.view, "in the ribbon the press drags the stack as before")
            }
        }
    }

    func testTheBadgeClearsTheFormattingBarsButtons() throws {
        for width in [wide, narrow] {
            let stack = stack(width: width)
            let cardView = try XCTUnwrap(stack.view.subviews.first { String(describing: type(of: $0)) == "CardView" })
            let bar = try XCTUnwrap(cardView.subviews.first { $0 is FormatBar } as? FormatBar)
            bar.layoutSubtreeIfNeeded()
            let buttonsEnd = bar.arrangedSubviews.map { stack.view.convert($0.frame, from: bar).maxX }.max()!
            XCTAssertLessThan(buttonsEnd, stack.badge.frame.minX, "at width \(width)")
        }
    }

    func testDesktopFullTruncatesBeforeAnyButtonMoves() {
        for visibility in [Visibility.all, .hideAll] {
            let without = stack(width: wide, visibility)
            let with = stack(width: wide, visibility, full: true)
            XCTAssertEqual(with.ribbonButtons.map(\.frame), without.ribbonButtons.map(\.frame), "the toolbar stays put")
            XCTAssertEqual(with.menu.frame, without.menu.frame, "and so does the menu button")
            let label = with.desktopFull.frame
            let rightEdge = visibility == .all ? with.menu.frame.minX : with.badge.frame.minX
            XCTAssertGreaterThanOrEqual(label.minX, with.toolbarEnd, "the label stays right of the toolbar")
            XCTAssertLessThanOrEqual(label.maxX, rightEdge, "and left of what is at its right")
        }
    }

    func testTheRibbonOnlyBadgeGivesWayRatherThanCoverTheToolbar() {
        let wideRibbon = stack(width: wide, .hideAll)
        XCTAssertFalse(wideRibbon.badge.isHidden, "with room the count shows beside the menu button")
        let narrowRibbon = stack(width: belowAnyCell, .hideAll)
        XCTAssertTrue(narrowRibbon.badge.isHidden || narrowRibbon.badge.frame.minX >= narrowRibbon.toolbarEnd + 8,
                      "it shows only clear of the toolbar")
        XCTAssertGreaterThan(narrowRibbon.menu.frame.minX, narrowRibbon.toolbarEnd, "and the buttons stay apart")
        let cramped = stack(width: tooNarrowForBadge, .hideAll)
        XCTAssertTrue(cramped.badge.isHidden, "without room it goes instead of covering the Clarity button")
    }
}
