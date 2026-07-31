import AppKit
import Foundation

/// Candidate words for a partial query.
///
/// `DCSCopyTextDefinition` only does exact lookup — there is no public API for "words starting with
/// `ru`" — so the candidate list comes from the spell checker. That is also what makes the order
/// inflection-aware (`run`, `runs`, `running`) instead of alphabetical: a flat word list ranked by
/// prefix returns `ruach, ruana, rubasse` for the same query.
@MainActor
enum DictionaryCompletions {
    /// Words the query could be the start of — `ru` → `running, run, rubbish`. These are the
    /// "Results".
    ///
    /// `NSSpellChecker` is main-thread affine and returns at most ~20 words, so this stays on the
    /// main actor. The per-word dictionary reads it feeds are the expensive part, and those don't.
    static func completions(for partial: String) -> [String] {
        // `language: nil` follows the user's own text language rather than pinning to English.
        NSSpellChecker.shared.completions(
            forPartialWordRange: range(of: partial), in: partial, language: nil,
            inSpellDocumentWithTag: 0) ?? []
    }

    /// Words the query might be a misspelling of — `ha` → `her`. These are the "Did you mean?".
    /// A different call from `completions`, which only ever extends a prefix and so can't suggest a
    /// correction.
    static func corrections(for partial: String) -> [String] {
        NSSpellChecker.shared.guesses(
            forWordRange: range(of: partial), in: partial, language: nil, inSpellDocumentWithTag: 0)
            ?? []
    }

    private static func range(of partial: String) -> NSRange {
        NSRange(location: 0, length: partial.utf16.count)
    }
}
