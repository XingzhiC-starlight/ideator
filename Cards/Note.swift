import CryptoKit
import Foundation

// A card's content in domain form, its Markdown file format, and the typing rules for lists.
// Markdown is parsed here, at the file boundary; the editor's NSAttributedString form is
// converted in CardEditor.swift, at the editor boundary, and the clipboard's forms in
// Clipboard.swift, which reads and writes Markdown only through this file.

/// A card's content: the header plus body lines.
struct Note: Equatable {
    /// The first paragraph. Always shown as the bold H1 header and stored as `# header`;
    /// it never carries inline styling or a list kind ("regardless of formatting").
    var header: String
    /// Tidy by construction: every way a note comes to exist (a file, the editor, a paste, a test)
    /// ends in `init`, which applies `tidyLevels`.
    private(set) var body: [Line]

    init(header: String, body: [Line]) {
        self.header = header
        self.body = Note.tidied(body)
    }

    static let blank = Note(header: "", body: [])

    static func tidied(_ lines: [Line]) -> [Line] {
        zip(lines, tidyLevels(lines.map(\.shape))).map { $0.with(shape: $1) }
    }
}

/// How deep a list item sits. Exactly three values exist; `init?` refuses any other (Tab uses
/// that as "would pass level 3") and `init(clamping:)` repairs one (files, pastes, attributes).
struct Level: Comparable, Hashable {
    static let count = 3
    let rawValue: Int

    private init(valid rawValue: Int) { self.rawValue = rawValue }
    static let top = Level(valid: 0)

    init?(_ rawValue: Int) {
        guard (0..<Level.count).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init(clamping n: Int) { rawValue = min(max(n, 0), Level.count - 1) }

    var deeper: Level? { Level(rawValue + 1) }
    var shallower: Level? { Level(rawValue - 1) }

    static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
}

/// A line's place in the outline, without its text. A plain line is always at the top: its
/// initializer drops any other level, so kind and level can't disagree.
struct LineShape: Hashable {
    let kind: LineKind
    let level: Level

    init(kind: LineKind, level: Level = .top) {
        self.kind = kind
        self.level = kind.isList ? level : .top
    }

    static let plain = LineShape(kind: .text)

    func with(kind: LineKind) -> LineShape { LineShape(kind: kind, level: level) }
    func with(level: Level) -> LineShape { LineShape(kind: kind, level: level) }
}

struct Line: Equatable {
    let shape: LineShape
    var kind: LineKind { shape.kind }
    var level: Level { shape.level }
    /// Normalized on construction: no empty runs, no two neighbouring runs with the same style,
    /// and spaces at the edges of a styled run are plain (Markdown can't style them).
    /// Normalization is what makes `Note(markdown: note.markdown) == note` hold.
    private(set) var runs: [Run]

    init(kind: LineKind = .text, level: Level = .top, runs: [Run]) {
        self.init(shape: LineShape(kind: kind, level: level), runs: runs)
    }

