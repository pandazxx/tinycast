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
        let senses: [Sense]
    }

    /// One numbered sense. The row shows `definition` alone — it has a line; the detail view has a
    /// scroll view, so it shows the examples and the `•` sub-senses that qualify the sense too.
    /// Sub-senses never nest further: the format has one level of bullet.
    struct Sense: Equatable, Sendable {
        let definition: String
        /// The usage examples after the colon, kept verbatim including their `|` separators.
        let example: String?
        let subSenses: [Sense]
    }

    /// Flattened for the clipboard. Every sense, not just the ones the card had room for — but still
    /// the parsed entry rather than the 20 KB of phrases and etymology the system returned.
    var plainText: String {
        var lines = [pronunciation.map { "\(headword)  |\($0)|" } ?? headword]
        for section in sections {
            if let partOfSpeech = section.partOfSpeech { lines.append(partOfSpeech) }
            for (index, sense) in section.senses.enumerated() {
                let number = section.senses.count > 1 ? "\(index + 1). " : ""
                lines.append("  \(number)\(sense.definition)")
                if let example = sense.example { lines.append("      \(example)") }
                for sub in sense.subSenses {
                    lines.append("      • \(sub.definition)")
                    if let example = sub.example { lines.append("        \(example)") }
                }
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
    /// Longer forms have to be listed, not derived: `her` labels its second half "possessive
    /// determiner", and matching the bare "determiner" would fail the preceding-punctuation check
    /// and lose the whole section.
    private static let twoWordPartsOfSpeech: Set<String> = [
        "plural noun", "proper noun", "combining form", "auxiliary verb", "modal verb",
        "definite article", "indefinite article", "possessive determiner", "possessive pronoun",
        "possessive adjective", "reflexive pronoun", "relative pronoun",
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
                ? [
                    .init(
                        partOfSpeech: nil,
                        senses: [.init(definition: head.body, example: nil, subSenses: [])])
                ] : sections)
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

    /// Drops the syllabified duplicate (`apple ap·ple` → `apple`) so the card doesn't say it twice,
    /// and the homograph number that marks one of several entries for a spelling (`ha 1` → `ha`).
    private static func cleanHeadword(_ area: String) -> String? {
        var words = area.split(separator: " ").filter { !$0.contains("·") }
        if words.count > 1, let last = words.last, last.allSatisfy(\.isNumber) {
            words.removeLast()
        }
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
            // A part of speech only opens a section at the start of the body or straight after a
            // sense ends. Mid-sentence they are ordinary words: `her` defines a pronoun as "used as
            // the object of a verb or preposition to refer to…", which otherwise split into three.
            if i > 0, let previous = words[i - 1].last, !".?!)]".contains(previous) { continue }
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
    private static func parseSenses(_ words: [String]) -> [Definition.Sense] {
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
            return [sense(from: words.joined(separator: " "))].compactMap { $0 }
        }
        var senses: [Definition.Sense] = []
        // Anything before sense 1 is a grammar note, not a sense — drop it.
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1] : words.count
            if let parsed = sense(from: words[(start + 1)..<end].joined(separator: " ")) {
                senses.append(parsed)
            }
        }
        return senses
    }

    /// Splits one sense into its definition, its examples, and its `•` sub-senses. The trimming that
    /// used to throw the last two away now happens in the view, which is what lets the detail show a
    /// full entry while a row still shows one line.
    private static func sense(from raw: String) -> Definition.Sense? {
        let segments = raw.components(separatedBy: " • ")
        guard let first = segments.first else { return nil }
        let head = clause(first)
        guard !head.definition.isEmpty else { return nil }
        let subSenses =
            segments.dropFirst()
            .map(clause)
            .filter { !$0.definition.isEmpty }
            .map { Definition.Sense(definition: $0.definition, example: $0.example, subSenses: []) }
        return Definition.Sense(
            definition: head.definition, example: head.example, subSenses: subSenses)
    }

    /// One `definition: example` pair, with the grammar labels and inflection lists that sit between
    /// the part of speech and the definition proper stripped off the front.
    private static func clause(_ raw: String) -> (definition: String, example: String?) {
        var definition = raw
        var example: String?
        if let separator = definition.range(of: ": ") {
            example = String(definition[separator.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            definition = String(definition[definition.startIndex..<separator.lowerBound])
        }
        var stripping = true
        while stripping {
            stripping = false
            if definition.hasPrefix("["), let close = definition.firstIndex(of: "]") {
                definition = String(definition[definition.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
                stripping = true
            } else if definition.hasPrefix("("), let close = definition.firstIndex(of: ")"),
                isInflectionList(
                    String(definition[definition.index(after: definition.startIndex)..<close]))
            {
                definition = String(definition[definition.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
                stripping = true
            }
        }
        return (
            definition.trimmingCharacters(in: .whitespaces),
            example?.isEmpty == false ? example : nil
        )
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
