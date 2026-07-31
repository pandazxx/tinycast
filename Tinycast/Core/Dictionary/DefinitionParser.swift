import Foundation

/// A parsed dictionary entry. `sections` is never empty: an entry the parser can't structure comes
/// back as a single section with a nil part of speech holding the text as-is, so the view never has
/// to special-case a failure.
struct Definition: Equatable, Sendable {
    let headword: String
    let pronunciation: String?
    let sections: [Section]

    struct Section: Equatable, Sendable {
        let partOfSpeech: String?
        let senses: [String]
    }

    /// Flattened for the clipboard. Every sense, not just the ones the card had room for — but still
    /// the parsed entry rather than the 20 KB of phrases and etymology the system returned.
    var plainText: String {
        var lines = [pronunciation.map { "\(headword)  |\($0)|" } ?? headword]
        for section in sections {
            if let partOfSpeech = section.partOfSpeech { lines.append(partOfSpeech) }
            for (index, sense) in section.senses.enumerated() {
                lines.append(section.senses.count > 1 ? "  \(index + 1). \(sense)" : "  \(sense)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Recovers structure from `DCSCopyTextDefinition`'s output, which arrives as one long line with no
/// newlines and no documented grammar. Best-effort by design — see docs/dictionary.md.
///
/// The shape, from real entries:
///
///     <headword> [<syl·la·bi·fied>] | <pronunciation> | [<part of speech>] <senses> [<trailers>]
///
/// Every part is optional past the headword: `New York` has no part of speech and jumps straight to
/// numbered senses, `run` has no syllabified form, `quickly` has neither numbers nor trailers.
enum DefinitionParser {
    /// Everything from the earliest of these is dropped. It is over half of a long entry — 57% of
    /// `run`, 74% of `apple` — and none of it is the definition.
    private static let trailers = [
        " PHRASES ", " PHRASAL VERBS ", " DERIVATIVES ", " USAGE ", " ORIGIN ",
    ]

    private static let singleWordPartsOfSpeech: Set<String> = [
        "abbreviation", "adjective", "adverb", "conjunction", "contraction", "determiner",
        "exclamation", "interjection", "noun", "particle", "prefix", "preposition", "pronoun",
        "suffix", "symbol", "verb",
    ]
    private static let twoWordPartsOfSpeech: Set<String> = [
        "plural noun", "proper noun", "combining form", "auxiliary verb", "modal verb",
        "definite article", "indefinite article",
    ]

    static func parse(_ raw: String, term: String) -> Definition {
        let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else {
            return Definition(headword: term, pronunciation: nil, sections: [])
        }
        let body = dropTrailers(text)
        let head = splitHead(body)
        let sections = parseSections(head.body)
        return Definition(
            headword: head.headword ?? term,
            pronunciation: head.pronunciation,
            // The raw-text fallback: structure recovery failed, so show what the system gave us.
            sections: sections.isEmpty
                ? [.init(partOfSpeech: nil, senses: [head.body])] : sections)
    }

    private static func dropTrailers(_ text: String) -> String {
        var cut = text.endIndex
        for marker in trailers {
            if let range = text.range(of: marker), range.lowerBound < cut {
                cut = range.lowerBound
            }
        }
        return String(text[text.startIndex..<cut])
    }

    /// Splits `headword | pronunciation | rest`. Only the *first* bar pair is the headword's — `run`
    /// carries more inside its inflections (`(, running | ˈrəniNG |)`).
    private static func splitHead(
        _ text: String
    ) -> (headword: String?, pronunciation: String?, body: String) {
        guard
            let open = text.firstIndex(of: "|"),
            let close = text[text.index(after: open)...].firstIndex(of: "|")
        else {
            return (nil, nil, text)
        }
        let headword = cleanHeadword(String(text[text.startIndex..<open]))
        let pronunciation = String(text[text.index(after: open)..<close])
            .trimmingCharacters(in: .whitespaces)
        let body = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        return (headword, pronunciation.isEmpty ? nil : pronunciation, body)
    }

    /// Drops the syllabified duplicate (`apple ap·ple` → `apple`) so the card doesn't say it twice.
    private static func cleanHeadword(_ area: String) -> String? {
        let words = area.split(separator: " ").filter { !$0.contains("·") }
        let headword = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return headword.isEmpty ? nil : headword
    }

    private static func parseSections(_ body: String) -> [Definition.Section] {
        let words = body.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let marks = partOfSpeechMarks(in: words)
        guard !marks.isEmpty else {
            let senses = parseSenses(Array(words))
            return senses.isEmpty ? [] : [.init(partOfSpeech: nil, senses: senses)]
        }
        var sections: [Definition.Section] = []
        // Anything before the first part of speech is a variant note, not a sense — `hello` opens
        // with "(hallo) (mainly British English hullo)". An entry that is *all* lead has no marks at
        // all and was handled above, which is how `New York` keeps its unlabelled senses.
        for (i, mark) in marks.enumerated() {
            let end = i + 1 < marks.count ? marks[i + 1].start : words.count
            let senses = parseSenses(Array(words[mark.end..<end]))
            sections.append(.init(partOfSpeech: mark.label, senses: senses))
        }
        return sections
    }

    /// A part of speech only counts as a section marker at bracket depth 0, so the `adjective` inside
    /// `(-run as adjective, in combination)` doesn't start a phantom section.
    private static func partOfSpeechMarks(
        in words: [String]
    ) -> [(start: Int, end: Int, label: String)] {
        var marks: [(start: Int, end: Int, label: String)] = []
        var depth = 0
        for (i, word) in words.enumerated() {
            let depthBefore = depth
            depth += word.filter { $0 == "(" || $0 == "[" }.count
            depth -= word.filter { $0 == ")" || $0 == "]" }.count
            depth = max(0, depth)
            guard depthBefore == 0 else { continue }
            if i + 1 < words.count {
                let pair = word + " " + words[i + 1]
                if twoWordPartsOfSpeech.contains(pair) {
                    marks.append((i, i + 2, pair))
                    continue
                }
            }
            if singleWordPartsOfSpeech.contains(word) {
                marks.append((i, i + 1, word))
            }
        }
        // A marker inside an earlier marker's two-word span isn't its own section ("plural noun").
        return marks.reduce(into: []) { kept, mark in
            if let last = kept.last, mark.start < last.end { return }
            kept.append(mark)
        }
    }

    /// Senses are numbered `1 2 3 …` in sequence. Requiring the *next expected* integer is what keeps
    /// `1664`, `$1,300` and `population 19,490,297` from being mistaken for sense markers.
    private static func parseSenses(_ words: [String]) -> [String] {
        guard !words.isEmpty else { return [] }
        var starts: [Int] = []
        var expected = 1
        var depth = 0
        for (i, word) in words.enumerated() {
            let depthBefore = depth
            depth += word.filter { $0 == "(" || $0 == "[" }.count
            depth -= word.filter { $0 == ")" || $0 == "]" }.count
            depth = max(0, depth)
            if depthBefore == 0, word == String(expected) {
                starts.append(i)
                expected += 1
            }
        }
        guard !starts.isEmpty else {
            let sense = cleanSense(words.joined(separator: " "))
            return sense.isEmpty ? [] : [sense]
        }
        var senses: [String] = []
        // Anything before sense 1 is a grammar note, not a sense — drop it.
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1] : words.count
            let sense = cleanSense(words[(start + 1)..<end].joined(separator: " "))
            if !sense.isEmpty { senses.append(sense) }
        }
        return senses
    }

    /// Trims a sense to its definition: sub-senses after `•` and the usage examples after the colon
    /// are what make an entry unreadable at a glance, and both are recoverable in Dictionary.app.
    private static func cleanSense(_ raw: String) -> String {
        var sense = raw
        for separator in [" • ", ": "] {
            if let range = sense.range(of: separator) {
                sense = String(sense[sense.startIndex..<range.lowerBound])
            }
        }
        // Leading grammar labels and inflection lists, which sit between the part of speech and the
        // definition proper: "[no object] say or shout", "(helloes, helloing, helloed) say or shout".
        var stripping = true
        while stripping {
            stripping = false
            if sense.hasPrefix("["), let close = sense.firstIndex(of: "]") {
                sense = String(sense[sense.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
                stripping = true
            } else if sense.hasPrefix("("), let close = sense.firstIndex(of: ")"),
                isInflectionList(String(sense[sense.index(after: sense.startIndex)..<close]))
            {
                sense = String(sense[sense.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
                stripping = true
            }
        }
        return sense.trimmingCharacters(in: .whitespaces)
    }

    /// A comma-separated list of single words is an inflection list — `(helloes, helloing, helloed)`.
    /// Anything with a multi-word item is prose worth keeping: `(also apple tree)`, `(the Apple)`.
    private static func isInflectionList(_ inner: String) -> Bool {
        let items = inner.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !items.isEmpty else { return false }
        return items.allSatisfy { !$0.isEmpty && !$0.contains(" ") }
    }
}
