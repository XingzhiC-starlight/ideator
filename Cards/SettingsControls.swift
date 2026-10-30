import AppKit
import Carbon.HIToolbox

/// SETTINGS-DESIGN.md's spacing (§2.3), sizes (§2.5) and type roles (§2.2) as names. A pane asks for
/// a gap or a role, never a value. Its colors are system colors, not §2.1's palette.
enum SettingsStyle {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32

    static let windowSize = NSSize(width: 640, height: 640)
    static let titleBar: CGFloat = 28
    static let sidebarWidth: CGFloat = 168
    static let sidebarRowHeight: CGFloat = 32
    static let contentWidth: CGFloat = 408
    static let controlHeight: CGFloat = 28
    static let editorSize = NSSize(width: 408, height: 112)
    static let contentTop = titleBar + s5

    enum TextRole { case title, display, lead, label, term, body, caption, mono, monoInput }
    enum Tone { case ink, muted }

    static func font(_ role: TextRole) -> NSFont {
        switch role {
        case .title: .systemFont(ofSize: 24, weight: .semibold)
        case .display: serif(24)
        case .lead: .systemFont(ofSize: 16)
        case .label: .systemFont(ofSize: 14, weight: .medium)
        case .term: .systemFont(ofSize: 14, weight: .semibold)
        case .body: .systemFont(ofSize: 14)
        case .caption: .systemFont(ofSize: 12)
        case .mono: .monospacedSystemFont(ofSize: 12, weight: .regular)
        case .monoInput: .monospacedSystemFont(ofSize: 14, weight: .regular)
        }
    }

    static func lineHeight(_ role: TextRole) -> CGFloat {
        switch role {
        case .title, .display: 32
        case .lead: 24
        case .label, .term, .body, .monoInput: 20
        case .caption, .mono: 16
        }
    }

    static func color(_ tone: Tone) -> NSColor {
        switch tone {
        case .ink: .labelColor
        case .muted: .secondaryLabelColor
        }
    }

    static func tint(_ kind: SettingsStatus.Kind) -> NSColor? {
        switch kind {
        case .neutral: nil
        case .success: .systemGreen
        case .warning: .systemOrange
        case .error: .systemRed
        }
    }

    /// AppKit puts all of a taller line's extra height above the text, so the baseline rises by half
    /// of it: the text sits in the middle of its line, as "16 / 24" means in the brief.
    static func attributed(_ text: String, as role: TextRole, tone: Tone) -> NSAttributedString {
        let font = font(role)
        let line = lineHeight(role)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = line
        paragraph.maximumLineHeight = line
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color(tone), .paragraphStyle: paragraph,
            .baselineOffset: (line - (font.ascender - font.descender)) / 2,
        ])
    }

    private static func serif(_ size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    }
}

/// A label in one of the type roles.
final class SettingsText: NSTextField {
    var role = SettingsStyle.TextRole.body
    var tone = SettingsStyle.Tone.ink { didSet { stringValue = stringValue } }

    override var stringValue: String {
        get { super.stringValue }
        set { attributedStringValue = SettingsStyle.attributed(newValue, as: role, tone: tone) }
    }
}

/// A pane asks for a control by its job, and this decides the class, the size and the type, so the
/// look can change here without touching a pane.
enum SettingsControl {
    enum RowAlignment { case leading, trailing, apart }

    static func text(_ string: String, as role: SettingsStyle.TextRole,
                     width: CGFloat = SettingsStyle.contentWidth) -> SettingsText {
        let label = SettingsText(wrappingLabelWithString: "")
        label.role = role
        label.font = SettingsStyle.font(role)
        label.tone = role == .caption || role == .mono ? .muted : .ink
        label.preferredMaxLayoutWidth = width
        label.cell?.truncatesLastVisibleLine = false
        label.stringValue = string
        return label
    }

