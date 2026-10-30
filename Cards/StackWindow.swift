import AppKit

/// The stack: its own card-sized window, the app's control center. Same window behaviour as a
/// card (borderless, normal layer, all Spaces), dragged by its ribbon instead of a header, and it
/// never hides: under Hide all it shrinks to its ribbon. Its selected card is edited in place.
final class StackWindow: NSWindow {
    private let stackView: StackView
    private let send: (Command) -> Void
    private var swipes = SwipeTracker()
    /// The full card frame from the last `apply`, which the window is only the top of under Hide all.
    private var cardFrame = CGRect.zero
    /// The window's frame from the last `apply`. A snap slides there, and hover goes by where it is going.
    private var placed = CGRect.zero

    /// `spread` gets true for a fresh set: Option-click, or the button's "New spread" action.
    init(send: @escaping (Command) -> Void, menu: @escaping () -> NSMenu, toggleHidden: @escaping () -> Void,
         spread: @escaping (_ fresh: Bool) -> Void = { _ in }, drag: WindowDrag) {
        self.send = send
        stackView = StackView(send: send, menu: menu, toggleHidden: toggleHidden, spread: spread)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        configureAsCard(self, content: stackView)
        // A drag always reports the whole card, whose top edge is the ribbon's.
        stackView.onRibbonPress = { [unowned self] event in
            func card(_ frame: CGRect) -> CGRect {
                CGRect(x: frame.minX, y: frame.maxY - self.cardFrame.height,
                       width: self.cardFrame.width, height: self.cardFrame.height)
            }
            guard let frame = trackWindowDrag(from: event, in: self, moved: { drag.moved(card($0)) }) else { return false }
            drag.dropped(card(frame))
            return true
        }
    }

    override var canBecomeKey: Bool { true }

    /// A two-finger horizontal swipe flips the stack; a vertical one scrolls the card's text.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, stackView.showsCard else {
            super.sendEvent(event)
            return
        }
        switch swipes.feed(phase: event.phase, momentumPhase: event.momentumPhase,
                           deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, at: event.timestamp) {
        case .pass: super.sendEvent(event)
        case .consume: break
        case .flip(let direction): send(.flipStack(direction))
        }
    }

    override func becomeKey() {
        super.becomeKey()
        stackView.editingStateChanged()
    }

    override func resignKey() {
        super.resignKey()
        stackView.editingStateChanged()
    }

    /// Under Hide all (`visibility`) the window shrinks to the top of `cell` and the card area
    /// goes; the ribbon's button then offers Show all. `spreadRefusal` is why the last Spread click
    /// changed nothing, for the Spread button's tooltip.
    func apply(_ face: StackFace, cell: CGRect, visibility: Visibility, spreadRefusal: SpreadRefusal? = nil) {
        cardFrame = cell
        stackView.apply(face, visibility: visibility, spreadRefusal: spreadRefusal)
        let frame = visibility.showsStackCard ? cell : Self.ribbonOnlyFrame(in: cell)
        placed = frame
        guard self.frame != frame else { return }
        if isVisible && self.frame.size == frame.size {
            animator().setFrame(frame, display: true)   // snapping or sliding back on screen
        } else {
            setFrame(frame, display: true)
        }
    }

    /// The ribbon and the gap around it, at the top of the stack's cell.
    static func ribbonOnlyFrame(in cell: CGRect) -> CGRect {
        let height = StackView.ribbonHeight + 2 * CardShape.gap
        return CGRect(x: cell.minX, y: cell.maxY - height, width: cell.width, height: height)
    }

    /// Makes this window key with the cursor in the shown card (the blank page after New refused).
    func focusEditor() {
        makeKeyAndOrderFront(nil)
        stackView.focusEditor()
    }

    /// The shown card's selection while it is being edited, for Pop to carry to the popped card.
    var editingSelection: NSRange? { stackView.editingSelection }

    /// The pointer is at `location`, in screen coordinates.
    func pointerMoved(to location: NSPoint) {
        let point = NSPoint(x: location.x - placed.minX, y: location.y - placed.minY)
        stackView.hover(at: isVisible && placed.contains(location) ? point : nil)
    }
}

