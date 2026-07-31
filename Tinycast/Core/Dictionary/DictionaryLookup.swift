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
        let range = CFRange(location: 0, length: CFStringGetLength(text))
        guard range.length > 0 else { return nil }
        guard let copied = DCSCopyTextDefinition(nil, text, range) else { return nil }
        let definition = copied.takeRetainedValue() as String
        return definition.isEmpty ? nil : definition
    }
}
