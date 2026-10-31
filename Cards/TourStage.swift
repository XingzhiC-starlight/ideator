import AppKit

// The tour's windows: AppKit only, no decisions.

/// The real `TourScreen`: a hint panel and a click-through overlay.
final class TourStage: TourScreen {
    private let panel = HintPanel()
    private let overlay = GuideOverlay()

    var onInput: (TourInput) -> Void {
        get { panel.onInput }
        set { panel.onInput = newValue }
    }

    func size(of card: HintCard, faceWidth: CGFloat) -> CGSize { HintPanel.size(of: card, faceWidth: faceWidth) }

    /// Moves the panel without an animator, which would lag a synchronous drag, and orders it front
    /// without activating Ideator, once: a drag shows a scene per step. The overlay comes after it,
    /// since the notch is drawn over the panel's edge.
    func show(_ scene: TourScene, takesKey: Bool) {
        panel.apply(scene.card)
        if panel.frame != scene.pointing.panel { panel.setFrame(scene.pointing.panel, display: true) }
        overlay.apply(scene.pointing, above: panel.level)
        if takesKey {
            panel.makeKeyAndOrderFront(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        if !overlay.isVisible { overlay.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
        overlay.orderOut(nil)
    }
}

/// The hint: a 316 pt face (322 pt window) in the card look with the tour's tint. Non-activating, so
/// a click on it never activates Ideator (page 5 would read that as "Back in front"); floating, so it
/// stays readable when the cards drop behind another app; key only when the reader clicks into it,
/// so a click on Next ends a card's editing like any click elsewhere.
final class HintPanel: NSPanel {
    var onInput: (TourInput) -> Void {
        get { hint.onInput }
        set { hint.onInput = newValue }
    }
    private let hint = HintView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configureAsCard(self, content: hint)
        level = .floating
        hidesOnDeactivate = false
        // The "couldn't read your notes" alert can be up as page 1 appears.
        worksWhenModal = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        title = "Ideator tour"   // a borderless window never draws it; VoiceOver and the verify harness read it
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Shows `card`; a card equal to the one shown changes nothing.
    func apply(_ card: HintCard) { hint.show(card) }

    /// The window size `card` needs with a face `faceWidth` wide: wrapping makes the height depend on
    /// the width.
    static func size(of card: HintCard, faceWidth: CGFloat) -> CGSize {
        HintView.size(of: card, faceWidth: faceWidth)
    }
}

/// The panel's content: the prototype's `.hint` box. Top to bottom: "n of 9" (and OPTIONAL) with
/// "Skip the tour" at the right, the title, the body, and Back with Next or "Start using Ideator".
private final class HintView: NSView {
    var onInput: (TourInput) -> Void = { _ in }
    private let progress = TourText()
    private let optional = TourText()
    private let title = TourText()
    private let body = TourText()
    private lazy var skip = ActionButton(title: "Skip the tour", help: "Go to the last page") { [unowned self] in onInput(.skip) }
    private lazy var back = ActionButton(title: "Back", help: "The page before") { [unowned self] in onInput(.back) }
    private lazy var next = ActionButton(title: "Next", help: "The next page") { [unowned self] in onInput(.next) }
    private lazy var startUsing = ActionButton(title: "Start using Ideator", help: "Open your notes folder and end the tour") {
        [unowned self] in onInput(.finish)
    }
    private var shown: HintCard?

    /// The prototype's padding (12 16 13) inside the face's 1 pt border, plus the window's gap.
    private static let insets = NSEdgeInsets(top: CardShape.gap + 1 + 12, left: CardShape.gap + 1 + 16,
                                             bottom: CardShape.gap + 1 + 13, right: CardShape.gap + 1 + 16)
    /// The row's, the title's and the footer's heights, and the gaps under the row, the title and
    /// the body: the prototype's line heights and margins.
    private static let rowHeight: CGFloat = 16
    private static let footHeight: CGFloat = 28
    private static let belowRow: CGFloat = 6
    private static let belowTitle: CGFloat = 3
    private static let aboveFoot: CGFloat = 12

    init() {
        super.init(frame: .zero)
        for label in [progress, optional, title, body] { addSubview(label) }
        optional.text = TourType.row.attributed("OPTIONAL", ink: Palette.inkFaint)
        optional.spoken = "Optional"
        skip.attributedTitle = TourButton.link(skip.title, size: 11, weight: .semibold)
        back.attributedTitle = TourButton.title(back.title)
        for button in [next, startUsing] { TourButton.fill(button) }
        for button in [skip, back, next, startUsing] { addSubview(button) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func show(_ card: HintCard) {
        guard card != shown else { return }
        shown = card
        progress.text = TourType.row.attributed(card.progress, ink: Palette.inkSoft)
        progress.spoken = card.progress
        optional.isHidden = !card.isOptional
        skip.isHidden = !card.canSkip
        title.text = card.title.attributed(.title)
        title.spoken = card.title.spoken
        body.text = card.body.attributed(.body)
        body.spoken = card.body.spoken
        // Only the button on screen answers Return.
        for (button, footer) in [(next, PhaseScript.Footer.backAndNext), (startUsing, .backAndStartUsing)] {
            button.isHidden = card.footer != footer
            button.keyEquivalent = button.isHidden ? "" : "\r"
        }
        needsLayout = true
        needsDisplay = true
    }

    static func size(of card: HintCard, faceWidth: CGFloat) -> CGSize {
        let width = faceWidth + 2 * CardShape.gap
        let text = width - insets.left - insets.right
        let titleHeight = TourText.height(of: card.title.attributed(.title), width: text)
        let bodyHeight = TourText.height(of: card.body.attributed(.body), width: text)
        return CGSize(width: width, height: insets.top + rowHeight + belowRow + titleHeight + belowTitle
                        + bodyHeight + aboveFoot + footHeight + insets.bottom)
    }

    override func layout() {
        super.layout()
        let insets = Self.insets
        let left = insets.left
        let right = bounds.width - insets.right
        let width = right - left
        var y = insets.top

        progress.place(in: NSRect(x: left, y: y, width: progress.fittingWidth, height: Self.rowHeight))
        optional.place(in: NSRect(x: progress.textFrame.maxX + 8, y: y, width: optional.fittingWidth, height: Self.rowHeight))
        TourButton.place(skip, textMaxX: right, y: y, height: Self.rowHeight)
        y += Self.rowHeight + Self.belowRow

        let titleHeight = TourText.height(of: title.text, width: width)
        title.place(in: NSRect(x: left, y: y, width: width, height: titleHeight))
        y += titleHeight + Self.belowTitle

        let bodyHeight = TourText.height(of: body.text, width: width)
        body.place(in: NSRect(x: left, y: y, width: width, height: bodyHeight))
        y += bodyHeight + Self.aboveFoot

        // Back's text sits 2 pt in, as the prototype pads it.
        TourButton.place(back, textMinX: left + 2, y: y + (Self.footHeight - 18) / 2, height: 18)
        for (button, minimum) in [(next, CGFloat(96)), (startUsing, 160)] {
            let width = TourButton.width(of: button, minimum: minimum)
            button.frame = NSRect(x: right - width, y: y, width: width, height: Self.footHeight)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        CardShape.fillGlass(in: bounds, lineWidth: 1, tint: Palette.Tour.hintPaper)
        CardShape.strokeEdge(in: bounds, lineWidth: 1, editing: false)
        window?.invalidateShadow()
    }
}

/// The prototype's buttons, as `ActionButton`s: a link, a plain title, and the ribbon-colored button.
/// A title button's cell centers its title with room on both sides, so a button is placed by where
/// its text goes.
enum TourButton {
    /// The prototype's `--ribbon`, which it paints opaque: these buttons, and the chips and key caps.
    static let ribbon = Palette.ribbon.withAlphaComponent(1)

    static func title(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: Palette.ribbonInk])
    }

    /// Underlined in the border color, as the prototype's "Skip the tour" links are.
    static func link(_ string: String, size: CGFloat, weight: NSFont.Weight) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: Palette.inkSoft,
            .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Palette.line])
    }

    /// 28 pt high, 16 pt of ribbon on each side of the title, radius 8. Its width comes from `width(of:minimum:)`.
    static func fill(_ button: ActionButton) {
        button.attributedTitle = title(button.title)
        button.wantsLayer = true
        button.layer?.backgroundColor = ribbon.cgColor
        button.layer?.cornerRadius = 8
    }

    static func width(of button: NSButton, minimum: CGFloat) -> CGFloat {
        max(minimum, ceil(button.attributedTitle.size().width) + 2 * 16)
    }

    private static func side(of button: NSButton) -> CGFloat {
        (button.fittingSize.width - button.attributedTitle.size().width) / 2
    }

    static func place(_ button: NSButton, textMinX: CGFloat, y: CGFloat, height: CGFloat) {
        let side = side(of: button)
        button.frame = NSRect(x: textMinX - side, y: y, width: button.fittingSize.width, height: height)
    }

    static func place(_ button: NSButton, textMaxX: CGFloat, y: CGFloat, height: CGFloat) {
        let side = side(of: button)
        button.frame = NSRect(x: textMaxX + side - button.fittingSize.width, y: y, width: button.fittingSize.width,
                              height: height)
    }
}

/// One of the prototype's text styles: its font, color and CSS line height, and how a chip hangs in
/// its lines.
struct TourType {
    let font: NSFont
    let ink: NSColor
    let lineHeight: CGFloat
    /// How far a chip's bottom hangs below the baseline: the prototype's `vertical-align` (-3 in a
    /// title, -4 in a body) plus the 2.5 pt between a chip's edge and its 13 pt icon, where CSS puts
    /// a chip's baseline.
    let chipDrop: CGFloat
    /// The chip's side margin: 2 in a title, 1 in a body.
    let chipMargin: CGFloat
    /// The prototype's letter spacing, in points.
    var tracking: CGFloat = 0