    init(shape: LineShape, runs: [Run]) {
        self.shape = shape
        var pieces: [Run] = []
        for run in runs {
            guard !run.style.isEmpty else {
                pieces.append(run)
                continue
            }
            let leading = run.text.prefix(while: \.isWhitespace)
            let trailing = run.text.dropFirst(leading.count).reversed().prefix(while: \.isWhitespace)
            pieces.append(Run(text: String(leading)))
            pieces.append(Run(text: String(run.text.dropFirst(leading.count).dropLast(trailing.count)), style: run.style))
            pieces.append(Run(text: String(trailing.reversed())))
        }
        var merged: [Run] = []
        for run in pieces where !run.text.isEmpty {
            if let last = merged.last, last.style == run.style {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        self.runs = merged
    }

    func with(shape: LineShape) -> Line { Line(shape: shape, runs: runs) }

    var text: String { runs.map(\.text).joined() }
    var isBlank: Bool { text.allSatisfy(\.isWhitespace) }
}

enum LineKind: Hashable {
    case text, bullet, numbered
    case todo(done: Bool)

    var isList: Bool { self != .text }

    /// Bullet, numbered and checkbox, ignoring whether a checkbox is ticked.
    func sameList(as other: LineKind) -> Bool {
        switch (self, other) {
        case (.todo, .todo): true
        default: self == other
        }
    }
}

struct Run: Equatable {
    var text: String
    var style: Style = []
}

struct Style: OptionSet, Hashable {
    let rawValue: Int
    static let bold = Style(rawValue: 1 << 0)
    static let italic = Style(rawValue: 1 << 1)
}

/// SHA-256 of some text, hex. Stable across launches (unlike `Hasher`), so the sidecar can say
/// which version of a note, and which prompt, a cached summary came from.
struct Digest: RawRepresentable, Hashable, Codable {
    let rawValue: String
}

extension Digest {
    init(of text: String) {
        let hash = SHA256.hash(data: Data(text.utf8))
        self.init(rawValue: hash.map { String(format: "%02x", $0) }.joined())
    }
}

extension Note {
    /// What lists and stack rows show for this card.
    var title: String {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var digest: Digest { Digest(of: markdown) }

    /// Summaries exist only for bodies with at least two non-blank lines (spec: "no summary for
    /// empty or one-line bodies").
    var wantsSummary: Bool { body.filter { !$0.isBlank }.count >= 2 }

    /// The single non-blank body line, shown instead of a summary when `wantsSummary` is false.
    var shortBody: String { body.first { !$0.isBlank }?.text ?? "" }

    /// Header and body as plain text, for the summary prompt. Each level is 2 spaces of indent.
    var plainText: String {
        ([header] + body.map { line in
            let item = switch line.kind {
            case .text: line.text
            case .bullet, .numbered: "- " + line.text
            case .todo(let done): (done ? "[x] " : "[ ] ") + line.text
            }
            return String(repeating: "  ", count: line.level.rawValue) + item
        }).joined(separator: "\n")
    }

    /// Reads a card file. Never fails: anything outside the supported subset stays literal text.
    ///
    /// - Line 0 is the header; leading `#`s and one space are stripped.
    /// - One blank line right after the header is the separator `markdown` writes; it is skipped.
    /// - Every other line is one body line, read by `bodyLines`.
    init(markdown: String) {
        // `isNewline` also splits "\r\n", which Swift treats as one character.
        var lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.count > 1, lines.last == "" { lines.removeLast() }   // the file's final newline

        var headerLine = Substring(lines.first ?? "")
        if headerLine.hasPrefix("#") {
            headerLine = headerLine.drop { $0 == "#" }
            if headerLine.hasPrefix(" ") { headerLine = headerLine.dropFirst() }
        }
        var rest = lines.dropFirst()
        if rest.first == "" { rest = rest.dropFirst() }
        self.init(header: Note.parseInline(headerLine).map(\.text).joined(), body: Note.bodyLines(Array(rest)))
    }

    /// Writes a card file: `# header`, a blank line, then one Markdown line per body line.
    /// Inverse of `init(markdown:)` for every note.
    var markdown: String {
        var out = ["# " + Note.escape(header)]
        if !body.isEmpty { out.append("") }
        out += Note.markdownLines(body)
        return out.joined(separator: "\n") + "\n"
    }

    /// Markdown body lines to `Line`s, the one reader for files and pasted text.
    ///
    /// - `- [ ] x` / `- [x] x` → todo, `- x` or `* x` → bullet, `12. x` → numbered, else text;
    ///   a marker may follow spaces or tabs (a tab counts as 4 columns).
    /// - A list line indented further than the open list item above it is that item's child,
    ///   one at the same indent is its sibling. The first item of a run (after a plain line or at
    ///   the start) is at the top whatever its indent. Past the third level clamps.
    /// - A plain line keeps its leading spaces and ends the run. A `\` before a number marker
    ///   (`\1. x`) is `escapeLineStart`'s and goes, though CommonMark keeps a backslash before a digit.
    /// - Inline: `***x***` bold+italic, `**x**` bold, `*x*` italic; a `\` makes the punctuation
    ///   after it literal (`parseInline`).
    static func bodyLines(_ lines: [String]) -> [Line] {
        var ancestors: [Int] = []   // indent columns of the open items, increasing
        return lines.map { raw in
            let (columns, rest) = indentation(of: Substring(raw))
            let (kind, content) = lineKind(of: rest)
            guard kind.isList else {
                ancestors = []
                let escapedNumber = rest.hasPrefix("\\") && lineKind(of: rest.dropFirst()).0 == .numbered
                return Line(runs: parseInline(escapedNumber ? raw.dropLast(rest.count) + rest.dropFirst() : raw[...]))
            }
            while let last = ancestors.last, last > columns { ancestors.removeLast() }
            if ancestors.last != columns { ancestors.append(columns) }
            return Line(kind: kind, level: Level(clamping: ancestors.count - 1), runs: parseInline(content))
        }
    }

    /// One Markdown line per body line: 4 spaces per level, then the marker. Numbers come from
    /// `listNumbers`, so the file and the screen can't disagree.
    static func markdownLines(_ body: [Line]) -> [String] {
        zip(body, listNumbers(body.map(\.shape))).map { line, number in
            let content = line.runs.map { Note.renderInline($0) }.joined()
            let indent = String(repeating: "    ", count: line.level.rawValue)
            switch line.kind {
            case .text:
                return Note.escapeLineStart(content)
            case .bullet:
                let readsAsCheckbox = Note.checkboxes.contains { content.hasPrefix($0.marker) }
                return indent + "- " + (readsAsCheckbox ? "\\" : "") + content
            case .numbered:
                return indent + "\(number ?? 1). " + content
            case .todo(let done):
                return indent + (done ? "- [x] " : "- [ ] ") + content
            }
        }
    }

    // MARK: Line prefixes

    private static let checkboxes: [(marker: String, done: Bool)] = [("[ ] ", false), ("[x] ", true), ("[X] ", true)]

    /// Leading spaces and tabs as columns (a tab counts 4), and what follows them.
    private static func indentation(of line: Substring) -> (columns: Int, rest: Substring) {
        let blanks = line.prefix { $0 == " " || $0 == "\t" }
        return (blanks.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }, line.dropFirst(blanks.count))
    }

    private static func lineKind(of line: Substring) -> (LineKind, Substring) {
        let todos = checkboxes.map { ("- " + $0.marker, LineKind.todo(done: $0.done)) }
        for (prefix, kind) in todos + [("- ", .bullet), ("* ", .bullet)] where line.hasPrefix(prefix) {
            return (kind, line.dropFirst(prefix.count))
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered, line.dropFirst(digits.count + 2))
        }
        return (.text, line)
    }

    /// A plain line whose text, after its own leading spaces, would read as a list marker, `#`
    /// or `>` gets a `\` there, so it reads back as plain text here and in other Markdown readers.
    static func escapeLineStart(_ content: String) -> String {
        let rest = indentation(of: Substring(content)).rest
        guard lineKind(of: rest).0 != .text || rest.hasPrefix("#") || rest.hasPrefix(">") else { return content }
        return String(content.dropLast(rest.count)) + "\\" + rest
    }

    // MARK: Inline

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "*", with: "\\*")
    }