    static func button(_ title: String, symbol: String? = nil, widestOf titles: [String] = [],
                       target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = SettingsStyle.font(.label)
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            button.imagePosition = .imageLeading
        }
        let widest = titles.map { other -> CGFloat in
            button.title = other
            return button.fittingSize.width
        }.max()
        button.title = title
        if let widest { button.widthAnchor.constraint(greaterThanOrEqualToConstant: widest).isActive = true }
        return button
    }

    /// The window's default button. AppKit skips the key equivalents of a hidden pane, so Return
    /// reaches it only while its pane shows.
    static func primaryButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let primary = button(title, target: target, action: action)
        primary.keyEquivalent = "\r"
        return primary
    }

    static func checkbox(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: target, action: action)
        box.controlSize = .large
        box.font = SettingsStyle.font(.body)
        return box
    }

    /// Radios in one superview with one action, so AppKit groups them and VoiceOver says "1 of 2".
    static func segments(_ titles: [String], target: AnyObject, action: Selector) -> (row: NSStackView, buttons: [NSButton]) {
        let buttons = titles.map { title in
            let radio = NSButton(radioButtonWithTitle: title, target: target, action: action)
            radio.controlSize = .large
            radio.font = SettingsStyle.font(.body)
            return radio
        }
        let row = NSStackView(views: buttons)
        row.spacing = SettingsStyle.s2
        return (row, buttons)
    }

    static func secureField(placeholder: String) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.controlSize = .large
        field.font = SettingsStyle.font(.monoInput)
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: SettingsStyle.contentWidth),
            field.heightAnchor.constraint(equalToConstant: SettingsStyle.controlHeight),
        ])
        return field
    }

    static func editor() -> (scroll: NSScrollView, textView: NSTextView) {
        let size = SettingsStyle.editorSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
        textView.minSize = NSSize(width: 0, height: size.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: SettingsStyle.s2, height: SettingsStyle.s2)
        textView.font = SettingsStyle.font(.body)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: size.width),
            scroll.heightAnchor.constraint(equalToConstant: size.height),
        ])
        return (scroll, textView)
    }

    static func row(_ views: [NSView], _ alignment: RowAlignment = .leading) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = SettingsStyle.s2
        switch alignment {
        case .leading:
            views.forEach { row.addArrangedSubview($0) }
        case .trailing:
            views.forEach { row.addView($0, in: .trailing) }
        case .apart:
            views.prefix(1).forEach { row.addView($0, in: .leading) }
            views.dropFirst().forEach { row.addView($0, in: .trailing) }
        }
        if alignment != .leading {
            row.widthAnchor.constraint(equalToConstant: SettingsStyle.contentWidth).isActive = true
        }
        return row
    }
}

/// A status line (§3.10): an optional glyph, then the text. With no status it shows its resting
/// caption, muted, or hides when it has none, so the caption above it never moves.
///
/// It owns the announcement rule: only a change to a new status is spoken, never the first one (the
/// window filling itself is not news), and never while its pane is hidden (six panes refresh at once).
final class StatusLine: NSStackView {
    private static let glyphSize = NSSize(width: 12, height: SettingsStyle.lineHeight(.caption))
    private let resting: String?
    private let announce: (String) -> Void
    private let glyph = NSImageView()
    private let label = SettingsControl.text("", as: .caption)
    private var seeded = false
    private(set) var status: SettingsStatus?

    init(resting: String?, announce: @escaping (String) -> Void) {
        self.resting = resting
        self.announce = announce
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .top
        spacing = SettingsStyle.s1
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        glyph.imageScaling = .scaleNone
        glyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glyph.widthAnchor.constraint(equalToConstant: Self.glyphSize.width),
            glyph.heightAnchor.constraint(equalToConstant: Self.glyphSize.height),
        ])
        addArrangedSubview(glyph)
        addArrangedSubview(label)
        render(nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ status: SettingsStatus?) {
        let changed = seeded && status != self.status
        seeded = true
        self.status = status
        render(status)
        if changed, let status, !isHiddenOrHasHiddenAncestor { announce(status.spoken) }
    }

    private func render(_ status: SettingsStatus?) {
        let symbol = status?.kind.glyph
        glyph.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: status?.kind.spokenPrefix) }
        glyph.contentTintColor = status.flatMap { SettingsStyle.tint($0.kind) }
        glyph.isHidden = symbol == nil
        label.preferredMaxLayoutWidth = SettingsStyle.contentWidth - (symbol == nil ? 0 : Self.glyphSize.width + spacing)
        label.tone = status == nil ? .muted : .ink
        label.stringValue = status?.text ?? resting ?? ""
        isHidden = status == nil && resting == nil
    }
}