    static let title = TourType(font: EditorStyle.header, ink: Palette.ink, lineHeight: 24, chipDrop: 5.5, chipMargin: 2)
    static let body = TourType(font: EditorStyle.body, ink: Palette.ink, lineHeight: 18, chipDrop: 6.5, chipMargin: 1)
    /// "3 of 9" and OPTIONAL: tabular figures, 0.02 em apart.
    static let row = TourType(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), ink: Palette.inkSoft,
                              lineHeight: 16, chipDrop: 0, chipMargin: 0, tracking: 0.22)

    /// Text in this style, with the line height CSS gives it: the lines are `lineHeight` apart and
    /// the leading is split above and below, where TextKit would put it all above. `font` replaces the
    /// style's own, for a bold lead.
    func attributes(font: NSFont? = nil, ink: NSColor? = nil) -> [NSAttributedString.Key: Any] {
        let font = font ?? self.font
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink ?? self.ink, .paragraphStyle: paragraph,
            .baselineOffset: (lineHeight - Self.measurer.defaultLineHeight(for: font)) / 2,
        ]
        if tracking != 0 { attributes[.kern] = tracking }
        return attributes
    }

    func attributed(_ string: String, ink: NSColor? = nil) -> NSAttributedString {
        NSAttributedString(string: string, attributes: attributes(ink: ink))
    }

    private static let measurer = NSLayoutManager()
}

