import AppKit

// The card editor: one NSTextView (TextKit 1) whose first paragraph is the header.
//
// Representation. The text storage holds exactly the note's text: the header paragraph, then one
// paragraph per body line, separated by "\n". List markers are not characters. A body
// paragraph's shape (kind and level) is the `.cardLine` attribute over its whole range, and
// `CardTextView` draws "•", "1." or a checkbox in the paragraph's indent. So the user can never
// half-delete a marker, numbering can't go stale, and `Note(attributedText:)` is a plain walk over
// paragraphs. Inline bold/italic is the `.cardStyle` attribute, not the font: text joined into the
// header takes the header's font, and undo must still find its style. Fonts and indents are
// re-derived from `.cardLine` and `.cardStyle` after every change; `.cardLine` changes only
// through `applyShapes`, which registers undo.
//
// An empty last paragraph has no characters to hold an attribute, so while the caret is in it,
// its shape lives in the typing attributes.

extension NSAttributedString.Key {
    /// Paragraph-level `LineShape.attributeValue` of a body paragraph. Absent means plain text.
    static let cardLine = NSAttributedString.Key("cards.line")
    /// A body character's `Style.rawValue`. Absent means plain.
    static let cardStyle = NSAttributedString.Key("cards.style")
}

extension Style {
    /// Anything but a known style reads as plain.
    init(attributeValue: Any?) {
        self = Style(rawValue: (attributeValue as? Int) ?? 0).intersection([.bold, .italic])
    }
}

extension LineShape {
    /// Plist-friendly value for `.cardLine`, so undo carries it: "text", "bullet", "numbered",
    /// "todo" or "done", with ":1" or ":2" below the top level.
    var attributeValue: String {
        let name = switch kind {
        case .text: "text"
        case .bullet: "bullet"
        case .numbered: "numbered"
        case .todo(let done): done ? "done" : "todo"
        }
        return level == .top ? name : "\(name):\(level.rawValue)"
    }

    /// Anything unknown reads as plain text, and a level out of range is clamped.
    init(attributeValue: Any?) {
        let parts = ((attributeValue as? String) ?? "").split(separator: ":", maxSplits: 1).map(String.init)
        let kind: LineKind = switch parts.first {
        case "bullet": .bullet
        case "numbered": .numbered
        case "todo": .todo(done: false)
        case "done": .todo(done: true)
        default: .text
        }
        self.init(kind: kind, level: Level(clamping: parts.count == 2 ? Int(parts[1]) ?? 0 : 0))
    }
}

/// Fonts and paragraph styles, in one place.
enum EditorStyle {
    static let header = NSFont.boldSystemFont(ofSize: 17)
    static let body = NSFont.systemFont(ofSize: 13)
    /// How much further each level indents; a list item's marker is drawn in its last 20 points.
    static let listIndent: CGFloat = 20
    /// Bullets by level.
    static let bullets = ["•", "◦", "▪"]

    static func font(for style: Style) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if style.contains(.bold) { traits.insert(.bold) }
        if style.contains(.italic) { traits.insert(.italic) }
        guard !traits.isEmpty else { return body }
        return NSFont(descriptor: body.fontDescriptor.withSymbolicTraits(traits), size: body.pointSize) ?? body
    }

    static let headerAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        return [.font: header, .foregroundColor: Palette.ink, .paragraphStyle: paragraph]
    }()

    /// The look of a body paragraph: font, color and indent, without its `.cardLine`.
    static func bodyLook(shape: LineShape, style: Style) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 3
        if shape.kind.isList {
            paragraph.firstLineHeadIndent = listIndent * CGFloat(shape.level.rawValue + 1)
            paragraph.headIndent = paragraph.firstLineHeadIndent
        }
        return [.font: font(for: style), .foregroundColor: Palette.ink, .paragraphStyle: paragraph]
    }

    static func bodyAttributes(shape: LineShape, style: Style) -> [NSAttributedString.Key: Any] {
        bodyLook(shape: shape, style: style).merging([.cardLine: shape.attributeValue, .cardStyle: style.rawValue]) { $1 }
    }
}