/// Settings › Spread (§3.8): the desktop's 5 × 4 cells as toggle buttons in reading order, named
/// "Spread cell 1" to "Spread cell 20". The stack's cell is dimmed, shows the stack, reads "The
/// stack, dimmed" and can't be ticked, whatever is stored for it.
///
/// One tab stop: the cells refuse focus, and the picker tracks `focusedCell`, moves it with the arrow
/// keys past the stack's cell, and ticks it with Space. The system ring is masked to that cell.
final class SpreadCellPicker: NSView {
    /// About the shape of one cell of a laptop screen, and at least 24 × 24 to click.
    static let cellSize = NSSize(width: 32, height: 24)
    static let spacing: CGFloat = 4
    var onToggle: (Slot) -> Void = { _ in }
    private let buttons: [SpreadCellButton]
    private var stackCell = Slot.stackHome
    private(set) var focusedCell = Slot.all[0]

    init() {
        buttons = Slot.all.map { slot in
            let button = SpreadCellButton(title: "", target: nil, action: nil)
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .smallSquare
            button.imagePosition = .imageOnly
            button.refusesFirstResponder = true
            button.setAccessibilityLabel(SettingsCopy.Spread.cell(slot.index + 1))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Self.cellSize.width).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.cellSize.height).isActive = true
            return button
        }
        super.init(frame: .zero)
        for button in buttons {
            button.target = self
            button.action = #selector(toggle)
        }
        let grid = NSGridView(views: (0..<Slot.rows).map { row in
            Array(buttons[row * Slot.columns..<(row + 1) * Slot.columns])
        })
        grid.rowSpacing = Self.spacing
        grid.columnSpacing = Self.spacing
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        let columns = CGFloat(Slot.columns), rows = CGFloat(Slot.rows)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: columns * Self.cellSize.width + (columns - 1) * Self.spacing),
            heightAnchor.constraint(equalToConstant: rows * Self.cellSize.height + (rows - 1) * Self.spacing),
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ cells: SpreadCells, stackCell: Slot) {
        self.stackCell = stackCell
        for (slot, button) in zip(Slot.all, buttons) {
            let ticked = slot != stackCell && cells.contains(slot)
            button.isEnabled = slot != stackCell
            button.state = ticked ? .on : .off
            button.image = slot == stackCell ? NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil)
                : ticked ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) : nil
            button.isStack = slot == stackCell
        }
        moveFocusOffStack()
    }

    /// The stack moved onto the focused cell: step right, or left at the grid's right edge.
    private func moveFocusOffStack() {
        guard focusedCell == stackCell else { return }
        let right = Self.step(from: focusedCell, dx: 1, dy: 0, skipping: stackCell)
        moveFocus(to: right != focusedCell ? right : Self.step(from: focusedCell, dx: -1, dy: 0, skipping: stackCell))
    }

    /// Where an arrow lands from `cell`: the next cell that way, past the stack's, or `cell` itself
    /// at the edge of the grid.
    static func step(from cell: Slot, dx: Int, dy: Int, skipping stackCell: Slot) -> Slot {
        var column = cell.index % Slot.columns, row = cell.index / Slot.columns
        repeat {
            column += dx
            row += dy
            guard (0..<Slot.columns).contains(column), (0..<Slot.rows).contains(row) else { return cell }
        } while row * Slot.columns + column == stackCell.index
        return Slot.all[row * Slot.columns + column]
    }

    /// A tab stop only where buttons are: with Full Keyboard Access on.
    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled }

    override func becomeFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return true
    }

    override func resignFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return true
    }

    override func keyDown(with event: NSEvent) {
        let moves: [Int: (dx: Int, dy: Int)] = [kVK_LeftArrow: (-1, 0), kVK_RightArrow: (1, 0), kVK_UpArrow: (0, -1), kVK_DownArrow: (0, 1)]
        if let move = moves[Int(event.keyCode)] {
            moveFocus(to: Self.step(from: focusedCell, dx: move.dx, dy: move.dy, skipping: stackCell))
        } else if Int(event.keyCode) == kVK_Space {
            onToggle(focusedCell)
        } else {
            super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { frame(of: focusedCell) }

    override func drawFocusRingMask() { frame(of: focusedCell).fill() }

    private func moveFocus(to cell: Slot) {
        focusedCell = cell
        noteFocusRingMaskChanged()
    }

    private func frame(of cell: Slot) -> NSRect {
        let button = buttons[cell.index]
        return convert(button.bounds, from: button)
    }

    @objc private func toggle(_ sender: NSButton) {
        guard let i = buttons.firstIndex(where: { $0 === sender }) else { return }
        onToggle(Slot.all[i])
    }
}

final class SpreadCellButton: NSButton {
    var isStack = false

    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityValue() -> Any? { NSNumber(value: state == .on ? 1 : 0) }
    override func accessibilityValueDescription() -> String? { isStack ? SettingsCopy.Spread.stackCell : nil }
}

/// While it records, the live hotkey is released (`onRecordingStart`), so pressing the
/// current combination reaches the recorder instead of hiding every card. A local monitor sees
/// every key first, so ⌘, ⌘Q, ⌘W and Return never reach the menu, the window or the default button.
/// Its title is the glyphs, which the harness presses; VoiceOver hears "Shortcut" and the spelled-out
/// combination.
final class ShortcutField: NSButton {
    var shortcut: Shortcut = .standard { didSet { if monitor == nil { title = shortcut.display } } }
    var onReject: (String) -> Void = { _ in }
    var onRecordingStart: () -> Void = {}
    /// Runs with the pick while the old shortcut is still released, so `HotKey.choose` claims the
    /// new one before the old is taken back.
    var onRecordingEnd: (Shortcut?) -> Void = { _ in }
    private var monitor: Any?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        controlSize = .large
        font = SettingsStyle.font(.label)
        target = self
        action = #selector(beginRecording)
        title = shortcut.display
        setAccessibilityLabel(SettingsSection.shortcut.title)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func accessibilityValue() -> Any? { monitor == nil ? shortcut.spoken : SettingsCopy.Shortcut.prompt }

    @objc private func beginRecording() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDown:
                finish(nil)
                return event
            case .flagsChanged:
                let held = Shortcut.describe(event)
                title = held.isEmpty ? SettingsCopy.Shortcut.prompt : held + "…"
                return event
            default:
                let bare = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
                if bare, event.charactersIgnoringModifiers == "\u{1B}" {
                    finish(nil)
                } else if let picked = Shortcut(event: event) {
                    finish(picked)
                } else if !event.isARepeat {
                    onReject(Shortcut.refusal(of: event))
                }
                return nil
            }
        }
        title = SettingsCopy.Shortcut.prompt
        onRecordingStart()
    }

    func cancelRecording() {
        if monitor != nil { finish(nil) }
    }

    private func finish(_ picked: Shortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        title = shortcut.display
        onRecordingEnd(picked)
    }
}