extension TourLine {
    /// Text in `type`, with each chip drawn as the control's symbol on a small ribbon-colored square
    /// and each key cap as its keys on one, both hung from the baseline where the prototype hangs them.
    func attributed(_ type: TourType) -> NSAttributedString {
        let attributes = type.attributes()
        let text = NSMutableAttributedString()
        for run in runs {
            switch run {
            case .text(let string):
                text.append(NSAttributedString(string: string, attributes: attributes))
            case .chip(let glyph):
                text.append(Inline.chip(glyph, margin: type.chipMargin, drop: type.chipDrop, attributes: attributes))
            case .key(let keys):
                text.append(Inline.keyCap(keys, size: type.font.pointSize, attributes: attributes))
            }
        }
        return text
    }
}

/// Chips and key caps: small pictures in a line of text. Each one's layout frame stays inside the
/// line, so TextKit spaces every line alike, and it draws at a fixed distance from the baseline.
private final class Inline: NSTextAttachmentCell {
    private let art: NSImage
    private let drop: CGFloat
    /// TextKit asks for the layout frame off the main actor's isolation, so it reads only this.
    private nonisolated let width: CGFloat

    private init(art: NSImage, drop: CGFloat) {
        self.art = art
        self.drop = drop
        width = art.size.width
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    private static func text(_ art: NSImage, drop: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = Inline(art: art, drop: drop)
        let text = NSMutableAttributedString(attachment: attachment)
        text.addAttributes(attributes, range: NSRange(location: 0, length: text.length))
        return text
    }

    static func chip(_ glyph: Glyph, margin: CGFloat, drop: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let key = "\(glyph.rawValue) \(margin)"
        let art = chips[key] ?? {
            let art = chipArt(glyph, margin: margin)
            chips[key] = art
            return art
        }()
        return text(art, drop: drop, attributes: attributes)
    }

    /// The prototype's `kbd`: semibold keys 5 pt in from each side of a 17 pt ribbon-colored cap,
    /// whose bottom is 3.5 pt below the baseline.
    static func keyCap(_ keys: String, size: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let key = "\(keys) \(size)"
        let art = caps[key] ?? {
            let art = capArt(keys, size: size)
            caps[key] = art
            return art
        }()
        return text(art, drop: capDrop, attributes: attributes)
    }

    private static var chips: [String: NSImage] = [:]
    private static var caps: [String: NSImage] = [:]
    private static let chipSide: CGFloat = 18
    private static let corner: CGFloat = 4
    private static let capHeight: CGFloat = 17
    private static let capDrop: CGFloat = 3.5
    private static let capPadding: CGFloat = 5

    private static func chipArt(_ glyph: Glyph, margin: CGFloat) -> NSImage {
        let ink = glyph == .spreadOn ? Palette.accent : Palette.ribbonInk
        // The ribbon draws the plus and the chevrons light, like thin lines.
        let weight: NSFont.Weight = [.plus, .hide, .show].contains(glyph) ? .light : .regular
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
        let symbol = NSImage(systemSymbolName: glyph.symbolName, accessibilityDescription: glyph.spoken)?
            .withSymbolConfiguration(configuration)
        return NSImage(size: NSSize(width: chipSide + 2 * margin, height: chipSide), flipped: false) { rect in
            let square = NSRect(x: margin, y: 0, width: chipSide, height: chipSide)
            TourButton.ribbon.setFill()
            NSBezierPath(roundedRect: square, xRadius: corner, yRadius: corner).fill()
            if let symbol {
                let origin = NSPoint(x: square.midX - symbol.size.width / 2, y: square.midY - symbol.size.height / 2)
                symbol.draw(in: NSRect(origin: pixelAligned(origin), size: symbol.size))
            }
            return true
        }
    }

    private static func capArt(_ keys: String, size: CGFloat) -> NSImage {
        let label = NSAttributedString(string: keys, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: Palette.ribbonInk])
        let width = ceil(label.size().width) + 2 * capPadding
        return NSImage(size: NSSize(width: width, height: capHeight), flipped: false) { rect in
            TourButton.ribbon.setFill()
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
            label.draw(with: NSRect(x: capPadding, y: capDrop, width: width - 2 * capPadding, height: capHeight),
                       options: [])
            return true
        }
    }

