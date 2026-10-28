import Foundation

// Copy and paste formats. Copy turns the selected lines into the card file's Markdown and an HTML
// nested list; paste turns HTML or plain text back into lines and splices them into the note.
// Pure: strings in, strings out. Markdown is read and written only by Note.swift, and the
// pasteboard itself belongs to CardEditor.swift.

enum Clipboard {
    /// A place in the editor's text. Paragraph 0 is the header and paragraph n is body line n - 1;
    /// `offset` counts UTF-16 units into that paragraph, as the text view does.
    struct Position: Comparable {
        var paragraph: Int
        var offset: Int

        static func < (a: Position, b: Position) -> Bool { (a.paragraph, a.offset) < (b.paragraph, b.offset) }
    }

    struct Span: Equatable {
        var start: Position
        var end: Position
    }

    /// What Copy puts on the pasteboard.
    struct Copy: Equatable {
        var markdown: String
        /// Nil for a selection inside one line, which copies just its text.
        var html: String?
    }

    /// What a pasteboard offers, already decoded to strings.
    struct Offer: Equatable {
        var html: String?
        var text: String?
    }

    struct Pasted: Equatable {
        var note: Note
        /// Just after the pasted text.
        var caret: Position
    }

    // MARK: Copy

    /// A selection inside one line copies just its text. One crossing a line break copies every
    /// line it touches, whole and with its marker; a line it reaches only at offset 0 isn't
    /// touched. Levels count from the shallowest copied item, and a copied header is `# Title`.
    static func copy(_ note: Note, span: Span) -> Copy? {
        guard span.start < span.end else { return nil }
        let paragraphs = [Line(runs: [Run(text: note.header)])] + note.body
        let first = span.start.paragraph
        guard first != span.end.paragraph else {
            let text = paragraphs[first].text
            let units = text.utf16
            let from = units.index(units.startIndex, offsetBy: span.start.offset)
            let to = units.index(units.startIndex, offsetBy: span.end.offset)
            return Copy(markdown: String(text[from..<to]), html: nil)
        }
        let last = span.end.offset == 0 ? span.end.paragraph - 1 : span.end.paragraph
        let lines = fromTop((first...last).filter { $0 > 0 }.map { paragraphs[$0] })
        var markdown: [String] = []
        var html = "<meta charset=\"utf-8\">"
        if first == 0 {
            markdown.append(note.markdownHeader)
            html += "<h1>" + escapeHTML(note.header) + "</h1>"
        }
        return Copy(markdown: (markdown + Note.markdownLines(lines)).joined(separator: "\n"), html: html + htmlList(lines))
    }

    /// Real nested lists: a deeper item's list opens inside the `<li>` above it, which tidy
    /// guarantees exists.
    private static func htmlList(_ lines: [Line]) -> String {
        var out = ""
        var open: [String] = []   // list tags by level; the innermost <li> of each is still open
        func close(downTo depth: Int) {
            while open.count > depth { out += "</li></\(open.removeLast())>" }
        }
        for line in lines {
            guard line.kind.isList else {
                close(downTo: 0)
                out += "<p>" + inlineHTML(line) + "</p>"
                continue
            }
            let depth = line.level.rawValue
            let tag = line.kind == .numbered ? "ol" : "ul"
            close(downTo: depth + 1)
            if open.count == depth + 1 {
                if open[depth] == tag { out += "</li>" } else { close(downTo: depth) }
            }
            if open.count == depth {
                open.append(tag)
                out += "<\(tag)>"
            }
            out += "<li>"
            if case .todo(let done) = line.kind { out += "<input type=\"checkbox\" disabled\(done ? " checked" : "")> " }
            out += inlineHTML(line)
        }
        close(downTo: 0)
        return out
    }