extension Note {
    /// The editor's text: header paragraph, then one paragraph per body line.
    var attributedText: NSAttributedString { attributedParagraphs(0..<(body.count + 1)) }

    /// Paragraphs `range` of the editor's text (0 is the header). Each but the note's last ends in
    /// a "\n" that carries its paragraph's attributes. Any other line break inside a run (a bare
    /// CR, U+2028, U+2029, U+0085, which a file edited elsewhere or an HTML paste can carry) shows
    /// as a space: the text view would split a paragraph on it that the note does not have, and
    /// then the two disagree on where paragraph N starts, which is how a copy or paste trapped.
    func attributedParagraphs(_ range: Range<Int>) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for i in range {
            let runs = i == 0 ? [Run(text: header)] : body[i - 1].runs
            let attributes = { (style: Style) in
                i == 0 ? EditorStyle.headerAttributes : EditorStyle.bodyAttributes(shape: body[i - 1].shape, style: style)
            }
            for run in runs where !run.text.isEmpty {
                text.append(NSAttributedString(string: Self.withoutLineBreaks(run.text), attributes: attributes(run.style)))
            }
            if i < body.count { text.append(NSAttributedString(string: "\n", attributes: attributes([]))) }
        }
        return text
    }

    /// Every character `NSString` ends a paragraph or line on, other than "\n", as a space.
    static func withoutLineBreaks(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch scalar {
            case "\r", "\u{2028}", "\u{2029}", "\u{85}": " "
            default: scalar
            }
        }))
    }

    /// Inverse of `attributedText`. Paragraph 0 → `header` (plain string, attributes ignored).
    /// Paragraph i > 0 → a line whose shape is the `.cardLine` at its start and whose runs follow
    /// `.cardStyle`. `trailingShape` is the shape of an empty last paragraph, which has no characters.
    init(attributedText text: NSAttributedString, trailingShape: LineShape = .plain) {
        let string = text.string as NSString
        var ranges: [NSRange] = []
        var start = 0
        while true {
            let newline = string.range(of: "\n", range: NSRange(location: start, length: string.length - start))
            guard newline.location != NSNotFound else {
                ranges.append(NSRange(location: start, length: string.length - start))
                break
            }
            ranges.append(NSRange(location: start, length: newline.location - start))
            start = newline.location + 1
        }
        let header = string.substring(with: ranges[0])
        let body = ranges.dropFirst().map { range -> Line in
            let shape = range.location < string.length
                ? LineShape(attributeValue: text.attribute(.cardLine, at: range.location, effectiveRange: nil))
                : trailingShape
            var runs: [Run] = []
            if range.length > 0 {
                text.enumerateAttribute(.cardStyle, in: range) { value, sub, _ in
                    runs.append(Run(text: string.substring(with: sub), style: Style(attributeValue: value)))
                }
            }
            return Line(shape: shape, runs: runs)
        }
        self.init(header: header, body: body)
    }

    /// The paragraphs (0 is the header) that differ between two notes, as ranges into each; either
    /// may be empty. The common prefix and suffix are left out, except that the prefix never takes
    /// either note's last paragraph: that one has no "\n", so a line added after it changes it.
    static func changedParagraphs(from old: Note, to new: Note) -> (old: Range<Int>, new: Range<Int>) {
        func same(_ i: Int, _ j: Int) -> Bool {
            i == 0 || j == 0 ? i == j && old.header == new.header : old.body[i - 1] == new.body[j - 1]
        }
        let (m, n) = (old.body.count, new.body.count)
        var prefix = 0
        while prefix < min(m, n), same(prefix, prefix) { prefix += 1 }
        var suffix = 0
        while m - suffix >= prefix, n - suffix >= prefix, same(m - suffix, n - suffix) { suffix += 1 }
        return (prefix..<(m + 1 - suffix), prefix..<(n + 1 - suffix))
    }
}

