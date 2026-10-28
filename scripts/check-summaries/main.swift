import Foundation

// Sends sample cards through the app's own summary request and checks each summary against the
// rules in CARDS-SPEC.md § AI summaries that a program can check. scripts/check-summaries.sh
// compiles this with Cards/{Summarizer,Desk,Grid,Note}.swift, so the request it sends is the
// request the app sends. The rules a program cannot check (is the gist right, is it worth
// reading) are for the person reading the output.

struct Sample {
    let name: String
    let markdown: String
    var thin = false
}

let samples: [Sample] = [
    Sample(name: "English to-do list, 2 of 4 done", markdown: """
        # Tokyo trip

        - [x] book flights
        - [x] pack passport
        - [ ] reserve hotel
        - [ ] buy charger
        """),
    Sample(name: "English to-do list, all done", markdown: """
        # Move out

        - [x] return keys
        - [x] cancel internet
        - [x] forward mail
        """),
    Sample(name: "English thoughts", markdown: """
        # Drag lag

        The drag felt slow after the new build.
        Maybe the input focus is the cause, not the window code.
        Try measuring with the text field unfocused.
        """),
    Sample(name: "English meeting notes", markdown: """
        # Weekly sync

        Priya: launch moved to Thursday.
        Ahmed will send the budget draft by Friday.
        Open question: who owns the support rota?
        """),
    Sample(name: "English links", markdown: """
        # Reading list

        - https://example.com/swift-concurrency
        - https://example.com/appkit-tips
        - https://example.com/keychain-basics
        """),
    Sample(name: "English nested plan", markdown: """
        # Launch plan

        1. Finish the OpenAI key work
            - test with a real key
            - update the privacy page
        2. Build the 0.9 disk image
        3. Send it to three friends
        """),
    Sample(name: "English thin card", markdown: """
        # Dentist

        call tomorrow
        ask about the crown
        """, thin: true),
    Sample(name: "English thin card, a question", markdown: """
        # Idea

        what if cards could fade
        ?
        """, thin: true),
    Sample(name: "Chinese to-do list, 2 of 5 done", markdown: """
        # 东京之行

        - [x] 订机票
        - [x] 办签证
        - [ ] 订酒店
        - [ ] 买充电器
        - [ ] 换日元
        """),
    Sample(name: "Chinese thoughts", markdown: """
        # 拖动卡顿

        今天发现拖动窗口的时候很卡。
        可能是输入法的问题，而不是窗口本身。
        明天用关闭输入法的方式再测一次。
        """),
    Sample(name: "Chinese meeting notes", markdown: """
        # 周会

        小王：发布推迟到周四。
        阿明周五前发预算草稿。
        待定：谁负责客服排班？
        """),
    Sample(name: "Chinese thin card", markdown: """
        # 牙医

        明天打电话
        问问牙冠的事
        """, thin: true),
    Sample(name: "Chinese with English terms", markdown: """
        # API 测试

        今天测了 OpenAI 和 Anthropic 的 key。
        OpenAI 的返回比较慢，但是格式稳定。
        Anthropic 的 key 以 sk-ant- 开头。
        """),
    Sample(name: "Japanese plan", markdown: """
        # 来週の計画

        月曜日にデザインを確認する。
        火曜日までにビルドを送る。
        水曜日にフィードバックをまとめる。
        """),
]

enum Language: String {
    case english, chinese, japanese, korean

    init(of text: String) {
        var han = 0, kana = 0, hangul = 0, letters = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            switch scalar.value {
            case 0x3040...0x30FF: kana += 1
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: han += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF: hangul += 1
            default: break
            }
        }
        let share = { (count: Int) in letters == 0 ? 0 : Double(count) / Double(letters) }
        if kana > 0, share(kana + han) >= 0.3 {
            self = .japanese
        } else if share(hangul) >= 0.3 {
            self = .korean
        } else if share(han) >= 0.3 {
            self = .chinese
        } else {
            self = .english
        }
    }

    var isCJK: Bool { self != .english }
    var lengthLimit: Int { isCJK ? 60 : 120 }
}

struct Check {
    let rule: String
    let passed: Bool
    let detail: String
    var heuristic = false
}