    /// `point` on the device's pixel grid, so an icon or a cap is never smeared across two pixels.
    private static func pixelAligned(_ point: NSPoint) -> NSPoint {
        guard let context = NSGraphicsContext.current?.cgContext else { return point }
        let device = context.convertToDeviceSpace(point)
        return context.convertToUserSpace(CGPoint(x: device.x.rounded(), y: device.y.rounded()))
    }

    nonisolated override func cellSize() -> NSSize { NSSize(width: width, height: 1) }

    nonisolated override func cellBaselineOffset() -> NSPoint { .zero }

    nonisolated override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                                        glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: 0, y: 0, width: width, height: 1)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        let baseline = flipped ? cellFrame.maxY : cellFrame.minY
        let bottom = flipped ? baseline + drop : baseline - drop
        let origin = Self.pixelAligned(NSPoint(x: cellFrame.minX, y: flipped ? bottom - art.size.height : bottom))
        art.draw(in: NSRect(origin: origin, size: art.size), from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: nil)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
                       layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }
}

/// A block of tour text, laid out the prototype's way. VoiceOver reads `spoken`, where each chip is
/// its control's name; the attachment alone would read as nothing.
final class TourText: NSView {
    var text = NSAttributedString() {
        didSet { needsDisplay = true }
    }
    var spoken = ""

