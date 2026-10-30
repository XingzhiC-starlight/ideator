import AppKit

/// §3.2's focus ring: a 2 pt line `focusOffset` outside a control, in `ink`, shown only while the
/// control has focus in the key window. AppKit's ring is off everywhere (`focusRingType = .none`), so
/// no system blue shows.
///
/// `SettingsWindow.makeFirstResponder` redraws the controls that gain and lose focus.
enum SettingsFocusRing {
    /// The view a responder stands for: a text field for its field editor, the instruction editor's
    /// well for its text view.
    static func owner(of responder: NSResponder?) -> NSView? {
        if let text = responder as? NSTextView {
            return text.isFieldEditor ? text.delegate as? NSView : text.enclosingScrollView ?? text
        }
        return responder as? NSView
    }

    static func shows(_ view: NSView) -> Bool {
        guard let window = view.window, window.isKeyWindow else { return false }
        return owner(of: window.firstResponder) === view
    }

    /// How far past its control the ring's outer edge reaches.
    static func reach(offset: CGFloat = SettingsStyle.focusOffset) -> CGFloat { offset + SettingsStyle.focusWidth }

    static func draw(around rect: NSRect, offset: CGFloat = SettingsStyle.focusOffset, shape: SettingsShape = .square,
                     flipped: Bool) {
        let middle = offset + SettingsStyle.focusWidth / 2
        let path = shape.path(rect.insetBy(dx: -middle, dy: -middle), outset: middle, flipped: flipped)
        path.lineWidth = SettingsStyle.focusWidth
        Palette.Settings.ink.setStroke()
        path.stroke()
    }
}

/// Square, or Save's 0/0/8/8: square top corners, rounded bottom ones (§2.4).
enum SettingsShape {
    case square, cta

    /// `outset` grows the bottom radius with the rect, so a ring around Save follows its curve.
    func path(_ rect: NSRect, outset: CGFloat = 0, flipped: Bool) -> NSBezierPath {
        guard self == .cta else { return NSBezierPath(rect: rect) }
        let radius = SettingsStyle.ctaRadius + outset
        let top = flipped ? rect.minY : rect.maxY, bottom = flipped ? rect.maxY : rect.minY
        let up: CGFloat = flipped ? -1 : 1
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: top))
        path.line(to: NSPoint(x: rect.maxX, y: top))
        path.line(to: NSPoint(x: rect.maxX, y: bottom + up * radius))
        path.appendArc(from: NSPoint(x: rect.maxX, y: bottom), to: NSPoint(x: rect.maxX - radius, y: bottom), radius: radius)
        path.line(to: NSPoint(x: rect.minX + radius, y: bottom))
        path.appendArc(from: NSPoint(x: rect.minX, y: bottom), to: NSPoint(x: rect.minX, y: bottom + up * radius), radius: radius)
        path.close()
        return path
    }
}

/// Every button in Settings. Its cell draws it; this adds what a cell can't hold: hover, room around
/// the control for the focus ring, and a click target of its own.
///
/// The ring's room is alignment insets, so layout, stack spacing and tests see the control's own size
/// while the frame has space to draw the ring in. Clicks land only on `targetRect`.
class SettingsButton: NSButton {
    override class var cellClass: AnyClass? {
        get { SettingsButtonCell.self }
        set {}
    }

    private(set) var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    private var hover: NSTrackingArea?