final class CardTextView: NSTextView {
    /// Every content change, already as a `Note`.
    var onChange: (Note) -> Void = { _ in }
    /// A single press in the header area. Returns true when it became a window drag; false means
    /// "it was a click", and normal text handling proceeds (see `trackWindowDrag`).
    var onHeaderPress: (NSEvent) -> Bool = { _ in false }
    var onFocusChange: () -> Void = {}

    /// The note currently shown, derived from the storage after every change. `show` compares
    /// against it so a re-render caused by our own `onChange` never resets the caret.
    private(set) var note = Note.blank

    /// True while the after-edit tidy writes, so its own change doesn't tidy again.
    private var isTidying = false
    private var tidyCheckPending = false

    init() {
        // TextKit 1, built by hand: the marker drawing and the header hit area need
        // line-fragment geometry from an NSLayoutManager.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        allowsUndo = true
        isRichText = true
        importsGraphics = false
        usesFontPanel = false
        usesRuler = false
        drawsBackground = false
        insertionPointColor = Palette.ink
        selectedTextAttributes = [.backgroundColor: Palette.highlight]
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        textContainerInset = NSSize(width: 2, height: 2)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        typingAttributes = EditorStyle.headerAttributes
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Replaces the content unless it already shows `note` (keeps caret and undo while typing).
    func show(_ note: Note) {
        guard note != self.note, let storage = textStorage else { return }
        self.note = note
        storage.setAttributedString(note.attributedText)
        undoManager?.removeAllActions()
        setSelectedRange(NSRange(location: min(selectedRange().location, storage.length), length: 0))
        fixTypingAttributes()
        needsDisplay = true
    }

    /// Bottom of the header paragraph, in this (flipped) view's coordinates. Everything above it,
    /// including the top inset, is the header's press area.
    var headerBottom: CGFloat {
        guard let layoutManager, let textContainer else { return 0 }
        let string = self.string as NSString
        guard string.length > 0 else {
            let extra = layoutManager.extraLineFragmentRect
            return textContainerOrigin.y + (extra.isEmpty ? EditorStyle.header.boundingRectForFont.height : extra.maxY)
        }
        let header = string.paragraphRange(for: NSRange(location: 0, length: 0))
        let glyphs = layoutManager.glyphRange(forCharacterRange: header, actualCharacterRange: nil)
        return textContainerOrigin.y + layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).maxY
    }

    // MARK: Formatting commands

    /// ⌘B / ⌘I and the bar's first two buttons. Body only: in the header it does nothing.
    /// Empty selection → toggles the typing attributes; otherwise removes the trait if the whole
    /// selection has it, else adds it. Undoable.
    func toggle(_ style: Style) {
        guard let storage = textStorage else { return }
        let string = self.string as NSString
        let headerEnd = NSMaxRange(string.paragraphRange(for: NSRange(location: 0, length: 0)))
        let selection = selectedRange()
        if selection.length == 0 {
            guard currentParagraph().location > 0 else { return }
            var current = Style(attributeValue: typingAttributes[.cardStyle])
            current.formSymmetricDifference(style)
            typingAttributes[.cardStyle] = current.rawValue
            fixTypingAttributes()
            return
        }
        let body = NSIntersectionRange(selection, NSRange(location: headerEnd, length: string.length - headerEnd))
        guard body.length > 0 else { return }
        var everyRunHasIt = true
        storage.enumerateAttribute(.cardStyle, in: body) { value, _, _ in
            if !Style(attributeValue: value).isSuperset(of: style) { everyRunHasIt = false }
        }
        guard shouldChangeText(in: body, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.cardStyle, in: body) { value, sub, _ in
            var runStyle = Style(attributeValue: value)
            if everyRunHasIt { runStyle.subtract(style) } else { runStyle.formUnion(style) }
            storage.addAttribute(.cardStyle, value: runStyle.rawValue, range: sub)
        }
        storage.endEditing()
        didChangeText()
    }

