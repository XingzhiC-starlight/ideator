import AppKit

/// One popped card: a borderless window on the normal layer that follows the user across Spaces
/// and over full-screen apps. It displays one `CardFace` and owns only transient UI state
/// (hover, editing, a drag in progress); everything else it reports as a `Command`.
final class CardWindow: NSWindow {
    private let cardView: CardView
    /// Where the last `apply` put the window. The window slides there, and hover goes by where it
    /// is going, so a card that arrives under a resting pointer shows its buttons.
    private var placed = CGRect.zero

    init(id: CardID, send: @escaping (Command) -> Void, drag: WindowDrag) {
        cardView = CardView(home: .desktop(drag), send: send)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        configureAsCard(self, content: cardView)
    }

    /// Borderless windows refuse key status by default; a card must take keyboard focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        cardView.editingStateChanged()
    }

    override func resignKey() {
        super.resignKey()
        cardView.editingStateChanged()
    }

    func apply(_ face: CardFace, frame: CGRect) {
        placed = frame
        if self.frame != frame {
            if isVisible {
                animator().setFrame(frame, display: true)
            } else {
                setFrame(frame, display: false)
            }
        }
        cardView.apply(face)
    }

    /// Makes this window key with the cursor at `range`, or on the header line when nil.
    func focusEditor(range: NSRange? = nil) {
        makeKeyAndOrderFront(nil)
        cardView.focusEditor(range: range)
    }

    /// The pointer is at `location`, in screen coordinates. The hover buttons show while it is
    /// over this card.
    func pointerMoved(to location: NSPoint) {
        cardView.setHovering(isVisible && placed.contains(location))
    }
}

/// The window settings cards and the stack share: borderless, transparent corners, normal level,
/// on every Space and over full-screen apps, always the light look. `content` goes on frosted
/// glass cut to the card shape; it draws the tint and edges over it (`CardShape.fillGlass`).
func configureAsCard(_ window: NSWindow, content: NSView) {
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .normal
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.acceptsMouseMovedEvents = true
    window.appearance = NSAppearance(named: .aqua)   // "neutral light cards", also in Dark Mode
    let glass = NSVisualEffectView()
    glass.material = Palette.glassMaterial
    glass.blendingMode = .behindWindow
    glass.state = .active   // Ideator is rarely the active app; inactive glass would go flat
    glass.maskImage = CardShape.maskImage
    content.frame = glass.bounds
    content.autoresizingMask = [.width, .height]
    glass.addSubview(content)
    window.contentView = glass
}

/// Card geometry shared by the card and the stack: the gap between neighbours and the corner radius.
enum CardShape {
    static let gap: CGFloat = 3
    static let radius: CGFloat = 10