/// A toolbar symbol drawn once into a bitmap at its window's pixel density, and the blank points it
/// leaves before and after its ink (symbols carry side bearings). The button shows this bitmap, not
/// the symbol, so the ink measured here is the ink on screen: a symbol redraws for every context, and
/// on a 1x screen macOS 26 drew some up to a point narrower in the window than on their own.
private struct RibbonIcon {
    let image: NSImage
    let scale: CGFloat
    let lead: CGFloat
    let trail: CGFloat

    init?(_ symbol: NSImage, scale: CGFloat) {
        let size = NSSize(width: (symbol.size.width * scale).rounded(.up) / scale,
                          height: (symbol.size.height * scale).rounded(.up) / scale)
        let columns = Int((size.width * scale).rounded())
        let rows = Int((size.height * scale).rounded())
        guard columns > 0, rows > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: columns, pixelsHigh: rows,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
        NSGraphicsContext.restoreGraphicsState()
        let inked = (0..<columns).filter { x in
            (0..<rows).contains { y in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 }
        }
        guard let first = inked.first, let last = inked.last else { return nil }
        image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        image.accessibilityDescription = symbol.accessibilityDescription
        self.scale = scale
        lead = CGFloat(first) / scale
        trail = CGFloat(columns - 1 - last) / scale
    }
}