func fold(_ text: String) -> String {
    String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

/// The parts of an item that a summary naming it would contain: its words of three letters or
/// more, or, for CJK, each pair of neighbouring characters.
func units(of item: String) -> Set<String> {
    if Language(of: item).isCJK {
        let characters = Array(fold(item))
        return Set(zip(characters, characters.dropFirst()).map { String([$0, $1]) })
    }
    return Set(item.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
}

func mentionsCount(_ n: Int, in summary: String) -> Bool {
    let words: [Int: [String]] = [1: ["one", "一"], 2: ["two", "二", "两"], 3: ["three", "三"], 4: ["four", "四"],
                                  5: ["five", "五"], 6: ["six", "六"], 7: ["seven", "七"], 8: ["eight", "八"],
                                  9: ["nine", "九"], 10: ["ten", "十"]]
    let lowered = summary.lowercased()
    return summary.range(of: "(?<![0-9])\(n)(?![0-9])", options: .regularExpression) != nil
        || (words[n] ?? []).contains { lowered.contains($0) }
}

func checks(for sample: Sample, note: Note, summary: String) -> [Check] {
    let cardText = note.plainText
    let cardLanguage = Language(of: cardText)
    var result: [Check] = []

    let lineBreaks = summary.unicodeScalars.filter { "\n\r\u{2028}\u{2029}\u{85}".unicodeScalars.contains($0) }.count
    result.append(Check(rule: "one paragraph, no line breaks", passed: lineBreaks == 0 && !summary.isEmpty,
                        detail: lineBreaks == 0 ? "" : "\(lineBreaks) line break(s)"))

    let limit = cardLanguage.lengthLimit
    let allowed = limit + limit / 10
    result.append(Check(rule: "length", passed: summary.count <= allowed,
                        detail: "\(summary.count) characters, the spec says about \(limit) for \(cardLanguage.isCJK ? "CJK" : "other") text (passes up to \(allowed))"))

    let summaryLanguage = Language(of: summary)
    result.append(Check(rule: "same language as the card", passed: summaryLanguage == cardLanguage,
                        detail: "card \(cardLanguage.rawValue), summary \(summaryLanguage.rawValue)"))

    let title = fold(note.header)
    let summaryKey = fold(summary)
    if title.count >= (cardLanguage.isCJK ? 3 : 5) {
        let restates = summaryKey == title || summaryKey.hasPrefix(title)
        result.append(Check(rule: "does not restate the title", passed: !restates,
                            detail: restates ? "starts with the title “\(note.header)”" : ""))
    }

    let open = note.body.compactMap { line -> String? in
        if case .todo(done: false) = line.kind { return line.text } else { return nil }
    }
    let done = note.body.compactMap { line -> String? in
        if case .todo(done: true) = line.kind { return line.text } else { return nil }
    }
    if !open.isEmpty {
        let missing = open.filter { item in !units(of: item).contains { fold(summary).contains($0) || summary.lowercased().contains($0) } }
        result.append(Check(rule: "to-do list names every unchecked item", passed: missing.isEmpty,
                            detail: missing.isEmpty ? "" : "missing: \(missing.joined(separator: ", "))"))
        let openText = open.map { fold($0) }.joined(separator: " ")
        let named = done.filter { item in
            units(of: item).filter { !openText.contains($0) && !open.joined(separator: " ").lowercased().contains($0) }
                .contains { fold(summary).contains($0) || summary.lowercased().contains($0) }
        }
        result.append(Check(rule: "to-do list names no checked item", passed: named.isEmpty,
                            detail: named.isEmpty ? "" : "names: \(named.joined(separator: ", "))"))
        if !done.isEmpty {
            result.append(Check(rule: "to-do list gives the count done (\(done.count))", passed: mentionsCount(done.count, in: summary),
                                detail: ""))
        }
    } else if !done.isEmpty {
        let words = ["all", "every", "complete", "done", "finished", "全部", "都", "完成", "全"]
        let lowered = summary.lowercased()
        result.append(Check(rule: "all-done to-do list says all done", passed: words.contains { lowered.contains($0) },
                            detail: ""))
    }

    let preambles = ["here", "sure", "certainly", "of course", "okay", "summary:", "summary of", "以下", "好的", "当然", "摘要", "总结"]
    let lowered = summary.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let preamble = preambles.first { lowered.hasPrefix($0) }
    result.append(Check(rule: "no preamble", passed: preamble == nil, detail: preamble.map { "starts with “\($0)”" } ?? ""))

    let quotes = "\"“”‘’「」『』«»".filter { $0 != "’" && $0 != "‘" }
    let quoted = summary.contains { quotes.contains($0) }
    result.append(Check(rule: "no quotation marks", passed: !quoted, detail: ""))

    let markdown = ["**", "__", "`", "](", "\n#"].contains { summary.contains($0) }
        || ["# ", "- ", "* ", "> "].contains { summary.hasPrefix($0) }
    result.append(Check(rule: "no Markdown", passed: !markdown, detail: ""))

    let aboutTitleOrPrompt = ["title", "prompt", "instruction", "标题", "提示词", "指令", "タイトル"].first { lowered.contains($0) }
    result.append(Check(rule: "does not comment on the title or the prompt", passed: aboutTitleOrPrompt == nil,
                        detail: aboutTitleOrPrompt.map { "mentions “\($0)”" } ?? "", heuristic: true))

    let source = cardText.lowercased()
    let digitGroups = { (text: String) in text.split { !($0.isASCII && $0.isNumber) }.map(String.init) }
    let allowedDigits = Set(digitGroups(source)).union((open + done).isEmpty ? [] : (0...(open.count + done.count)).map(String.init))
    let invented = digitGroups(summary).filter { !allowedDigits.contains($0) }
    var names: [String] = []
    if !summaryLanguage.isCJK {
        var afterSentence = true
        for raw in summary.split(separator: " ") {
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            if !afterSentence, word.first?.isUppercase == true, !source.contains(word.lowercased()) { names.append(word) }
            afterSentence = raw.last.map { ".:;!?".contains($0) } ?? true
        }
    }
    result.append(Check(rule: "invents no number or name the card lacks", passed: invented.isEmpty && names.isEmpty,
                        detail: (invented + names).isEmpty ? "" : "not in the card: \((invented + names).joined(separator: ", "))",
                        heuristic: true))

    if sample.thin {
        result.append(Check(rule: "thin card gets a short summary", passed: summary.count <= limit / 2,
                            detail: "\(summary.count) characters, at most \(limit / 2) expected", heuristic: true))
    }
    return result
}

let trimmingSet = CharacterSet.whitespacesAndNewlines

func readKey(environment name: String, prompt: String) -> String? {
    if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: trimmingSet), !value.isEmpty {
        return value
    }
    guard let entered = getpass("\(prompt) (input hidden, empty to skip): ") else { return nil }
    let value = String(cString: entered).trimmingCharacters(in: trimmingSet)
    return value.isEmpty ? nil : value
}

func redact(_ text: String) -> String {
    text.replacingOccurrences(of: "sk-[A-Za-z0-9_*-]{3,}", with: "[key]", options: .regularExpression)
}

func indent(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "    " + $0 }.joined(separator: "\n")
}

