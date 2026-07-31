import CoreServices
import Foundation

/// The system dictionary lookup, kept in its own file so `DictionaryQuery` — and any parser added
/// later — stay Foundation-only and harness-compilable.
///
/// Passing `nil` for the dictionary consults whatever the user enabled in Dictionary.app, in their
/// priority order. There is no public API for a specific dictionary, or for structured results.
enum DictionaryLookup {
    /// Blocking: reads the dictionary indexes off disk, so callers must keep it off the main actor.
    nonisolated static func definition(for term: String) -> String? {
        let text = term as CFString
        let whole = CFRange(location: 0, length: CFStringGetLength(text))
        guard whole.length > 0 else { return nil }
        if let definition = copyDefinition(text, whole) { return definition }

        // The string isn't a headword as typed. `DCSGetTermRangeInString` reports where the
        // dictionary thinks the term actually starts and ends, which is what resolves trailing
        // punctuation and multi-word entries; retry against that.
        //
        // Deliberately a fallback rather than a normalisation step: run first it could narrow a
        // query that already resolved, so as written it can only turn a miss into a hit.
        let term = DCSGetTermRangeInString(nil, text, 0)
        guard term.location != kCFNotFound, term.length > 0, term.length != whole.length else {
            return nil
        }
        return copyDefinition(text, term)
    }

    private nonisolated static func copyDefinition(_ text: CFString, _ range: CFRange) -> String? {
        guard let copied = DCSCopyTextDefinition(nil, text, range) else { return nil }
        let definition = copied.takeRetainedValue() as String
        return definition.isEmpty ? nil : definition
    }
}