/// Looks like one card: a tan ribbon with the toolbar (New, Hide all / Show all, Spread, Clarity),
/// "Desktop full" and the app menu button, above the selected stacked card, which is a full `CardView`. The
/// count badge sits in that card's bottom-right corner, and in the ribbon beside the menu button
/// while Hide all has removed the card. The window's margin is
/// four invisible edge bands that select another stacked card: left/top the previous,
/// right/bottom the next.
/// The stack draws the card shape and the editing border; the `CardView` inside draws nothing.
private final class StackView: NSView {
    /// A press on the ribbon's empty space: true when it moved and dragged the window, false for a click.
    var onRibbonPress: (NSEvent) -> Bool = { _ in false }
    private let send: (Command) -> Void
    private let newButton: ActionButton
    private let toggleButton: ActionButton
    private let spreadButton: ActionButton
    private let clarityButton: ActionButton
    /// Left to right at the ribbon's left edge.
    private var toolbar: [ActionButton] { [newButton, toggleButton, spreadButton, clarityButton] }
    /// Each toolbar button's symbol, and the bitmap of it that the button shows.
    private var symbols: [ObjectIdentifier: NSImage] = [:]
    private var icons: [ObjectIdentifier: RibbonIcon] = [:]
    private let menuButton = ActionButton(symbol: "ellipsis.circle", help: "Settings and quit")
    private let cardView: CardView
    /// False under Hide all: the window is only the ribbon, and the edge bands do nothing.
    private(set) var showsCard = true
    /// Hide all is on: the toggle's chevron points down and offers Show all.
    private var allHidden = false {
        didSet {
            guard allHidden != oldValue else { return }
            let help = allHidden ? "Show all" : "Hide all"
            setIcon(allHidden ? "chevron.down" : "chevron.up", help, on: toggleButton, weight: .light)
            toggleButton.toolTip = help
            toggleButton.setAccessibilityLabel(help)
        }
    }
    private var clarity = false {
        didSet {
            guard clarity != oldValue else { return }
            setIcon(clarity ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle", "Clarity", on: clarityButton)
        }
    }
    private let badge = CountBadge()
    private let arranger: StackArranger
    private let fullLabel = NSTextField(labelWithString: "Desktop full")
    private var hoveredEdge: Edge? {
        didSet { if hoveredEdge != oldValue { needsDisplay = true } }
    }
    private var cardEditing = false {
        didSet { if cardEditing != oldValue { needsDisplay = true } }
    }

    static let ribbonHeight: CGFloat = 40
    /// Between the toolbar icons' drawn (inked) edges; each hit area reaches a few points into it.
    static let toolbarGap: CGFloat = 12

    /// A ribbon icon at 13 points; the plus and the chevron are light, like thin lines.
    private static func icon(_ symbol: String, _ help: String, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: weight))
    }

    private func setIcon(_ symbol: String, _ help: String, on button: ActionButton, weight: NSFont.Weight = .regular) {
        symbols[ObjectIdentifier(button)] = Self.icon(symbol, help, weight: weight)
        showIcon(on: button, scale: backingScale)
        needsLayout = true
    }

    private func showIcon(on button: ActionButton, scale: CGFloat) {
        let id = ObjectIdentifier(button)
        icons[id] = symbols[id].flatMap { RibbonIcon($0, scale: scale) }
        button.image = icons[id]?.image ?? symbols[id]
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    init(send: @escaping (Command) -> Void, menu: @escaping () -> NSMenu, toggleHidden: @escaping () -> Void,
         spread: @escaping (_ fresh: Bool) -> Void) {
        self.send = send
        arranger = StackArranger(send: send)
        cardView = CardView(home: .stack, send: send)
        newButton = ActionButton(symbol: "plus", help: "New card") { send(.new(at: Date())) }
        toggleButton = ActionButton(symbol: "chevron.up", help: "Hide all") { toggleHidden() }
        // The one place Option is read: the click's own mouse-up. A test press or VoiceOver carries
        // no modifier, so it spreads; "New spread" below is their way to a fresh set.
        spreadButton = ActionButton(symbol: "square.grid.2x2", help: "Spread cards") {
            spread(NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
        }
        clarityButton = ActionButton(symbol: "line.3.horizontal.decrease.circle", help: "")
        super.init(frame: .zero)

        setIcon("plus", "New", on: newButton, weight: .light)
        newButton.setAccessibilityLabel("New")
        setIcon("chevron.up", "Hide all", on: toggleButton, weight: .light)
        toggleButton.setAccessibilityLabel("Hide all")
        setIcon("square.grid.2x2", "Spread", on: spreadButton)
        spreadButton.setAccessibilityLabel("Spread")
        // On the cell: an NSButton's accessibility actions come from its cell, which ignores any set on the button.
        spreadButton.cell?.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "New spread") { spread(true); return true },
        ])
        setIcon("line.3.horizontal.decrease.circle", "Clarity", on: clarityButton)
        clarityButton.setAccessibilityLabel("Clarity")
        clarityButton.handler = { [unowned self] in send(.setClarity(!self.clarity)) }
        for button in toolbar {
            button.contentTintColor = Palette.ribbonInk
            addSubview(button)
        }

        menuButton.contentTintColor = Palette.ribbonInk
        menuButton.handler = { [unowned menuButton] in
            // Drops down from the button, like a menu bar menu (the button view is flipped).
            menu().popUp(positioning: nil, at: NSPoint(x: 0, y: menuButton.bounds.maxY + 4), in: menuButton)
        }
        addSubview(menuButton)

        cardView.onEditingChange = { [unowned self] editing in self.cardEditing = editing }
        addSubview(cardView)

        badge.handler = { [unowned self] in arranger.toggle(relativeTo: badge.frame, of: self) }
        addSubview(badge)

        fullLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        fullLabel.textColor = Palette.danger
        fullLabel.lineBreakMode = .byTruncatingTail
        fullLabel.toolTip = "Desktop full: no free slot for Pop or New"   // truncated, it may read only "…"
        fullLabel.isHidden = true
        addSubview(fullLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ face: StackFace, visibility: Visibility, spreadRefusal: SpreadRefusal?) {
        let showsCard = visibility.showsStackCard
        if self.showsCard != showsCard {
            self.showsCard = showsCard
            cardView.isHidden = !showsCard
            if !showsCard {
                cardView.dropFocus()
                hoveredEdge = nil
            }
        }
        allHidden = visibility.isHidden
        cardView.apply(face.selected, desktopFull: face.desktopFull)
        badge.show(count: face.count)
        arranger.apply(face.arrangement)
        fullLabel.isHidden = !face.desktopFull
        clarity = face.clarity
        clarityButton.contentTintColor = face.clarity ? Palette.accent : Palette.ribbonInk
        clarityButton.toolTip = face.clarity ? "Clarity is on: click to expand every card"
                                             : "Clarity is off: click to collapse every card"
        clarityButton.setAccessibilityValue(face.clarity ? "on" : "off")
        let out = face.spreadButton.isOut
        spreadButton.contentTintColor = out ? Palette.accent : Palette.ribbonInk
        spreadButton.toolTip = face.spreadButton.help(after: spreadRefusal)
        spreadButton.setAccessibilityValue(out ? "out" : "in")
        needsLayout = true
        needsDisplay = true
    }

    /// The pointer is at `point` (view coordinates), or outside the window.
    func hover(at point: NSPoint?) {
        hoveredEdge = point.flatMap(edge(at:))
        cardView.setHovering(showsCard && point.map { cardView.frame.contains($0) } ?? false)
    }

    func editingStateChanged() { cardView.editingStateChanged() }

    func focusEditor() { cardView.focusEditor() }

    var editingSelection: NSRange? { cardView.editingSelection }

    // MARK: Layout

    /// Everything but the edge bands lives inside this.
    private var content: NSRect {
        bounds.insetBy(dx: bounds.width * EdgeBands.fraction, dy: bounds.height * EdgeBands.fraction)
    }

    /// The ribbon across the top of the card.
    private var ribbonRect: NSRect {
        NSRect(x: bounds.minX, y: bounds.maxY - CardShape.gap - Self.ribbonHeight,
               width: bounds.width, height: Self.ribbonHeight + CardShape.gap)
    }

    /// The toolbar's icons sit at the left, `toolbarGap` apart between the ink they draw, not between
    /// their images, whose side bearings differ. They sit on whole pixels, so each bitmap shows one to
    /// one and every gap is the same count of pixels. Right to left, the ribbon holds the menu button, the
    /// badge (only under Hide all, since the card area that normally has it is gone) and "Desktop
    /// full". The toolbar and the buttons never move:
    /// "Desktop full" takes what room is left and truncates, and the badge hides once there is no
    /// room for it.
    override func layout() {
        super.layout()
        let inner = content
        let ribbonMid = ribbonRect.minY + Self.ribbonHeight / 2
        // The card's own margin reaches into the edge bands; its text stays inside them.
        let left = max(inner.minX - CardView.margin.width, bounds.minX)
        let right = min(inner.maxX + CardView.margin.width, bounds.maxX)
        let bottom = max(inner.minY - CardView.margin.height, bounds.minY)
        let card = NSRect(x: left, y: bottom, width: right - left, height: ribbonRect.minY - bottom)
        if showsCard { cardView.frame = card }

        let scale = backingScale
        for button in toolbar where icons[ObjectIdentifier(button)]?.scale != scale {
            showIcon(on: button, scale: scale)
        }
        var edge = (inner.minX * scale).rounded() / scale   // where the next icon's ink starts
        for button in toolbar {
            let icon = icons[ObjectIdentifier(button)]
            let imageWidth = button.image?.size.width ?? 0
            // The hit area, at least 18 wide, centered on the image by whole pixels: AppKit shifts an
            // image that would sit on a half pixel by a pixel.
            let inset = max(3, ((18 - imageWidth) / 2 * scale).rounded(.up) / scale)
            let imageMinX = edge - (icon?.lead ?? 0)
            button.frame = NSRect(x: imageMinX - inset, y: ribbonMid - 10, width: imageWidth + 2 * inset, height: 18)
            edge = imageMinX + imageWidth - (icon?.trail ?? 0) + Self.toolbarGap
        }
        let toolbarEnd = clarityButton.frame.maxX
        menuButton.frame = NSRect(x: inner.maxX - 18, y: ribbonMid - 10, width: 18, height: 18)
        let badgeWidth = max(22, badge.fittingSize.width + 10)
        var trailing = menuButton.frame.minX
        if showsCard {
            // In the card's bottom-right at its content inset: clear of the hover buttons at the
            // top and of the formatting bar's buttons, which are at the left of its row.
            let text = card.insetBy(dx: CardView.margin.width, dy: CardView.margin.height)
            badge.frame = NSRect(x: text.maxX - badgeWidth, y: text.minY + (CardView.formatBarHeight - 17) / 2,
                                 width: badgeWidth, height: 17)
            badge.layer?.backgroundColor = Palette.ribbon.withAlphaComponent(0.55).cgColor
            badge.isHidden = false
        } else {
            badge.frame = NSRect(x: trailing - 8 - badgeWidth, y: ribbonMid - 9.5, width: badgeWidth, height: 17)
            badge.layer?.backgroundColor = Palette.paper.withAlphaComponent(0.85).cgColor
            badge.isHidden = badge.frame.minX < toolbarEnd + 8
            if !badge.isHidden { trailing = badge.frame.minX }
        }
        let room = max(trailing - toolbarEnd - 2 * 8, 0)
        let fullWidth = min(fullLabel.fittingSize.width, room)
        fullLabel.frame = NSRect(x: trailing - 8 - fullWidth, y: ribbonMid - 9, width: fullWidth, height: 15)
        arranger.follow(badge.isHidden || !badge.isEnabled ? nil : badge.frame)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = cardEditing ? 2 : 1
        CardShape.fillGlass(in: bounds, lineWidth: lineWidth, ribbon: ribbonRect)
        if let edge = hoveredEdge {
            let band = EdgeBands.rect(of: edge, in: bounds)
            NSGraphicsContext.saveGraphicsState()
            CardShape.path(in: bounds, lineWidth: lineWidth).addClip()
            Palette.shade.setFill()
            band.fill()
            NSGraphicsContext.restoreGraphicsState()
            let chevron = NSAttributedString(string: edge.direction == .previous ? "‹" : "›", attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: Palette.inkSoft,
            ])
            let size = chevron.size()
            chevron.draw(at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2))
        }
        CardShape.strokeEdge(in: bounds, lineWidth: lineWidth, editing: cardEditing)
        window?.invalidateShadow()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The ribbon's labels (badge, "Desktop full") and the toolbar's gaps are part of its
    /// draggable empty space; only its buttons stay buttons.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hit, !(hit is NSButton), ribbonRect.contains(convert(point, from: superview)) { return self }
        return hit
    }

    /// The ribbon drags the window. A press anywhere that does not move is a click, which the
    /// edge band under it, if any, turns into a flip.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if ribbonRect.contains(point), onRibbonPress(event) { return }
        if let edge = edge(at: point) {
            send(.flipStack(edge.direction))
        }
    }

    private func edge(at point: CGPoint) -> Edge? {
        guard showsCard, !content.contains(point) else { return nil }
        return EdgeBands.edge(at: point, in: bounds)
    }
}

/// The count of stacked cards, and the button that opens the arranger. With no cards it is
/// disabled and takes no click, so a press on it reaches whatever is under it, as it did when the
/// badge was a plain label.
private final class CountBadge: NSButton {
    var handler: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        contentTintColor = Palette.ribbonInk
        alignment = .center
        focusRingType = .exterior
        wantsLayer = true
        layer?.cornerRadius = 8
        toolTip = "Arrange the stack"
        target = self
        action = #selector(fire)
        show(count: 0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(count: Int) {
        title = "\(count)"
        isEnabled = count > 0
        setAccessibilityLabel(count == 1 ? "1 card in the stack" : "\(count) cards in the stack")
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((title as NSString).size(withAttributes: [.font: font as Any]).width) + 4, height: 14)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { isEnabled ? super.hitTest(point) : nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A click leaves the card's caret where it is; Tab reaches the badge only with full keyboard access.
    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled && isEnabled }

    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill() }

    override var focusRingMaskBounds: NSRect { bounds }

    @objc private func fire() { handler() }
}