    init(_ look: SettingsButtonCell.Look, title: String = "", target: AnyObject? = nil, action: Selector? = nil) {
        super.init(frame: .zero)
        settingsCell.look = look
        setButtonType(look.buttonType)
        self.title = title
        self.target = target
        self.action = action
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var settingsCell: SettingsButtonCell { cell as! SettingsButtonCell }

    /// The control without its ring's room.
    var controlRect: NSRect {
        let reach = settingsCell.look.ringReach
        return bounds.insetBy(dx: reach, dy: reach)
    }

    /// The control, grown to WCAG 2.5.8's 24 × 24 where it is smaller: a checkbox is one 20 pt line
    /// tall, so its target reaches 2 pt into the gaps above and below it.
    var targetRect: NSRect {
        let rect = controlRect
        return rect.insetBy(dx: -max(0, SettingsStyle.minTarget - rect.width) / 2,
                            dy: -max(0, SettingsStyle.minTarget - rect.height) / 2)
    }

    override var alignmentRectInsets: NSEdgeInsets {
        let reach = settingsCell.look.ringReach
        return NSEdgeInsets(top: reach, left: reach, bottom: reach, right: reach)
    }

    override var intrinsicContentSize: NSSize { settingsCell.controlSize(title: title, image: image) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        targetRect.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hover { removeTrackingArea(hover) }
        let area = NSTrackingArea(rect: targetRect, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        hover = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// A pane that hides under the pointer gets no exit event.
    override func viewDidHide() {
        super.viewDidHide()
        isHovered = false
    }
}

/// One cell for every flat button look (§3.1): the look picks the size, the shape and the tick, and the
/// state comes from AppKit (`isEnabled`, `state`, `isHighlighted` while pressed) plus hover and focus.
final class SettingsButtonCell: NSButtonCell {
    enum Look: Equatable {
        /// The secondary button; a Connect button adds its glyph.
        case button
        /// Save, the one primary button.
        case primary
        case checkbox
        case segment(Edge)
        case spreadCell
        case recorder

        enum Edge { case leading, trailing }

        var buttonType: NSButton.ButtonType {
            switch self {
            case .checkbox: .switch
            case .segment: .radio
            case .spreadCell: .pushOnPushOff
            case .button, .primary, .recorder: .momentaryPushIn
            }
        }

        var ringReach: CGFloat {
            SettingsFocusRing.reach(offset: self == .spreadCell ? SettingsStyle.cellFocusOffset : SettingsStyle.focusOffset)
        }
    }

    var look = Look.button

    func controlSize(title: String, image: NSImage?) -> NSSize {
        let padding = 2 * SettingsStyle.s3
        let height = SettingsStyle.controlHeight
        switch look {
        case .button:
            let glyph = image == nil ? 0 : SettingsStyle.symbolSize + SettingsStyle.s2
            return NSSize(width: padding + glyph + width(of: title, .label), height: height)
        case .primary:
            return NSSize(width: padding + width(of: title, .term), height: height)
        case .checkbox:
            return NSSize(width: SettingsStyle.boxSize + SettingsStyle.s2 + width(of: title, .body), height: SettingsStyle.lineHeight(.body))
        case .segment:
            return NSSize(width: max(SettingsStyle.segmentMinWidth, padding + width(of: title, .term)), height: height)
        case .spreadCell:
            return SpreadCellPicker.cellSize
        case .recorder:
            return NSSize(width: max(SettingsStyle.recorderMinWidth, padding + width(of: title, .label)), height: height)
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rect = cellFrame.insetBy(dx: look.ringReach, dy: look.ringReach)
        let hovered = isEnabled && (controlView as? SettingsButton)?.isHovered == true
        switch look {
        case .button: drawButton(rect, hovered: hovered, in: controlView)
        case .primary: drawPrimary(rect, hovered: hovered, in: controlView)
        case .checkbox: drawCheckbox(rect, hovered: hovered, in: controlView)
        case .segment(let edge):
            drawSegment(rect, edge: edge, hovered: hovered, in: controlView)
            return
        case .spreadCell: drawSpreadCell(rect, hovered: hovered, in: controlView)
        case .recorder: drawRecorder(rect, hovered: hovered, in: controlView)
        }
        if isEnabled, SettingsFocusRing.shows(controlView) {
            SettingsFocusRing.draw(around: rect, shape: look == .primary ? .cta : .square, flipped: controlView.isFlipped)
        }
    }

    override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {}

    private typealias P = Palette.Settings

    private func drawButton(_ rect: NSRect, hovered: Bool, in view: NSView) {
        let pressed = isEnabled && isHighlighted
        fill(rect, pressed ? P.inverse : hovered ? P.wash : P.canvas)
        frame(rect, isEnabled ? P.ink : P.inkDisabled)
        let ink = !isEnabled ? P.inkDisabled : pressed ? P.inkInverse : P.ink
        drawContent(in: rect, role: .label, color: ink, underline: false, in: view)
    }

    private func drawPrimary(_ rect: NSRect, hovered: Bool, in view: NSView) {
        if isEnabled {
            (isHighlighted ? P.inverseRaised : P.inverse).setFill()
            SettingsShape.cta.path(rect, flipped: view.isFlipped).fill()
        } else {
            let edge = SettingsShape.cta.path(rect.insetBy(dx: 0.5, dy: 0.5), outset: -0.5, flipped: view.isFlipped)
            P.inkDisabled.setStroke()
            edge.stroke()
        }
        drawContent(in: rect, role: .term, color: isEnabled ? P.inkInverse : P.inkDisabled, underline: hovered, in: view)
    }

    private func drawCheckbox(_ rect: NSRect, hovered: Bool, in view: NSView) {
        let size = SettingsStyle.boxSize
        let box = view.backingAlignedRect(NSRect(x: rect.minX, y: rect.midY - size / 2, width: size, height: size),
                                          options: .alignAllEdgesNearest)
        let ticked = state == .on
        if ticked {
            fill(box, isEnabled ? P.inverse : P.inkDisabled)
            drawSymbol("checkmark", size: SettingsStyle.checkSize, color: isEnabled ? P.inkInverse : P.canvas, in: box, view: view)
        } else {
            fill(box, isEnabled && isHighlighted ? P.wash : P.canvas)
            frame(box, isEnabled ? P.ink : P.inkDisabled, width: hovered ? SettingsStyle.focusWidth : 1)
        }
        let label = NSRect(x: box.maxX + SettingsStyle.s2, y: rect.minY, width: rect.maxX - box.maxX - SettingsStyle.s2, height: rect.height)
        drawTitle(in: label, role: .body, color: isEnabled ? P.ink : P.inkDisabled, underline: false, centered: false, in: view)
    }

    /// The leading segment draws the shared middle line as its right edge; the trailing one leaves its
    /// left edge open. While either has focus the ring goes around the selected one (§3.1), so it
    /// crosses onto the other, canvas segment and never onto slate; each segment draws the part on it.
    private func drawSegment(_ rect: NSRect, edge: Look.Edge, hovered: Bool, in view: NSView) {
        let selected = state == .on
        let fillColor: NSColor = switch (isEnabled, selected) {
        case (true, true): P.inverse
        case (true, false): hovered || isHighlighted ? P.wash : P.canvas
        case (false, true): P.inkDisabled
        case (false, false): P.canvas
        }
        fill(rect, fillColor)
        let line = isEnabled ? P.ink : P.inkDisabled
        line.setFill()
        var edges: [CGRectEdge] = [.minYEdge, .maxYEdge, .maxXEdge]
        if edge == .leading { edges.append(.minXEdge) }
        for side in edges { rect.divided(atDistance: 1, from: side).slice.fill() }
        let label: NSColor = switch (isEnabled, selected) {
        case (true, true): P.inkInverse
        case (true, false): P.ink
        case (false, true): P.canvas
        case (false, false): P.inkDisabled
        }
        drawTitle(in: rect, role: selected ? .term : .body, color: label, underline: false, centered: true, in: view)
        let partner = view.superview?.subviews.first { $0 !== view && $0 is SettingsButton } as? SettingsButton
        let pairFocused = SettingsFocusRing.shows(view) || partner.map { SettingsFocusRing.shows($0) } == true
        guard isEnabled, pairFocused else { return }
        if selected {
            SettingsFocusRing.draw(around: rect, flipped: view.isFlipped)
        } else if let partner, partner.state == .on {
            SettingsFocusRing.draw(around: view.convert(partner.controlRect, from: partner), flipped: view.isFlipped)
        }
    }

    private func drawSpreadCell(_ rect: NSRect, hovered: Bool, in view: NSView) {
        let ticked = state == .on
        fill(rect, isEnabled && ticked ? P.accent : P.canvas)
        if hovered {
            frame(rect, P.ink, width: SettingsStyle.focusWidth)
        } else if !ticked || !isEnabled {
            frame(rect, isEnabled ? P.border : P.inkDisabled)
        }
        if let image {
            let color = isEnabled ? P.inkInverse : P.inkMuted
            drawSymbol(image, size: SettingsStyle.checkSize, weight: .semibold, color: color, in: rect, view: view)
        }
        if (view as? SpreadCellButton)?.showsFocus == true {
            SettingsFocusRing.draw(around: rect, offset: SettingsStyle.cellFocusOffset, flipped: view.isFlipped)
        }
    }

    private func drawRecorder(_ rect: NSRect, hovered: Bool, in view: NSView) {
        let recording = (view as? ShortcutField)?.isRecording == true
        fill(rect, recording ? P.inverse : hovered ? P.wash : P.surface)
        if !recording { frame(rect, P.border) }
        drawTitle(in: rect, role: .label, color: recording ? P.inkInverse : P.ink, underline: false, centered: true, in: view)
    }

    private func drawContent(in rect: NSRect, role: SettingsStyle.TextRole, color: NSColor, underline: Bool, in view: NSView) {
        guard let image else {
            drawTitle(in: rect, role: role, color: color, underline: underline, centered: true, in: view)
            return
        }
        let glyph = SettingsStyle.symbolSize + SettingsStyle.s2
        let content = glyph + width(of: title, role)
        let start = rect.midX - content / 2
        drawSymbol(image, size: SettingsStyle.symbolSize, weight: .regular, color: color,
                   in: NSRect(x: start, y: rect.minY, width: SettingsStyle.symbolSize, height: rect.height), view: view)
        let label = NSRect(x: start + glyph, y: rect.minY, width: rect.maxX - start - glyph, height: rect.height)
        drawTitle(in: label, role: role, color: color, underline: underline, centered: false, in: view)
    }

    private func drawTitle(in rect: NSRect, role: SettingsStyle.TextRole, color: NSColor, underline: Bool, centered: Bool,
                           in view: NSView) {
        var attributes: [NSAttributedString.Key: Any] = [.font: SettingsStyle.font(role), .foregroundColor: color]
        if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        let x = centered ? rect.midX - size.width / 2 : rect.minX
        let origin = view.backingAlignedRect(NSRect(x: x, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                                             options: .alignAllEdgesNearest).origin
        text.draw(at: origin)
    }

    private func drawSymbol(_ name: String, size: CGFloat, color: NSColor, in rect: NSRect, view: NSView) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        drawSymbol(image, size: size, weight: .semibold, color: color, in: rect, view: view)
    }

    private func drawSymbol(_ image: NSImage, size: CGFloat, weight: NSFont.Weight, color: NSColor, in rect: NSRect, view: NSView) {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = image.withSymbolConfiguration(configuration) else { return }
        let box = view.backingAlignedRect(NSRect(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2,
                                                 width: symbol.size.width, height: symbol.size.height),
                                          options: .alignAllEdgesNearest)
        symbol.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func width(of text: String, _ role: SettingsStyle.TextRole) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: SettingsStyle.font(role)]).width)
    }

    private func fill(_ rect: NSRect, _ color: NSColor) {
        color.setFill()
        rect.fill()
    }

    /// A border drawn inside `rect`, so a 2 pt one doesn't move the layout.
    private func frame(_ rect: NSRect, _ color: NSColor, width: CGFloat = 1) {
        color.setFill()
        rect.frame(withWidth: width)
    }
}

/// The API key field (§3.5): a `surface` well with a 1 pt `border`, 2 pt `ink` inside while you type
/// in it, and 2 pt `dangerStrong` while the pane says the Keychain refused the key.
final class SettingsKeyField: NSSecureTextField {
    override class var cellClass: AnyClass? {
        get { SettingsFieldCell.self }
        set {}
    }