    /// A line's runs with `<b>` and `<i>`. A space HTML would collapse or trim (at either end of
    /// the line, or after another space) is written `&nbsp;`, so indents and double spaces survive.
    private static func inlineHTML(_ line: Line) -> String {
        let chars = Array(line.text)
        var index = 0
        return line.runs.map { run in
            var text = ""
            for c in run.text {
                let kept = c == " " && (index == 0 || index == chars.count - 1 || chars[index - 1] == " ")
                text += kept ? "&nbsp;" : escapeHTML(String(c))
                index += 1
            }
            if run.style.contains(.italic) { text = "<i>\(text)</i>" }
            if run.style.contains(.bold) { text = "<b>\(text)</b>" }
            return text
        }.joined()
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Levels counted from the shallowest item of the run, then tidied.
    private static func fromTop(_ lines: [Line]) -> [Line] {
        let shallowest = lines.filter(\.kind.isList).map(\.level.rawValue).min() ?? 0
        return Note.tidied(lines.map { $0.with(shape: $0.shape.with(level: Level(clamping: $0.level.rawValue - shallowest))) })
    }

    // MARK: Read

    /// Bigger HTML is read as its plain text instead, so a huge web page can't stall a paste.
    private static let htmlLimit = 1_000_000

    /// The pasted run, or nil when the pasteboard holds nothing usable. HTML first when it holds
    /// a list item; otherwise the text, one line verbatim, several lines as Markdown that also
    /// accepts `•◦▪·‣` bullets and `1)` numbers; otherwise the HTML's text as plain lines.
    static func lines(from offer: Offer) -> [Line]? {
        let html = offer.html.flatMap { $0.utf8.count <= htmlLimit ? $0 : nil }
        if let html, html.range(of: "<li[\\s/>]", options: [.regularExpression, .caseInsensitive]) != nil {
            let lines = HTMLReader.lines(from: html)
            if !lines.isEmpty { return fromTop(lines) }
        }
        if let text = offer.text, !text.isEmpty { return fromTop(textLines(text)) }
        guard let html else { return nil }
        let lines = HTMLReader.lines(from: html)
        return lines.isEmpty ? nil : fromTop(lines)
    }

    private static func textLines(_ text: String) -> [Line] {
        var rows = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if rows.count > 1, rows.last == "" { rows.removeLast() }
        guard rows.count > 1 else { return [Line(runs: [Run(text: rows[0])])] }
        return Note.bodyLines(rows.map { fileGrammar($0) })
    }

    /// One pasted line in the card file's grammar, so Note's one reader can read it: other
    /// bullets and `1)` become `- ` and `1. `, a tab after a marker becomes a space, and a `#`
    /// heading's text becomes a plain line written the way the writer writes one, so it reads back
    /// as the heading showed it whatever it starts with (`\1. x`, `- x`).
    private static func fileGrammar(_ row: String) -> String {
        let indent = String(row.prefix { $0 == " " || $0 == "\t" })
        let rest = row.dropFirst(indent.count)
        let gap: (Character?) -> Bool = { $0 == " " || $0 == "\t" }
        if let mark = rest.first, "-*•◦▪·‣".contains(mark), gap(rest.dropFirst().first) {
            return indent + "- " + rest.dropFirst(2)
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, let mark = rest.dropFirst(digits.count).first, mark == "." || mark == ")",
           gap(rest.dropFirst(digits.count + 1).first) {
            return indent + digits + ". " + rest.dropFirst(digits.count + 2)
        }
        let hashes = rest.prefix { $0 == "#" }
        if (1...6).contains(hashes.count), gap(rest.dropFirst(hashes.count).first) {
            return Note.markdownLines([Line(runs: Note.parseInline(rest.dropFirst(hashes.count + 1)))])[0]
        }
        return indent + rest
    }

    // MARK: Paste

    /// Splices the pasted run into `note` in place of `span`.
    ///
    /// - One line is typed text: it joins the line in the caret's `typing` style and never starts
    ///   a list.
    /// - Several lines on an empty line: the first replaces it, kind and level. Inside text: the
    ///   first line's text joins the current line, which keeps its kind, and the text after the
    ///   caret follows the last pasted line. Later lines keep their kinds, shifted by the current
    ///   item's level. Into the header: the first line joins the header, the rest are body lines.
    /// - `Note.init` tidies: past the third level clamps, and lines after the paste that lost
    ///   their parent move up.
    static func paste(_ lines: [Line], into note: Note, replacing span: Span, typing: Style) -> Pasted {
        let paragraphs = [Line(runs: [Run(text: note.header)])] + note.body
        let (a, b) = (span.start.paragraph, span.end.paragraph)
        let head = paragraphs[a].split(atUTF16: span.start.offset).head
        let tail = paragraphs[b].split(atUTF16: span.end.offset).tail
        let current = paragraphs[a].shape
        var out = Array(paragraphs[..<a])
        let caret: Position
        if lines.count == 1 {
            let typed = Run(text: lines[0].text, style: a == 0 ? [] : typing)
            caret = Position(paragraph: a, offset: (head + [typed]).map(\.text).joined().utf16.count)
            out.append(Line(shape: current, runs: head + [typed] + tail))
        } else {
            let shift = current.level.rawValue
            func shifted(_ line: Line) -> Line {
                Line(shape: line.shape.with(level: Level(clamping: line.level.rawValue + shift)), runs: line.runs)
            }
            let (first, last) = (lines[0], lines[lines.count - 1])
            if a == 0 || !(head.isEmpty && tail.isEmpty) {
                out.append(Line(shape: current, runs: head + first.runs))
            } else {
                out.append(shifted(first))
            }
            out += lines.dropFirst().dropLast().map(shifted)
            caret = Position(paragraph: out.count, offset: last.text.utf16.count)
            out.append(Line(shape: shifted(last).shape, runs: last.runs + tail))
        }
        out += paragraphs[(b + 1)...]
        return Pasted(note: Note(header: out[0].text, body: Array(out.dropFirst())), caret: caret)
    }
}

private extension Line {
    /// The runs before and after a UTF-16 offset into `text`; a run across it is cut in two.
    func split(atUTF16 offset: Int) -> (head: [Run], tail: [Run]) {
        var head: [Run] = [], tail: [Run] = []
        var seen = 0
        for run in runs {
            let length = run.text.utf16.count
            if seen + length <= offset {
                head.append(run)
            } else if seen >= offset {
                tail.append(run)
            } else {
                let cut = run.text.utf16.index(run.text.utf16.startIndex, offsetBy: offset - seen)
                head.append(Run(text: String(run.text[..<cut]), style: run.style))
                tail.append(Run(text: String(run.text[cut...]), style: run.style))
            }
            seen += length
        }
        return (head, tail)
    }
}

// MARK: - HTML

/// A tolerant reader for clipboard HTML, which is rarely well formed: unclosed `<li>`, `<br>`,
/// `&nbsp;`, wrapper tags. It never throws and keeps only what a card can hold: list items with
/// their nesting, kind and checkbox, bold and italic. Headings, paragraphs, table cells and
/// `<pre>` lines become plain lines; links and code keep their text; images are dropped.
private enum HTMLReader {
    enum Token: Equatable {
        case start(String, [String: String])
        case end(String)
        case text(String)
    }

    static func lines(from html: String) -> [Line] {
        var builder = Builder()
        for token in tokens(html) { builder.take(token) }
        return builder.finish()
    }

    static func tokens(_ html: String) -> [Token] {
        let chars = Array(html)
        var tokens: [Token] = []
        var text = ""
        var i = 0
        func flushText() {
            if !text.isEmpty { tokens.append(.text(decode(text))) }
            text = ""
        }
        func at(_ index: Int, _ literal: String) -> Bool {
            var j = index
            for c in literal {
                guard j < chars.count, chars[j] == c else { return false }
                j += 1
            }
            return true
        }
        while i < chars.count {
            guard chars[i] == "<", i + 1 < chars.count else {
                text.append(chars[i])
                i += 1
                continue
            }
            if at(i, "<!--") {
                flushText()
                var j = i + 4
                while j < chars.count, !at(j, "-->") { j += 1 }
                i = min(j + 3, chars.count)
                continue
            }
            if chars[i + 1] == "!" || chars[i + 1] == "?" {
                flushText()
                while i < chars.count, chars[i] != ">" { i += 1 }
                i += 1
                continue
            }
            let closing = chars[i + 1] == "/"
            let nameStart = closing ? i + 2 : i + 1
            guard nameStart < chars.count, chars[nameStart].isLetter else {
                text.append(chars[i])
                i += 1
                continue
            }
            flushText()
            var j = nameStart
            while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "-" || chars[j] == ":" { j += 1 }
            let name = String(chars[nameStart..<j]).lowercased()
            var attributes: [String: String] = [:]
            while j < chars.count, chars[j] != ">" {
                if chars[j].isWhitespace || chars[j] == "/" {
                    j += 1
                    continue
                }
                let keyStart = j
                while j < chars.count, !chars[j].isWhitespace, !"=>/".contains(chars[j]) { j += 1 }
                let key = String(chars[keyStart..<j]).lowercased()
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                var value = ""
                if j < chars.count, chars[j] == "=" {
                    j += 1
                    while j < chars.count, chars[j].isWhitespace { j += 1 }
                    if j < chars.count, chars[j] == "\"" || chars[j] == "'" {
                        let quote = chars[j]
                        let valueStart = j + 1
                        j = valueStart
                        while j < chars.count, chars[j] != quote { j += 1 }
                        value = String(chars[valueStart..<j])
                        j = min(j + 1, chars.count)
                    } else {
                        let valueStart = j
                        while j < chars.count, !chars[j].isWhitespace, chars[j] != ">" { j += 1 }
                        value = String(chars[valueStart..<j])
                    }
                }
                if !key.isEmpty { attributes[key] = decode(value) }
            }
            i = min(j + 1, chars.count)
            tokens.append(closing ? .end(name) : .start(name, attributes))
        }
        flushText()
        return tokens
    }

    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}", "bull": "•", "middot": "·",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = text[...]
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            guard let semi = rest.prefix(12).firstIndex(of: ";") else {
                out.append(rest.removeFirst())
                continue
            }
            let name = rest[rest.index(after: amp)..<semi]
            let number = name.hasPrefix("#x") || name.hasPrefix("#X") ? UInt32(name.dropFirst(2), radix: 16)
                : name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil
            if let value = entities[name.lowercased()] {
                out += value
            } else if let number, let scalar = Unicode.Scalar(number) {
                out.unicodeScalars.append(scalar)
            } else {
                out += rest[...semi]
            }
            rest = rest[rest.index(after: semi)...]
        }
        return out + rest
    }

    /// Builds lines from tokens, with the open lists, list items and inline styles as stacks.
    private struct Builder {
        struct Item {
            var shape: LineShape
            /// How many lists were open around it: a new `<li>` closes open items at its depth or deeper.
            var depth: Int
            var emitted = false
            var holdsList = false
        }

        static let skipped: Set<String> = ["head", "script", "style", "title", "template"]
        static let blocks: Set<String> = [
            "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "table", "tr", "td", "th", "thead",
            "tbody", "tfoot", "section", "article", "header", "footer", "hr", "figure", "figcaption", "caption",
            "dl", "dt", "dd", "form", "details", "summary", "aside", "nav", "main", "address",
        ]
        static let inline: Set<String> = ["b", "strong", "i", "em", "span", "font", "a", "code", "u", "mark", "small", "s", "sub", "sup"]

        var lines: [Line] = []
        var lists: [LineKind] = []
        var items: [Item] = []
        var styles: [(tag: String, style: Style)] = []
        var runs: [Run] = []
        var skipping = 0
        var preformatted = 0

        var hasContent: Bool { runs.contains { !$0.text.allSatisfy(\.isWhitespace) } }

        mutating func take(_ token: Token) {
            switch token {
            case .text(let text):
                guard skipping == 0 else { return }
                if preformatted > 0 {
                    for (n, row) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                        if n > 0 { flush() }
                        if !row.isEmpty { runs.append(Run(text: String(row), style: currentStyle)) }
                    }
                } else {
                    add(text)
                }
            case .start(let tag, let attributes):
                if tag == "body" { skipping = 0 }
                if Self.skipped.contains(tag) { skipping += 1 }
                guard skipping == 0 else { return }
                switch tag {
                case "ul", "ol":
                    flush()
                    if let top = items.indices.last, items[top].depth == lists.count { items[top].holdsList = true }
                    lists.append(tag == "ol" ? .numbered : .bullet)
                case "li":
                    flush()
                    while let top = items.last, top.depth >= lists.count { closeItem() }
                    items.append(Item(shape: LineShape(kind: lists.last ?? .bullet, level: Level(clamping: lists.count - 1)),
                                      depth: lists.count))
                case "input":
                    if attributes["type"]?.lowercased() == "checkbox", let top = items.indices.last, !items[top].emitted, !hasContent {
                        items[top].shape = items[top].shape.with(kind: .todo(done: attributes["checked"] != nil))
                    }
                case "pre":
                    flush()
                    preformatted += 1
                case "br":
                    flush()
                case _ where Self.inline.contains(tag):
                    styles.append((tag, Self.style(of: tag, css: attributes["style"])))
                case _ where Self.blocks.contains(tag):
                    flush()
                default:
                    break
                }
            case .end(let tag):
                if Self.skipped.contains(tag) {
                    skipping = max(0, skipping - 1)
                    return
                }
                guard skipping == 0 else { return }
                switch tag {
                case "ul", "ol":
                    flush()
                    guard !lists.isEmpty else { return }
                    while let top = items.last, top.depth >= lists.count { closeItem() }
                    lists.removeLast()
                case "li":
                    closeItem()
                case "pre":
                    flush()
                    preformatted = max(0, preformatted - 1)
                case _ where Self.inline.contains(tag):
                    if let index = styles.lastIndex(where: { $0.tag == tag }) { styles.remove(at: index) }
                case _ where Self.blocks.contains(tag):
                    flush()
                default:
                    break
                }
            }
        }

        mutating func finish() -> [Line] {
            flush()
            while !items.isEmpty { closeItem() }
            return lines
        }

        private var currentStyle: Style { styles.reduce([]) { $0.union($1.style) } }

        /// Whitespace collapses as HTML shows it, except a no-break space; a line never starts with
        /// a collapsible space. Unicode's own line breaks (U+2028, U+2029, U+0085) are not HTML
        /// whitespace, but they collapse too: the editor would split a paragraph on them.
        private mutating func add(_ text: String) {
            var collapsed = ""
            var afterSpace = runs.last.map { $0.text.last == " " } ?? true
            for c in text {
                if c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\r\n" || c == "\u{C}"
                    || c == "\u{2028}" || c == "\u{2029}" || c == "\u{85}" {
                    if !afterSpace { collapsed.append(" ") }
                    afterSpace = true
                } else {
                    collapsed.append(c)
                    afterSpace = false
                }
            }
            if !collapsed.isEmpty { runs.append(Run(text: collapsed, style: currentStyle)) }
        }

        /// Ends the line being built: the open item's text if it has none yet, else a plain line.
        private mutating func flush() {
            defer { runs = [] }
            guard hasContent else { return }
            if let first = runs.first { runs[0].text = String(first.text.drop { $0 == " " }) }
            if let last = runs.last { runs[runs.count - 1].text = String(last.text.reversed().drop { $0 == " " }.reversed()) }
            for i in runs.indices { runs[i].text = runs[i].text.replacingOccurrences(of: "\u{A0}", with: " ") }
            if let top = items.indices.last, !items[top].emitted {
                items[top].emitted = true
                lines.append(Line(shape: items[top].shape, runs: runs))
            } else {
                lines.append(Line(runs: runs))
            }
        }

        /// An item that never got text and holds no list (`<li></li>`) is an empty item; a wrapper
        /// item around a nested list adds nothing.
        private mutating func closeItem() {
            flush()
            guard let item = items.popLast(), !item.emitted, !item.holdsList else { return }
            lines.append(Line(shape: item.shape, runs: []))
        }

        /// Google Docs wraps a whole copy in `<b style="font-weight:normal">`, so a tag's own
        /// style attribute wins over the tag.
        private static func style(of tag: String, css: String?) -> Style {
            var style: Style = switch tag {
            case "b", "strong": .bold
            case "i", "em": .italic
            default: []
            }
            for declaration in (css ?? "").lowercased().split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "font-weight":
                    if ["bold", "bolder", "600", "700", "800", "900"].contains(parts[1]) { style.insert(.bold) } else { style.remove(.bold) }
                case "font-style":
                    if ["italic", "oblique"].contains(parts[1]) { style.insert(.italic) } else { style.remove(.italic) }
                default:
                    break
                }
            }
            return style
        }
    }
}