/// The Privacy card (§3.11): a headline, then each term on its own line over its text.
final class PrivacyCardView: NSView {
    private static let inner = SettingsStyle.contentWidth - 2 * SettingsStyle.s5
    private let headline = SettingsControl.text("", as: .display, width: inner)
    private let list = NSStackView()
    private var items: [(term: SettingsText, text: SettingsText)] = []

    init() {
        super.init(frame: .zero)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = SettingsStyle.s3
        let column = NSStackView(views: [headline, list])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = SettingsStyle.s4
        column.edgeInsets = NSEdgeInsets(top: SettingsStyle.s5, left: SettingsStyle.s5, bottom: SettingsStyle.s5, right: SettingsStyle.s5)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: SettingsStyle.contentWidth),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternarySystemFill.setFill()
        bounds.fill()
    }

    func show(_ card: PrivacyCard) {
        headline.stringValue = card.headline
        while items.count < card.items.count {
            let item = (term: SettingsControl.text("", as: .term, width: Self.inner),
                        text: SettingsControl.text("", as: .body, width: Self.inner))
            let pair = NSStackView(views: [item.term, item.text])
            pair.orientation = .vertical
            pair.alignment = .leading
            pair.spacing = 0
            list.addArrangedSubview(pair)
            items.append(item)
        }
        for (shown, item) in zip(items, card.items) {
            shown.term.stringValue = item.term
            shown.text.stringValue = item.text
        }
    }
}