    static func path(in bounds: NSRect, lineWidth: CGFloat) -> NSBezierPath {
        let rect = bounds.insetBy(dx: gap + lineWidth / 2, dy: gap + lineWidth / 2)
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    /// The glass's cut-out: the card shape, stretched from its middle pixel so the corners stay round.
    static let maskImage: NSImage = {
        let edge = gap + radius + 1
        let image = NSImage(size: NSSize(width: edge * 2 + 1, height: edge * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            path(in: rect, lineWidth: 1).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: edge, left: edge, bottom: edge, right: edge)
        image.resizingMode = .stretch
        return image
    }()

    /// The glass surface up to its sheen: the tint, the tinted `ribbon` strip if any, and the
    /// light at the top edge. A caller with more to lay between this and the edge (`strokeEdge`)
    /// does so after.
    static func fillGlass(in bounds: NSRect, lineWidth: CGFloat, ribbon: NSRect? = nil) {
        NSGraphicsContext.saveGraphicsState()
        path(in: bounds, lineWidth: lineWidth).addClip()
        Palette.paper.setFill()
        bounds.fill()
        if let ribbon {
            Palette.ribbon.setFill()
            ribbon.fill()
        }
        NSGradient(colors: [Palette.sheen.withAlphaComponent(0.10), Palette.sheen.withAlphaComponent(0)])?
            .draw(in: NSRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: bounds.height / 2), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The bright rim inside the outline, then the outline: the editing border while `editing`.
    static func strokeEdge(in bounds: NSRect, lineWidth: CGFloat, editing: Bool) {
        let shape = path(in: bounds, lineWidth: lineWidth)
        (editing ? Palette.focus : Palette.line).setStroke()
        shape.lineWidth = lineWidth
        shape.stroke()

        // Clipped to inside the inner path, so only the inner half of the 2.4pt stroke shows.
        let inner = NSBezierPath(roundedRect: shape.bounds.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        inner.setClip()
        context.addPath(inner.cgPath)
        context.setLineWidth(2.4)
        context.replacePathWithStrokedPath()
        context.clip()
        NSGradient(colors: [Palette.rim.withAlphaComponent(0.55), Palette.rim.withAlphaComponent(0.05),
                            Palette.rim.withAlphaComponent(0.22)])?.draw(in: bounds, angle: -60)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Root view of a card, on the desktop or as the stack's selected card. It owns the one decision
/// about what a press means, in this order:
/// 1. a hover button;
/// 2. the header or the card's margin: on the desktop a press that moves drags the window, and a
///    press on the header that doesn't is a normal text click (`trackWindowDrag`, called from
///    `CardTextView.mouseDown` and from here); on the stack every such press is a text click or
///    belongs to the stack's edge bands;
/// 3. the body: text editing, or "expand this card" when collapsed.
///
/// On the stack the view shows one card at a time: `apply` re-points it at the selected card, or
/// at nil for the blank page, whose first typed character becomes a card (`Command.writeBlank`).
final class CardView: NSView {
    /// Where the card lives. A desktop card draws itself and can be dragged anywhere. A
    /// stacked card is drawn by the `StackView` around it, which also draws the editing border,
    /// and cannot be dragged.
    enum Home {
        case desktop(WindowDrag)
        case stack

        var move: (title: String, help: String, command: (CardID) -> Command) {
            switch self {
            case .desktop: ("↩ Stack", "Return this card to the top of the stack", { .returnToStack($0) })
            case .stack: ("↗ Pop", "Bring this card out", { _ in .pop })
            }
        }
    }

    /// Stack home only: the card's editing state changed, so the stack redraws its border.
    var onEditingChange: (Bool) -> Void = { _ in }
    private let home: Home
    private let send: (Command) -> Void
    private let editor = CardTextView()
    private let scrollView = NSScrollView()
    private let collapsedHeader = NSTextField(labelWithString: "")
    private let summaryView = SummaryView()
    private let formatBar: FormatBar
    private let hoverButtons = HoverButtons()
    private let clarityButton = ActionButton(symbol: "rectangle.compress.vertical", help: "Collapse this card")
    private let refreshButton = ActionButton(symbol: "arrow.clockwise", help: "Refresh summary")
    private let moveButton: ActionButton
    /// Nil is the stack's blank page.
    private var face: CardFace?
    /// Whether the last `apply` showed the collapsed look; nil before the first one.
    private var showsCollapsed: Bool?
    /// Derived from AppKit (key window + editor is first responder), never set from outside.
    private var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            formatBar.isHidden = !isEditing
            needsLayout = true
            needsDisplay = true
            onEditingChange(isEditing)
        }
    }

    static let formatBarHeight: CGFloat = 24
    /// The card's margin around its content; pressing in it drags the card.
    static let margin = NSSize(width: 16, height: 12)

    init(home: Home, send: @escaping (Command) -> Void) {
        self.home = home
        self.send = send
        formatBar = FormatBar(editor: editor)
        let move = home.move
        moveButton = ActionButton(title: move.title, help: move.help)
        super.init(frame: .zero)

        editor.onChange = { [unowned self] note in
            if let id = self.face?.id {
                self.send(.edit(id, note))
            } else {
                self.send(.writeBlank(note, at: Date()))
            }
        }
        editor.onHeaderPress = { [unowned self] event in self.dragIfMoved(event) }
        editor.onFocusChange = { [unowned self] in self.editingStateChanged() }

        scrollView.documentView = editor
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        collapsedHeader.font = EditorStyle.header
        collapsedHeader.textColor = Palette.ink
        collapsedHeader.lineBreakMode = .byTruncatingTail
        collapsedHeader.maximumNumberOfLines = 1
        addSubview(collapsedHeader)
        addSubview(summaryView)

        formatBar.isHidden = true
        addSubview(formatBar)

        clarityButton.handler = { [unowned self] in
            guard let face = self.face else { return }
            self.send(.setCollapsed(face.id, !face.collapsed))
        }
        refreshButton.handler = { [unowned self] in
            if let id = self.face?.id { self.send(.refreshSummary(id)) }
        }
        moveButton.handler = { [unowned self] in
            if let id = self.face?.id { self.send(move.command(id)) }
        }
        let trashButton = ActionButton(symbol: "trash", help: "Delete this card") { [unowned self] in
            self.confirmDelete()
        }
        for button in [refreshButton, clarityButton, moveButton, trashButton] {
            hoverButtons.addArrangedSubview(button)
        }
        hoverButtons.spacing = 6
        hoverButtons.alphaValue = 0
        addSubview(hoverButtons)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ face: CardFace?, desktopFull: Bool = false) {
        let previous = self.face
        self.face = face
        let note = face?.note ?? .blank
        // Another card in the same view: leave the old card's focus and scroll position behind.
        // The blank page turning into the card typed on it has the same note, so it is not one.
        let repointed = previous?.id != face?.id && editor.note != note
        if repointed { dropFocus() }
        editor.show(note)
        if repointed {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        collapsedHeader.stringValue = note.title
        summaryView.show(face?.summary ?? .body(""))
        hoverButtons.isHidden = face == nil
        moveButton.isEnabled = !desktopFull
        moveButton.toolTip = desktopFull ? "Desktop full" : home.move.help
        let collapsed = face?.collapsed ?? false
        if showsCollapsed != collapsed {
            showsCollapsed = collapsed
            scrollView.isHidden = collapsed
            collapsedHeader.isHidden = !collapsed
            summaryView.isHidden = !collapsed
            if collapsed { dropFocus() }
            let help = collapsed ? "Expand this card" : "Collapse this card"
            clarityButton.image = NSImage(systemSymbolName: collapsed ? "rectangle.expand.vertical"
                                                                      : "rectangle.compress.vertical",
                                          accessibilityDescription: help)
            clarityButton.toolTip = help
        }
        let canRefresh: Bool = switch face?.summary {
        case .body, nil: false
        default: collapsed
        }
        refreshButton.isHidden = !canRefresh
        needsLayout = true
        needsDisplay = true
    }

    /// Puts the cursor in the editor: at `range`, or on the header line when nil (New).
    func focusEditor(range: NSRange? = nil) {
        window?.makeFirstResponder(editor)
        let length = (editor.string as NSString).length
        let location = min(range?.location ?? 0, length)
        editor.setSelectedRange(NSRange(location: location, length: min(range?.length ?? 0, length - location)))
        if range != nil { editor.scrollRangeToVisible(editor.selectedRange()) }
    }

    /// The editor's selection while this card is being edited.
    var editingSelection: NSRange? { isEditing ? editor.selectedRange() : nil }

    func dropFocus() {
        if window?.firstResponder === editor { window?.makeFirstResponder(nil) }
    }

    func editingStateChanged() {
        isEditing = window?.isKeyWindow == true && window?.firstResponder === editor
    }

    // MARK: Layout

    /// The area inside the margin. Everything lives here. Empty, not `insetBy`'s infinite null
    /// rect, when the view is smaller than its margins.
    private var content: NSRect {
        NSRect(x: bounds.minX + Self.margin.width, y: bounds.minY + Self.margin.height,
               width: max(bounds.width - 2 * Self.margin.width, 0),
               height: max(bounds.height - 2 * Self.margin.height, 0))
    }

    override func layout() {
        super.layout()
        let content = self.content
        let bar = isEditing ? Self.formatBarHeight : 0
        scrollView.frame = NSRect(x: content.minX, y: content.minY + bar,
                                  width: content.width, height: content.height - bar)
        formatBar.frame = NSRect(x: content.minX, y: content.minY, width: content.width, height: Self.formatBarHeight)
        let buttons = hoverButtons.fittingSize
        hoverButtons.frame = NSRect(x: content.maxX - buttons.width, y: content.maxY - buttons.height,
                                    width: buttons.width, height: buttons.height)
        // The title stops short of the buttons, shown or not, so hovering never reflows it.
        let titleEnd = hoverButtons.frame.minX - hoverButtons.spacing
        let headerHeight = ceil(EditorStyle.header.boundingRectForFont.height) + 2
        collapsedHeader.frame = NSRect(x: content.minX + 7, y: content.maxY - headerHeight - 2,
                                       width: titleEnd - content.minX - 7, height: headerHeight)
        // The editor wraps the title around them. The rect is in its text container's top-down
        // coordinates, so it stays beside the title when the text scrolls.
        let text = NSPoint(x: scrollView.frame.minX + editor.textContainerOrigin.x,
                           y: scrollView.frame.maxY - editor.textContainerOrigin.y)
        let besideButtons = NSRect(x: titleEnd - text.x, y: 0, width: bounds.maxX - titleEnd,
                                   height: text.y - hoverButtons.frame.minY)
        if editor.textContainer?.exclusionPaths.first?.bounds != besideButtons {   // setting it lays out all the text again
            editor.textContainer?.exclusionPaths = [NSBezierPath(rect: besideButtons)]
        }
        summaryView.frame = NSRect(x: content.minX + 7, y: content.minY,
                                   width: content.width - 14, height: collapsedHeader.frame.minY - content.minY - 4)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard case .desktop = home else { return }
        let lineWidth: CGFloat = isEditing ? 2 : 1
        CardShape.fillGlass(in: bounds, lineWidth: lineWidth)
        CardShape.strokeEdge(in: bounds, lineWidth: lineWidth, editing: isEditing)
        window?.invalidateShadow()
    }

    // MARK: Mouse

    /// The first click on an inactive card already acts (places the caret, drags), as well as
    /// activating the app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // A collapsed card's header and body are ours to handle; its buttons stay buttons.
        if face?.collapsed == true, let hit, hit !== self, !(hit is NSButton) { return self }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let face, face.collapsed, content.contains(point), point.y < collapsedHeader.frame.minY {
            send(.setCollapsed(face.id, false))     // collapsed body: expand just this card
            focusEditor(range: NSRange(location: (editor.string as NSString).length, length: 0))
            return
        }
        switch home {
        case .desktop: _ = dragIfMoved(event)       // collapsed header or the margin: drag
        case .stack: super.mouseDown(with: event)   // the margin is the stack's edge bands
        }
    }

    func setHovering(_ on: Bool) { hoverButtons.shown = on }

    /// Header press: drag the window if the pointer moves; report a plain click otherwise.
    private func dragIfMoved(_ event: NSEvent) -> Bool {
        guard case .desktop(let drag) = home, let window,
              let frame = trackWindowDrag(from: event, in: window, moved: drag.moved) else { return false }
        drag.dropped(frame)
        return true
    }

    private func confirmDelete() {
        guard let window, let id = face?.id else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this card?"
        alert.informativeText = "Its Markdown file moves to the Trash."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.send(.delete(id)) }
        }
    }
}

/// The buttons in a card's top-right corner. They fade in while the pointer is over the card. While
/// hidden they take no press, which goes to the card under them, but accessibility still lists and
/// presses them, so VoiceOver users, who cannot hover, keep them.
private final class HoverButtons: NSStackView {
    var shown = false {
        didSet {
            guard shown != oldValue else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                animator().alphaValue = shown ? 1 : 0
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { shown ? super.hitTest(point) : nil }
}

/// What a window drag reports, in screen coordinates: every move while it lasts (for the guide)
/// and the frame it was released at. The controller decides where that lands.
struct WindowDrag {
    let moved: (CGRect) -> Void
    let dropped: (CGRect) -> Void
}

/// Click or drag? Decided without stealing the click.
///
/// Peeks at the next mouse event *without dequeuing it*. If the button comes up before the
/// pointer has moved `threshold` points, this returns nil and the mouse-up is still in the
/// queue, so the caller can pass the original mouse-down to `NSTextView`, whose own tracking
/// loop then sees that mouse-up and places the caret. Once the pointer passes the threshold the
/// press is a window drag: the window comes to the front and follows the pointer until mouse-up,
/// `moved` hears each new frame, and the function returns the window's final frame. Multi-clicks
/// are never drags, so double-click still selects a word in the header.
func trackWindowDrag(from mouseDown: NSEvent, in window: NSWindow, threshold: CGFloat = 4,
                     moved: (CGRect) -> Void) -> CGRect? {
    guard mouseDown.clickCount == 1 else { return nil }
    let start = screenLocation(of: mouseDown)
    let origin = window.frame.origin
    func follow(_ event: NSEvent) {
        let now = screenLocation(of: event)
        window.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
        moved(window.frame)
    }
    var dragging = false
    var suspendedInput: NSTextInputContext?
    defer { suspendedInput?.activate() }
    while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                       until: .distantFuture, inMode: .eventTracking, dequeue: false) {
        if event.type == .leftMouseUp {
            guard dragging else { return nil }                 // a click: leave the mouse-up queued
            _ = window.nextEvent(matching: .leftMouseUp)       // consume it: the drag is over
            follow(event)                                      // a quick flick can release further on
            return window.frame
        }
        _ = window.nextEvent(matching: .leftMouseDragged)      // consume the drag we peeked at
        let now = screenLocation(of: event)
        if !dragging && hypot(now.x - start.x, now.y - start.y) < threshold { continue }
        if !dragging {
            window.orderFront(nil)
            // An active text input context makes the window server show each move about half a second late.
            suspendedInput = NSTextInputContext.current
            suspendedInput?.deactivate()
        }
        dragging = true
        follow(event)
    }
    return dragging ? window.frame : nil
}

/// Where a mouse event happened, in screen coordinates. Taken from the event itself rather than
/// the live cursor, and independent of the window, which moves during a drag.
private func screenLocation(of event: NSEvent) -> CGPoint {
    guard let location = event.cgEvent?.location, let primary = NSScreen.screens.first else {
        return NSEvent.mouseLocation
    }
    return CGPoint(x: location.x, y: primary.frame.maxY - location.y)   // CG's origin is top-left
}

/// The drag guide: an outline of the slot a drop would snap to, faint and dashed while the drop
/// would stay free, solid and filled once it would snap. Shown only during a drag, just above
/// the dragged window, and never takes the mouse.
final class SlotGuide: NSWindow {
    private let outline = GuideView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = outline
    }

    func show(_ frame: CGRect, snaps: Bool) {
        if self.frame != frame { setFrame(frame, display: false) }
        outline.snaps = snaps
        if !isVisible { orderFront(nil) }   // the dragged window came forward first
    }

    func hide() { orderOut(nil) }

    private final class GuideView: NSView {
        var snaps = false {
            didSet { if snaps != oldValue { needsDisplay = true } }
        }

        override func draw(_ dirtyRect: NSRect) {
            let lineWidth: CGFloat = snaps ? 2.5 : 1.5
            let shape = CardShape.path(in: bounds, lineWidth: lineWidth)
            if snaps {
                Palette.accent.withAlphaComponent(0.10).setFill()
                shape.fill()
                Palette.accent.withAlphaComponent(0.9).setStroke()
            } else {
                Palette.guide.setStroke()
                shape.setLineDash([6, 4], count: 2, phase: 0)
            }
            shape.lineWidth = lineWidth
            shape.stroke()
        }
    }
}

/// A collapsed card's body: up to three lines of lighter summary text, a small spinner, or
/// "Summary unavailable" with the reason as its tooltip.
final class SummaryView: NSView {
    private static let lineCount = 3
    private let label = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12)
        label.textColor = Palette.inkSoft
        label.maximumNumberOfLines = Self.lineCount
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let height = min(bounds.height, ceil(label.font!.boundingRectForFont.height * CGFloat(Self.lineCount)) + 4)
        label.frame = NSRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height)
        spinner.frame = NSRect(x: 0, y: bounds.maxY - 18, width: 16, height: 16)
    }

    func show(_ face: SummaryFace) {
        label.toolTip = nil
        switch face {
        case .body(let text):
            label.stringValue = text
            spinner.stopAnimation(nil)
        case .loading:
            label.stringValue = ""
            spinner.startAnimation(nil)
        case .text(let text):
            label.stringValue = text
            spinner.stopAnimation(nil)
        case .unavailable(let reason):
            label.stringValue = "Summary unavailable"
            label.toolTip = reason
            spinner.stopAnimation(nil)
        }
    }
}