    /// One run as Markdown. Spaces at the edges go outside the markers, where Markdown wants them.
    private static func renderInline(_ run: Run) -> String {
        let marker = switch (run.style.contains(.bold), run.style.contains(.italic)) {
        case (true, true): "***"
        case (true, false): "**"
        case (false, true): "*"
        case (false, false): ""
        }
        let text = escape(run.text)
        let leading = text.prefix(while: \.isWhitespace)
        guard !marker.isEmpty, leading.count < text.count else { return text }
        let trailing = text.reversed().prefix(while: \.isWhitespace)
        let core = text.dropFirst(leading.count).dropLast(trailing.count)
        return leading + marker + core + marker + String(trailing.reversed())
    }

    private static let asciiPunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    /// Scans one line as CommonMark reads it, for the part of Markdown cards use. A backslash
    /// escapes the ASCII punctuation after it and is a literal backslash anywhere else. A run of
    /// asterisks with no space before it closes the styles that are open; with no space after it,
    /// it then opens new ones, if enough such closing asterisks follow later on the line. Any
    /// asterisk left over is literal, so `rm *.txt *.log` and `2 * 3 * 4` read as they look.
    static func parseInline(_ text: Substring) -> [Run] {
        let chars = Array(text)
        var runs: [Run] = []
        var current = ""
        var style: Style = []
        var i = 0

        func flush() {
            if !current.isEmpty { runs.append(Run(text: current, style: style)) }
            current = ""
        }
        func isEscape(at j: Int) -> Bool {
            chars[j] == "\\" && j + 1 < chars.count && asciiPunctuation.contains(chars[j + 1])
        }
        func isSpace(at j: Int) -> Bool { !chars.indices.contains(j) || chars[j].isWhitespace }
        func closersAhead(from index: Int) -> Int {
            var count = 0
            var j = index
            while j < chars.count {
                if isEscape(at: j) { j += 2; continue }
                guard chars[j] == "*" else { j += 1; continue }
                let start = j
                while j < chars.count, chars[j] == "*" { j += 1 }
                if !isSpace(at: start - 1) { count += j - start }
            }
            return count
        }

        while i < chars.count {
            let c = chars[i]
            if isEscape(at: i) {
                current.append(chars[i + 1])
                i += 2
                continue
            }
            guard c == "*" else {
                current.append(c)
                i += 1
                continue
            }
            var n = 0
            while i + n < chars.count, chars[i + n] == "*" { n += 1 }
            let closes = !isSpace(at: i - 1)
            let ahead = isSpace(at: i + n) ? 0 : closersAhead(from: i + n)
            var next = style
            var left = n
            if closes, next.contains(.bold), left >= 2 { next.remove(.bold); left -= 2 }
            if closes, next.contains(.italic), left >= 1 { next.remove(.italic); left -= 1 }
            if !next.contains(.bold), left >= 2, ahead >= 2 { next.insert(.bold); left -= 2 }
            if !next.contains(.italic), left >= 1, ahead >= 1 { next.insert(.italic); left -= 1 }
            if next != style {
                flush()
                style = next
            }
            current += String(repeating: "*", count: left)
            i += n
        }
        flush()
        return Line(runs: runs).runs
    }
}