func showRequest(_ provider: Provider, note: Note, key: String) {
    guard let request = try? provider.request(for: note, apiKey: key), let url = request.url else { return }
    print("Request the app sends for the first card:")
    print("  \(request.httpMethod ?? "?") \(url.absoluteString)")
    for (name, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
        let secret = ["authorization", "x-api-key"].contains(name.lowercased())
        print("  \(name): \(secret ? "<key, never printed>" : value)")
    }
    guard let data = request.httpBody, var body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    for field in ["instructions", "system"] where body[field] is String {
        body[field] = "<Summary.instructions, \(Summary.instructions.count) characters, prompt \(Summary.prompt.rawValue.prefix(8))>"
    }
    if let pretty = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: pretty, encoding: .utf8) {
        print("  body:\n\(indent(text))")
    }
    print()
}

var slots: [(label: String, variable: String)] = [("OpenAI key", "OPENAI_API_KEY")]
if CommandLine.arguments.contains("--anthropic") { slots.append(("Anthropic key, for comparison", "ANTHROPIC_API_KEY")) }
if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
        check-summaries.sh              sample cards through the OpenAI request; key from $OPENAI_API_KEY or a hidden prompt
        check-summaries.sh --anthropic  also through the Anthropic request; key from $ANTHROPIC_API_KEY or a hidden prompt
        """)
    exit(0)
}

let keys = slots.compactMap { readKey(environment: $0.variable, prompt: $0.label) }
guard !keys.isEmpty else {
    print("No key. Set OPENAI_API_KEY, or run this in a terminal and paste a key at the hidden prompt.")
    exit(2)
}

var cards = 0, rules = 0, failedRules = 0, failedRequests = 0
for key in keys {
    let provider = Provider(key: key)
    print("==== \(provider.name): \(samples.count) sample cards ====\n")
    showRequest(provider, note: Note(markdown: samples[0].markdown), key: key)
    for (index, sample) in samples.enumerated() {
        cards += 1
        let note = Note(markdown: sample.markdown)
        print("---- \(index + 1)/\(samples.count) \(sample.name) ----")
        print("Card:\n\(indent(sample.markdown))")
        switch await provider.summarize(note, apiKey: key) {
        case .failed(let reason):
            failedRequests += 1
            print("Summary: none\n  FAIL  the request: \(redact(reason))\n")
        case .text(let summary):
            print("Summary: \(summary)")
            for check in checks(for: sample, note: note, summary: summary) {
                rules += 1
                if !check.passed { failedRules += 1 }
                print("  \(check.passed ? "PASS" : "FAIL")  \(check.rule)\(check.heuristic ? " (heuristic)" : "")\(check.detail.isEmpty ? "" : ": \(check.detail)")")
            }
            print()
        }
    }
}

print("TOTAL: \(cards) cards, \(failedRequests) requests failed, \(rules) rule checks, \(failedRules) failed")
if failedRequests > 0 {
    print("A request failed, so its rules were not checked. The reason is above; HTTP 401 means the key is wrong or has no access to the model.")
}
if failedRules > 0 {
    print("""

        A rule failed. The prompt is shared by both providers (there is no prompt per provider):
          1. Edit Summary.instructions in Cards/Desk.swift. That changes Summary.prompt, so every saved
             summary is asked for again once, after the next build.
          2. Run this script again.
          3. Because Desk.swift changed, run .claude/skills/check-desk-invariants/run.sh, then --mutants,
             then --reviewed, and commit the new reviewed.sha256.
        A (heuristic) rule can fail on a good summary; read the summary and decide.
        """)
}
exit(failedRules == 0 && failedRequests == 0 ? 0 : 1)