/// The five-button bar along the bottom of the card being edited.
final class FormatBar: NSStackView {
    init(editor: CardTextView) {
        super.init(frame: .zero)
        let buttons = [
            ActionButton(symbol: "bold", help: "Bold (⌘B)") { editor.toggle(.bold) },
            ActionButton(symbol: "italic", help: "Italic (⌘I)") { editor.toggle(.italic) },
            ActionButton(symbol: "list.bullet", help: "Bulleted list") { editor.toggleLineKind(.bullet) },
            ActionButton(symbol: "list.number", help: "Numbered list") { editor.toggleLineKind(.numbered) },
            ActionButton(symbol: "checklist", help: "Checklist") { editor.toggleLineKind(.todo(done: false)) },
        ]
        for button in buttons { addArrangedSubview(button) }
        spacing = 14
        edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// NSButton with a closure instead of target/action. Acts on the first click even when the app
/// is inactive, and never takes keyboard focus away from the editor.
final class ActionButton: NSButton {
    var handler: () -> Void = {}

    convenience init(symbol: String, help: String, handler: @escaping () -> Void = {}) {
        self.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        imagePosition = .imageOnly
        setUp(help: help, handler: handler)
    }

    convenience init(title: String, help: String, handler: @escaping () -> Void = {}) {
        self.init(frame: .zero)
        self.title = title
        font = .systemFont(ofSize: 11)
        setUp(help: help, handler: handler)
    }

    private func setUp(help: String, handler: @escaping () -> Void) {
        self.handler = handler
        toolTip = help
        isBordered = false
        refusesFirstResponder = true
        contentTintColor = Palette.inkSoft
        target = self
        action = #selector(fire)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func fire() { handler() }
}
