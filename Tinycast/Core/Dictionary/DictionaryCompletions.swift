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
    /// `NSSpellChecker` is main-thread affine and returns at most ~20 words, so this stays on the
    /// main actor. The per-word dictionary reads it feeds are the expensive part, and those don't.
    static func words(for partial: String) -> [String] {
        let range = NSRange(location: 0, length: partial.utf16.count)
        guard range.length > 0 else { return [] }
        // `language: nil` follows the user's own text language rather than pinning to English.
        let completions = NSSpellChecker.shared.completions(
            forPartialWordRange: range, in: partial, language: nil, inSpellDocumentWithTag: 0)
        return completions ?? []
    }
}