    var showsError = false {
        didSet { if showsError != oldValue { needsDisplay = true } }
    }

    /// The well is the whole control, so it lines up with the column; a label's 2 pt insets don't apply.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    func restyle() {
        let words = placeholderAttributedString?.string ?? placeholderString ?? ""
        placeholderAttributedString = NSAttributedString(string: words, attributes: [
            .font: SettingsStyle.font(.monoInput), .foregroundColor: Palette.Settings.inkMuted,
        ])
    }
}

final class SettingsFieldCell: NSSecureTextFieldCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Palette.Settings.surface.setFill()
        cellFrame.fill()
        drawWellEdge(cellFrame, error: (controlView as? SettingsKeyField)?.showsError == true,
                     focused: SettingsFocusRing.shows(controlView))
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    /// The text system pads each line by 2 pt on both sides.
    private static let linePadding: CGFloat = 2

    /// Text 8 from each side, one line high in the middle, for the drawn text and the field editor alike.
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let line = ceil(font.map { $0.ascender - $0.descender + $0.leading } ?? rect.height)
        let inset = rect.insetBy(dx: SettingsStyle.s2 - Self.linePadding, dy: 0)
        return NSRect(x: inset.minX, y: (rect.midY - line / 2).rounded(), width: inset.width, height: line)
    }

    /// The field editor goes where it is told, not where `drawingRect` says, so it is told the same.
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
}