    /// A body's chip hangs 2.5 pt below its line: the view reaches this far past its text on both
    /// edges so the chip is not cut off.
    static let bleed: CGFloat = 4

    override var isFlipped: Bool { true }

    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin]).height)
    }

    var fittingWidth: CGFloat { ceil(text.size().width) }

    /// Where the text itself goes, inside the view's bleed.
    var textFrame: NSRect { frame.insetBy(dx: 0, dy: Self.bleed) }

    func place(in textFrame: NSRect) { frame = textFrame.insetBy(dx: 0, dy: -Self.bleed) }

    override func draw(_ dirtyRect: NSRect) {
        text.draw(with: bounds.insetBy(dx: 0, dy: Self.bleed), options: [.usesLineFragmentOrigin])
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { spoken }
}

/// One borderless, clear, click-through window the size of the screen the panel is on. Draws, from a
/// `Pointing`, the lit cells, each ring and the panel's notch. Rings and lit cells stay under the
/// panel's face, as the prototype draws them under its hint; the notch goes over the panel's edge.
final class GuideOverlay: NSWindow {
    private let canvas = GuideCanvas()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = canvas
    }

    /// One level above `panel`, or above the menu bar while a ring is drawn around its icon.
    func apply(_ pointing: Pointing, above panel: NSWindow.Level) {
        level = pointing.needsMenuBarLevel ? NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
                                           : NSWindow.Level(panel.rawValue + 1)
        let center = CGPoint(x: pointing.panel.midX, y: pointing.panel.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.screens.first
        if let frame = screen?.frame, frame != self.frame { setFrame(frame, display: false) }
        canvas.show(pointing, origin: frame.origin)
    }

    private final class GuideCanvas: NSView {
        private var pointing: Pointing?

        /// Redraws only where the old and the new drawing reach: the window is the whole screen, and a
        /// drag shows a new pointing at every step.
        func show(_ pointing: Pointing, origin: CGPoint) {
            let local = pointing.moved(by: CGPoint(x: -origin.x, y: -origin.y))
            guard local != self.pointing else { return }
            if let old = self.pointing { setNeedsDisplay(old.reach) }
            self.pointing = local
            setNeedsDisplay(local.reach)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let pointing else { return }
            let face = pointing.panel.insetBy(dx: CardShape.gap, dy: CardShape.gap)
            NSGraphicsContext.saveGraphicsState()
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(roundedRect: face, xRadius: CardShape.radius, yRadius: CardShape.radius))
            outside.windingRule = .evenOdd
            outside.addClip()
            for cell in pointing.lit { GuideArt.drawLit(cell) }
            for ring in pointing.rings { GuideArt.drawRing(ring) }
            NSGraphicsContext.restoreGraphicsState()
            if let notch = pointing.notch { GuideArt.drawNotch(notch, on: face) }
        }
    }
}

private extension Pointing {
    /// Everything the overlay draws for this pointing lies in here: each ring with its halo and glow,
    /// each lit cell, and the panel with its notch.
    var reach: CGRect {
        let glow = 5 + GuideArt.glowBlur
        return (rings.map { $0.rect.insetBy(dx: -glow, dy: -glow) } + lit + [panel.insetBy(dx: -12, dy: -12)])
            .reduce(CGRect.null) { $0.union($1) }
    }

    func moved(by offset: CGPoint) -> Pointing {
        func move(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: offset.x, dy: offset.y) }
        return Pointing(panel: move(panel), notch: notch,
                        rings: rings.map { RingShape(rect: move($0.rect), radius: $0.radius) },
                        lit: lit.map(move), needsMenuBarLevel: needsMenuBarLevel)
    }
}