// MARK: - Levels

/// The whole nesting rule: takes the shapes lines ask for, returns the shapes they may have. No item
/// sits more than one level deeper than the item above it, an item first in the body or right after
/// a plain line is at the top, and nothing passes the deepest level. A child whose parent went away
/// moves up just enough. Idempotent, never deeper than asked, kinds untouched.
func tidyLevels(_ shapes: [LineShape]) -> [LineShape] {
    var cap = Level.top
    return shapes.map { shape in
        guard shape.kind.isList else {
            cap = .top
            return .plain
        }
        let level = min(shape.level, cap)
        cap = level.deeper ?? level
        return shape.with(level: level)
    }
}

/// Display numbers, one running count per level. A numbered item counts up at its level; any other
/// item ends its level's run; a parent restarts the counts below it, so a nested run starts at 1
/// and the parent's run resumes after its children; a plain line ends every run. The Markdown
/// writer and the editor's marker drawing both use this, so the file and the screen can't disagree.
func listNumbers(_ shapes: [LineShape]) -> [Int?] {
    var counts = [Int](repeating: 0, count: Level.count)
    return shapes.map { shape in
        guard shape.kind.isList else {
            counts = [Int](repeating: 0, count: Level.count)
            return nil
        }
        let level = shape.level.rawValue
        for deeper in (level + 1)..<Level.count { counts[deeper] = 0 }
        guard shape.kind == .numbered else {
            counts[level] = 0
            return nil
        }
        counts[level] += 1
        return counts[level]
    }
}

// MARK: - Typing

/// The list rules the editor applies while typing, as pure decisions over the body's shapes.
/// Each key asks one function and gets one `Outcome`; the editor only carries it out.
enum Typing {
    enum Outcome: Equatable {
        /// Do what the text view does for this key (type a tab, join lines on Backspace).
        case system
        /// Swallow the key: a refused Tab, or Shift-Tab where nothing can move.
        case nothing
        /// The body's shapes become exactly these (same count, already tidy). One undo step.
        case reshape([LineShape])
        /// Insert the line break, and give the line it creates this shape.
        case splitLine(LineShape)
    }