/// The instruction editor's well (§3.9): `surface`, a 1 pt `border`, 2 pt `ink` while you type in it
/// and 2 pt `dangerStrong` while the pane says it refused an edit. The border is a view above the
/// text, so lines scroll under it.
final class SettingsEditorWell: NSScrollView {
    var showsError = false {
        didSet { if showsError != oldValue { edge.needsDisplay = true } }
    }

    private let edge = WellEdge()

    override init(frame: NSRect) {
        super.init(frame: frame)
        backgroundColor = Palette.Settings.surface
        addSubview(edge, positioned: .above, relativeTo: contentView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// A scroll view lays out its own subviews here rather than by autoresizing.
    override func tile() {
        super.tile()
        edge.frame = bounds
    }

    private final class WellEdge: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            guard let well = superview as? SettingsEditorWell else { return }
            drawWellEdge(bounds, error: well.showsError, focused: SettingsFocusRing.shows(well))
        }
    }
}

private func drawWellEdge(_ rect: NSRect, error: Bool, focused: Bool) {
    let p = Palette.Settings.self
    (error ? p.dangerStrong : focused ? p.ink : p.border).setFill()
    rect.frame(withWidth: error || focused ? SettingsStyle.focusWidth : 1)
}

/// A sidebar row (§3.1): the selected one is a `canvas` block running to the sidebar's right edge, so
/// it joins the pane, with a 2 pt `ink` ring 4 inside it while the table has focus in the key window.
/// Never the system's blue.
final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        Palette.Settings.canvas.setFill()
        bounds.fill()
        if let table = superview as? NSTableView, SettingsFocusRing.shows(table) {
            Palette.Settings.ink.setFill()
            bounds.insetBy(dx: SettingsStyle.s1, dy: SettingsStyle.s1).frame(withWidth: SettingsStyle.focusWidth)
        }
    }

    /// Tells the row's cell it sits on canvas, focused or not, so its label turns to `ink`.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }
}