/// The prototype's `.ring`, `.lit` and `.hint::before`, drawn with AppKit.
enum GuideArt {
    /// The glow's spread. The prototype blurs 18 px, a Gaussian of sigma 9; an `NSShadow` of 20 measured
    /// close to that, where 18 gave about 8.
    static let glowBlur: CGFloat = 20

    /// A 2 pt accent ring inside `ring.rect`, a 5 pt accent halo at 20 % outside it and a soft accent
    /// glow at 35 % beyond that. Nothing is drawn inside the ring, so the control keeps its own look.
    static func drawRing(_ ring: RingShape) {
        let outer = NSBezierPath(roundedRect: ring.rect, xRadius: ring.radius, yRadius: ring.radius)

        NSGraphicsContext.saveGraphicsState()
        let outside = NSBezierPath(rect: ring.rect.insetBy(dx: -4 * glowBlur, dy: -4 * glowBlur))
        outside.append(outer)
        outside.windingRule = .evenOdd
        outside.addClip()
        let glow = NSShadow()
        glow.shadowBlurRadius = glowBlur
        glow.shadowOffset = .zero
        glow.shadowColor = Palette.accent.withAlphaComponent(0.35)
        glow.set()
        Palette.accent.setFill()
        outer.fill()   // clipped away: only its shadow shows, outside the ring
        NSGraphicsContext.restoreGraphicsState()

        Palette.accent.withAlphaComponent(0.20).setFill()
        band(outside: ring.rect, radius: ring.radius, width: 5).fill()
        Palette.accent.setFill()
        band(outside: ring.rect.insetBy(dx: 2, dy: 2), radius: max(ring.radius - 2, 0), width: 2).fill()
    }

    /// The ring between `rect` and `rect` grown by `width`, its corners following CSS's rule that a
    /// spread adds to the radius.
    private static func band(outside rect: CGRect, radius: CGFloat, width: CGFloat) -> NSBezierPath {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: -width, dy: -width),
                                xRadius: radius + width, yRadius: radius + width)
        path.append(NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius))
        path.windingRule = .evenOdd
        return path
    }

    /// A free Spread cell's face: a faint paper fill and a 1.5 pt dashed paper border just inside it.
    static func drawLit(_ face: CGRect) {
        Palette.Tour.litBase.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: face, xRadius: CardShape.radius, yRadius: CardShape.radius).fill()
        let border = NSBezierPath(roundedRect: face.insetBy(dx: 0.75, dy: 0.75),
                                  xRadius: CardShape.radius, yRadius: CardShape.radius)
        border.lineWidth = 1.5
        border.setLineDash([6, 4], count: 2, phase: 0)
        Palette.Tour.litBase.withAlphaComponent(0.85).setStroke()
        border.stroke()
    }

    /// The prototype's notch: a 14 pt square with a 1 pt border on its two outer sides, turned 45°,
    /// centered on the face's edge line so it covers the edge there and its tip points out.
    static func drawNotch(_ notch: Notch, on face: CGRect) {
        let edge: CGFloat = 0.5   // the middle of the face's 1 pt border
        let (center, angle): (CGPoint, CGFloat) = switch notch {
        case .left(let at): (CGPoint(x: face.minX + edge, y: face.maxY - at), 180)
        case .right(let at): (CGPoint(x: face.maxX - edge, y: face.maxY - at), 0)
        case .top(let at): (CGPoint(x: face.minX + at, y: face.maxY - edge), 90)
        }
        let half: CGFloat = 7.5
        NSGraphicsContext.saveGraphicsState()
        let turn = NSAffineTransform()
        turn.translateX(by: center.x, yBy: center.y)
        turn.rotate(byDegrees: angle - 45)   // the square's corner at (+, +) points along `angle`
        turn.concat()
        Palette.Tour.notch.setFill()
        NSBezierPath(rect: NSRect(x: -half, y: -half, width: 2 * half, height: 2 * half)).fill()
        // The two borders, the corner they share painted once.
        Palette.line.setFill()
        NSBezierPath(rect: NSRect(x: half - 1, y: -half, width: 1, height: 2 * half)).fill()
        NSBezierPath(rect: NSRect(x: -half, y: half - 1, width: 2 * half - 1, height: 1)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