    /// Typing a space after one of these at the very start of a body line starts a list:
    /// `-` bullet, `1.` (any number) numbered, `[]` or `[ ]` checkbox.
    static func listKind(forPrefix prefix: String) -> LineKind? {
        switch prefix {
        case "-", "*": return .bullet
        case "[]", "[ ]": return .todo(done: false)
        default:
            let digits = prefix.dropLast()
            if prefix.hasSuffix("."), !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return .numbered
            }
            return nil
        }
    }

    /// Enter. `line` is the body line the caret is in, nil in the header. Continues a list at the
    /// same level (a new checkbox starts unticked); on an empty item it moves the item up a level,
    /// and a top-level one becomes plain text, as before.
    static func onReturn(_ body: [LineShape], at line: Int?, isEmpty: Bool) -> Outcome {
        guard let i = line, body[i].kind.isList else { return .splitLine(.plain) }
        if isEmpty { return onBacktab(body, touching: i..<(i + 1)) }
        if case .todo = body[i].kind { return .splitLine(body[i].with(kind: .todo(done: false))) }
        return .splitLine(body[i])
    }

    /// Backspace with the caret at the very start of a body line and no selection: an item moves
    /// up a level (a top-level one becomes plain); anything else joins lines as before.
    static func onBackspaceAtStart(_ body: [LineShape], at line: Int) -> Outcome {
        body[line].kind.isList ? onBacktab(body, touching: line..<(line + 1)) : .system
    }

    /// Tab. `lines` are the body lines the selection touches (empty in the header). Moves every
    /// touched item and the deeper lines after it one level down, or refuses the whole move when a
    /// line would pass the deepest level or the result would need tidying (no item above to sit
    /// under). With no item touched, or a caret on a list's first item, it types a tab character.
    /// A selection that touches an item never becomes a tab: on a first item it moves nothing.
    static func onTab(_ body: [LineShape], touching lines: Range<Int>, isCaret: Bool) -> Outcome {
        let items = lines.filter { body[$0].kind.isList }
        guard let first = items.first else { return .system }
        if isCaret, first == 0 || !body[first - 1].kind.isList { return .system }
        var proposed = body
        for i in block(rootedAt: items, in: body) {
            guard let deeper = body[i].level.deeper else { return .nothing }
            proposed[i] = body[i].with(level: deeper)
        }
        return tidyLevels(proposed) == proposed ? .reshape(proposed) : .nothing
    }

    /// Shift-Tab, and the move behind Enter on an empty item and Backspace at an item's start. The
    /// same block moves one level up; a top-level item becomes plain and its children rise with it.
    static func onBacktab(_ body: [LineShape], touching lines: Range<Int>) -> Outcome {
        let items = lines.filter { body[$0].kind.isList }
        guard !items.isEmpty else { return .nothing }
        var proposed = body
        for i in block(rootedAt: items, in: body) {
            proposed[i] = body[i].level.shallower.map { body[i].with(level: $0) } ?? .plain
        }
        return .reshape(tidyLevels(proposed))
    }

    /// The bar's list buttons: every touched line becomes `kind`, or plain if all already are.
    /// Only those lines change; a list item keeps its level and plain text becomes a top-level item.
    static func onToggleKind(_ kind: LineKind, body: [LineShape], touching lines: Range<Int>) -> Outcome {
        guard !lines.isEmpty else { return .nothing }
        let allAlready = lines.allSatisfy { body[$0].kind.sameList(as: kind) }
        var proposed = body
        for i in lines { proposed[i] = body[i].with(kind: allAlready ? .text : kind) }
        return .reshape(tidyLevels(proposed))
    }

    /// The touched items plus every deeper line after each.
    private static func block(rootedAt roots: [Int], in body: [LineShape]) -> Set<Int> {
        var moved: Set<Int> = []
        for root in roots {
            moved.insert(root)
            var j = root + 1
            while j < body.count, body[j].kind.isList, body[j].level > body[root].level {
                moved.insert(j)
                j += 1
            }
        }
        return moved
    }
}