    /// The bar's list buttons: every body line the selection touches becomes `kind`, or plain
    /// text if they all already are `kind`. Only those lines change. Undoable.
    func toggleLineKind(_ kind: LineKind) {
        perform(Typing.onToggleKind(kind, body: bodyShapes(), touching: touchedLines()), named: "List") {}
    }

    /// Targets of the hidden Format menu's ⌘B / ⌘I items (see `AppDelegate.installMainMenu`).
    @objc func cardsToggleBold(_ sender: Any?) { toggle(.bold) }
    @objc func cardsToggleItalic(_ sender: Any?) { toggle(.italic) }

    // MARK: Typing rules

    /// Tab nests the touched items, carrying their children; where nothing can nest it types a tab.
    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText() else { return super.insertTab(sender) }
        perform(Typing.onTab(bodyShapes(), touching: touchedLines()), named: "Indent") { super.insertTab(sender) }
    }

    /// Shift-Tab moves the touched items up a level. It never moves focus out of the card.
    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText() else { return super.insertBacktab(sender) }
        perform(Typing.onBacktab(bodyShapes(), touching: touchedLines()), named: "Outdent") {}
    }

    /// Enter continues a list at its level (a new checkbox starts unticked); on an empty item it
    /// moves the item up, and a top-level one ends the list.
    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), selectedRange().length == 0 else { return super.insertNewline(sender) }
        let outcome = Typing.onReturn(bodyShapes(), at: caretLine(), isEmpty: contentLength(of: currentParagraph()) == 0)
        perform(outcome, named: "Typing") { super.insertNewline(sender) }
    }

    /// Auto-start: typing a space right after "-", "1." or "[]" at the very start of a plain body
    /// paragraph removes those characters and makes the paragraph a list item. One undo step
    /// gives back the literal characters.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if text == " ", !hasMarkedText(), selectedRange().length == 0, startList() { return }
        super.insertText(Self.plainNewlines(text), replacementRange: replacementRange)
    }

    /// Backspace at the very start of a list item moves it up a level instead of joining lines.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, !hasMarkedText(), let line = caretLine(), selection.location == currentParagraph().location {
            return perform(Typing.onBackspaceAtStart(bodyShapes(), at: line), named: "Outdent") { super.deleteBackward(sender) }
        }
        super.deleteBackward(sender)
    }

    /// An edit that removes a line break starts its own undo step, so the tidy it may cause lands
    /// in that step instead of after typing that coalesced before it.
    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        if replacementString != nil, (string as NSString).substring(with: range).contains("\n") { breakUndoCoalescing() }
        return super.shouldChangeText(in: range, replacementString: replacementString)
    }

    // MARK: Copy and paste

    /// Copy, Cut and dragging text out: the card file's Markdown, plus an HTML list when the
    /// selection crosses a line break.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.html, .string] }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let copy = Clipboard.copy(note, span: span(of: selectedRange())) else { return false }
        let html = types.contains(.html) ? copy.html : nil
        pboard.declareTypes(html == nil ? [.string] : [.html, .string], owner: nil)
        if let html { pboard.setString(html, forType: .html) }
        return pboard.setString(copy.markdown, forType: .string)
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let copy = Clipboard.copy(note, span: span(of: selectedRange())) else { return false }
        switch type {
        case .html: return copy.html.map { pboard.setString($0, forType: .html) } ?? false
        case .string: return pboard.setString(copy.markdown, forType: .string)
        default: return false
        }
    }

    /// Paste and drop: an HTML list first, else the text as Markdown (see `Clipboard.lines`), as
    /// one undo step. Never goes through `insertText`, so a pasted space can't start a list.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.html, .string] }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard !hasMarkedText(), let lines = Clipboard.lines(from: pboard.clipboardOffer) else { return false }
        let pasted = Clipboard.paste(lines, into: note, replacing: span(of: selectedRange()),
                                     typing: Style(attributeValue: typingAttributes[.cardStyle]))
        undoStep("Paste") { replaceDocument(with: pasted) }
        return true
    }

    /// Replaces only the paragraphs that differ from `pasted.note`, as one registered change, and
    /// puts the caret after the pasted text.
    private func replaceDocument(with pasted: Clipboard.Pasted) {
        guard let storage = textStorage else { return }
        let region = Note.changedParagraphs(from: note, to: pasted.note)
        let starts = allParagraphs().map(\.location) + [storage.length]
        let range = NSRange(location: starts[region.old.lowerBound], length: starts[region.old.upperBound] - starts[region.old.lowerBound])
        let replacement = pasted.note.attributedParagraphs(region.new)
        guard shouldChangeText(in: range, replacementString: replacement.string) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        let paragraphs = allParagraphs()
        setSelectedRange(NSRange(location: paragraphs[pasted.caret.paragraph].location + pasted.caret.offset, length: 0))
        didChangeText()
        if let last = pasted.note.body.last, paragraphs.last?.length == 0, pasted.caret.paragraph == paragraphs.count - 1 {
            setTrailingShape(last.shape)
        }
    }

    /// A text range as clipboard positions: paragraph (0 is the header) and UTF-16 offset.
    private func span(of range: NSRange) -> Clipboard.Span {
        let starts = allParagraphs().map(\.location)
        func position(_ location: Int) -> Clipboard.Position {
            let paragraph = starts.lastIndex { $0 <= location } ?? 0
            return Clipboard.Position(paragraph: paragraph, offset: location - starts[paragraph])
        }
        return Clipboard.Span(start: position(range.location), end: position(NSMaxRange(range)))
    }

    // MARK: Change tracking

    /// After any change (typing, paste, undo): tidy the shapes, re-derive the look, publish.
    override func didChangeText() {
        super.didChangeText()
        guard !hasMarkedText() else { return }
        if !isTidying { tidyAfterChange() }
        restyle()
        fixTypingAttributes()
        publish()
    }

    /// Makes the shapes tidy and each paragraph's `.cardLine` uniform, registered in the undo
    /// group of the edit that broke them. Undo and redo bring back states that were already tidy,
    /// so they get only an unregistered check once they finish: registering mid-undo would put
    /// the tidy on the redo stack.
    private func tidyAfterChange() {
        if let undoManager, undoManager.isUndoing || undoManager.isRedoing {
            guard !tidyCheckPending else { return }
            tidyCheckPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                tidyCheckPending = false
                undoManager.disableUndoRegistration()
                tidyAfterChange()
                undoManager.enableUndoRegistration()
            }
            return
        }
        isTidying = true
        applyShapes(tidyLevels(bodyShapes()))
        isTidying = false
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting, !hasMarkedText() {
            fixTypingAttributes()
            needsDisplay = true   // the empty last line's marker follows the caret
        }
    }

    override func becomeFirstResponder() -> Bool {
        defer { onFocusChange() }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        defer { onFocusChange() }
        return super.resignFirstResponder()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let marker = checkbox(at: point), case .todo(let done) = marker.shape.kind {
            var shapes = bodyShapes()
            shapes[marker.line] = marker.shape.with(kind: .todo(done: !done))
            undoStep("Checkbox") { applyShapes(shapes) }
            return
        }
        if event.clickCount == 1, !event.modifierFlags.contains(.shift), point.y <= headerBottom,
           onHeaderPress(event) {
            return                                      // the press became a window drag
        }
        super.mouseDown(with: event)                    // a click: NSTextView places the caret
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let placeholder = NSAttributedString(string: "Title", attributes: [
                .font: EditorStyle.header, .foregroundColor: Palette.inkFaint,
            ])
            placeholder.draw(at: NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
                                         y: textContainerOrigin.y))
        }
        for marker in markers() {
            switch marker.shape.kind {
            case .todo(let done):
                let name = done ? "checkmark.square" : "square"
                guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) else { continue }
                image.isTemplate = true
                let tinted = image.tinted(Palette.inkSoft)
                tinted.draw(in: marker.box)
            default:
                let attributes: [NSAttributedString.Key: Any] = [.font: EditorStyle.body, .foregroundColor: Palette.inkSoft]
                let label = NSAttributedString(string: marker.label, attributes: attributes)
                let size = label.size()
                label.draw(at: NSPoint(x: marker.box.maxX - size.width, y: marker.baseline - EditorStyle.body.ascender))
            }
        }
    }

    private struct Marker {
        /// Index into the body.
        let line: Int
        let shape: LineShape
        let label: String
        /// Where the marker sits, in view coordinates: the box a checkbox fills, whose right edge
        /// a bullet or number aligns to.
        let box: NSRect
        let baseline: CGFloat
    }

    /// Every list paragraph's marker, with the same geometry for drawing and checkbox clicks.
    private func markers() -> [Marker] {
        guard let layoutManager, let textContainer else { return [] }
        let paragraphs = Array(allParagraphs().dropFirst())
        let shapes = paragraphs.map(shape(ofParagraph:))
        let numbers = listNumbers(shapes)
        let left = textContainerOrigin.x + textContainer.lineFragmentPadding
        var result: [Marker] = []
        for (line, paragraph) in paragraphs.enumerated() where shapes[line].kind.isList {
            let shape = shapes[line]
            let fragment: NSRect
            let baselineOffset: CGFloat
            if paragraph.location < (string as NSString).length {
                let glyph = layoutManager.glyphIndexForCharacter(at: paragraph.location)
                fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                baselineOffset = layoutManager.location(forGlyphAt: glyph).y
            } else {
                fragment = layoutManager.extraLineFragmentRect
                baselineOffset = layoutManager.defaultBaselineOffset(for: EditorStyle.body)
            }
            guard fragment.height > 0 else { continue }
            let baseline = textContainerOrigin.y + fragment.minY + baselineOffset
            let box = NSRect(x: left + 2 + EditorStyle.listIndent * CGFloat(shape.level.rawValue), y: baseline - 11, width: 13, height: 13)
            let label = switch shape.kind {
            case .bullet: EditorStyle.bullets[shape.level.rawValue]
            case .numbered: "\(numbers[line] ?? 1)."
            default: ""
            }
            result.append(Marker(line: line, shape: shape, label: label,
                                 box: shape.kind == .bullet ? box.offsetBy(dx: -3, dy: 0) : box, baseline: baseline))
        }
        return result
    }

    private func checkbox(at point: NSPoint) -> Marker? {
        markers().first { marker in
            if case .todo = marker.shape.kind { return marker.box.insetBy(dx: -4, dy: -3).contains(point) }
            return false
        }
    }

    // MARK: Paragraphs and shapes

    /// Every paragraph's full range (including its "\n"), header first. An empty last paragraph
    /// is included as a zero-length range at the end.
    private func allParagraphs() -> [NSRange] {
        let string = self.string as NSString
        var result: [NSRange] = []
        var location = 0
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            result.append(paragraph)
            location = NSMaxRange(paragraph)
        } while location < string.length
        if string.length > 0, string.hasSuffix("\n") {
            result.append(NSRange(location: string.length, length: 0))
        }
        return result
    }

    private func currentParagraph() -> NSRange {
        let string = self.string as NSString
        let caret = min(selectedRange().location, string.length)
        return string.paragraphRange(for: NSRange(location: caret, length: 0))
    }

    /// The body line the caret is in, nil in the header.
    private func caretLine() -> Int? {
        let paragraph = currentParagraph()
        guard paragraph.location > 0 else { return nil }
        return allParagraphs().firstIndex { $0.location == paragraph.location }.map { $0 - 1 }
    }

    /// The body lines the selection touches (for a caret, the one it is in); empty in the header.
    private func touchedLines() -> Range<Int> {
        let paragraphs = allParagraphs()
        let covered = (string as NSString).paragraphRange(for: selectedRange())
        let touched = paragraphs.indices.dropFirst().filter { i in
            paragraphs[i].length == 0 ? paragraphs[i].location == covered.location
                                      : NSIntersectionRange(paragraphs[i], covered).length > 0
        }
        guard let first = touched.first, let last = touched.last else { return 0..<0 }
        return (first - 1)..<last
    }

    private func contentLength(of paragraph: NSRange) -> Int {
        let string = self.string as NSString
        guard paragraph.length > 0 else { return 0 }
        return string.character(at: NSMaxRange(paragraph) - 1) == 10 ? paragraph.length - 1 : paragraph.length
    }

    /// The header (location 0) is plain. The empty last paragraph's shape is in the typing
    /// attributes while the caret is in it.
    private func shape(ofParagraph paragraph: NSRange) -> LineShape {
        guard paragraph.location > 0 else { return .plain }
        if paragraph.length > 0, let storage = textStorage {
            return LineShape(attributeValue: storage.attribute(.cardLine, at: paragraph.location, effectiveRange: nil))
        }
        return selectedRange().location == paragraph.location ? LineShape(attributeValue: typingAttributes[.cardLine]) : .plain
    }

    /// Every body paragraph's shape, the empty last one included.
    private func bodyShapes() -> [LineShape] { allParagraphs().dropFirst().map(shape(ofParagraph:)) }

    /// The one writer of `.cardLine`: body paragraph i gets `shapes[i]` on every character and the
    /// header none, as one registered change, so undo restores shapes together with the edit that
    /// set them. The empty last paragraph's shape goes to `setTrailingShape`.
    private func applyShapes(_ shapes: [LineShape]) {
        guard let storage = textStorage else { return }
        let paragraphs = allParagraphs()
        var writes: [(range: NSRange, shape: LineShape?)] = []
        for (i, paragraph) in paragraphs.enumerated() where paragraph.length > 0 {
            let wanted = i == 0 ? LineShape.plain : shapes[i - 1]
            var uniform = true
            storage.enumerateAttribute(.cardLine, in: paragraph) { value, _, stop in
                if LineShape(attributeValue: value) != wanted {
                    uniform = false
                    stop.pointee = true
                }
            }
            if !uniform { writes.append((paragraph, i == 0 ? nil : wanted)) }
        }
        if let first = writes.first, let last = writes.last,
           shouldChangeText(in: NSUnionRange(first.range, last.range), replacementString: nil) {
            storage.beginEditing()
            for write in writes {
                if let shape = write.shape {
                    storage.addAttribute(.cardLine, value: shape.attributeValue, range: write.range)
                } else {
                    storage.removeAttribute(.cardLine, range: write.range)
                }
            }
            storage.endEditing()
            didChangeText()
        }
        if let trailing = paragraphs.last, trailing.length == 0, trailing.location > 0,
           selectedRange().location == trailing.location, let wanted = shapes.last {
            setTrailingShape(wanted)
        }
    }

    /// The empty last paragraph's shape, kept in the typing attributes. No storage change exists
    /// for the text view to register, so this registers its own undo, which applies only while the
    /// caret is back in that paragraph.
    private func setTrailingShape(_ shape: LineShape) {
        let old = LineShape(attributeValue: typingAttributes[.cardLine])
        guard shape != old else { return }
        let location = (string as NSString).length
        undoManager?.registerUndo(withTarget: self) { view in
            if view.selectedRange() == NSRange(location: location, length: 0) { view.setTrailingShape(old) }
        }
        typingAttributes[.cardLine] = shape.attributeValue
        fixTypingAttributes()
        publish()
    }

    /// One user-visible step for undo, however many changes `work` registers, kept apart from
    /// typing before and after it.
    private func undoStep(_ name: String, _ work: () -> Void) {
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        work()
        undoManager?.setActionName(name)
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
    }

    /// Carries out a `Typing` decision; `system` is what the text view does for the key.
    private func perform(_ outcome: Typing.Outcome, named name: String, system: () -> Void) {
        switch outcome {
        case .system:
            system()
        case .nothing:
            break
        case .reshape(let shapes):
            undoStep(name) { applyShapes(shapes) }
        case .splitLine(let shape):
            // The new line inherits the current line's shape, so usually Enter is plain typing and
            // coalesces with the typing around it, as it did before levels.
            guard shape != (caretLine().map { bodyShapes()[$0] } ?? .plain) else { return system() }
            undoStep(name) {
                system()
                guard let line = caretLine() else { return }
                var shapes = bodyShapes()
                shapes[line] = shape
                applyShapes(shapes)
            }
        }
    }

    /// The space-after-prefix rule. Returns true when it started a list.
    private func startList() -> Bool {
        guard let storage = textStorage, let line = caretLine() else { return false }
        let paragraph = currentParagraph()
        guard shape(ofParagraph: paragraph) == .plain else { return false }
        let prefixRange = NSRange(location: paragraph.location, length: selectedRange().location - paragraph.location)
        guard let kind = Typing.listKind(forPrefix: (string as NSString).substring(with: prefixRange)) else { return false }
        undoStep("List") {
            guard shouldChangeText(in: prefixRange, replacementString: "") else { return }
            storage.replaceCharacters(in: prefixRange, with: "")
            setSelectedRange(NSRange(location: paragraph.location, length: 0))
            didChangeText()
            var shapes = bodyShapes()
            shapes[line] = LineShape(kind: kind)
            applyShapes(shapes)
        }
        return true
    }

    /// Paragraph 0 gets the header look and each body paragraph the look of its shape (the one at
    /// its start) with its own `.cardStyle`. It never writes `.cardLine` or `.cardStyle`, so it
    /// neither changes the note nor needs undo.
    private func restyle() {
        guard let storage = textStorage else { return }
        var looks: [(NSRange, [NSAttributedString.Key: Any])] = []
        for (index, paragraph) in allParagraphs().enumerated() where paragraph.length > 0 {
            let shape = LineShape(attributeValue: storage.attribute(.cardLine, at: paragraph.location, effectiveRange: nil))
            storage.enumerateAttributes(in: paragraph) { attributes, range, _ in
                var look = index == 0 ? EditorStyle.headerAttributes
                    : EditorStyle.bodyLook(shape: shape, style: Style(attributeValue: attributes[.cardStyle]))
                look[.cardLine] = attributes[.cardLine]
                look[.cardStyle] = attributes[.cardStyle]
                looks.append((range, look))
            }
        }
        storage.beginEditing()
        for (range, look) in looks { storage.setAttributes(look, range: range) }
        storage.endEditing()
    }

    /// Typing attributes follow the caret: header look in paragraph 0, otherwise the body look
    /// for the paragraph's shape, keeping the bold/italic the user has toggled.
    private func fixTypingAttributes() {
        let paragraph = currentParagraph()
        if paragraph.location == 0 {
            typingAttributes = EditorStyle.headerAttributes
            return
        }
        let style = Style(attributeValue: typingAttributes[.cardStyle])
        typingAttributes = EditorStyle.bodyAttributes(shape: shape(ofParagraph: paragraph), style: style)
    }

    private func publish() {
        let string = self.string as NSString
        let caretInTrailing = string.length > 0 && string.hasSuffix("\n") && selectedRange().location == string.length
        let trailing = caretInTrailing ? LineShape(attributeValue: typingAttributes[.cardLine]) : .plain
        let current = Note(attributedText: textStorage ?? NSTextStorage(), trailingShape: trailing)
        needsDisplay = true
        guard current != note else { return }
        note = current
        onChange(current)
    }

    /// Only "\n" separates paragraphs here; other line breaks in typed text become "\n".
    private static func plainNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }
}

private extension NSPasteboard {
    /// The HTML and text on offer, as strings. HTML arrives as bytes, nearly always UTF-8.
    var clipboardOffer: Clipboard.Offer {
        let html = data(forType: .html).map { data in
            data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
                ? String(data: data, encoding: .utf16) ?? "" : String(decoding: data, as: UTF8.self)
        }
        return Clipboard.Offer(html: html, text: string(forType: .string))
    }
}

private extension NSImage {
    /// A copy of a template image filled with `color`.
    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
