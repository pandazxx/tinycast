import Foundation

/// Parses the launcher's `define <word>` prefix. Foundation-only and pure so
/// `Tools/dictionary-test.swift` can compile it standalone.
enum DictionaryQuery {
    static let keyword = "define"

    /// The word to look up, or nil when the query isn't a dictionary lookup. The keyword has to be
    /// followed by whitespace, so `defined` and `definer` stay ordinary launcher searches.
    static func term(in query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > keyword.count else { return nil }
        guard trimmed.prefix(keyword.count).lowercased() == keyword else { return nil }
        let afterKeyword = trimmed.index(trimmed.startIndex, offsetBy: keyword.count)
        guard trimmed[afterKeyword].isWhitespace else { return nil }
        let term = trimmed[afterKeyword...].trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? nil : term
    }
}
