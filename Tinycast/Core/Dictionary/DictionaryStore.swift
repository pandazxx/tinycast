import Foundation

/// One matching word, already looked up and parsed — the row *and* the detail view read from this,
/// so opening an entry costs nothing.
struct DefinitionEntry: Equatable, Sendable, Identifiable {
    let term: String
    let definition: Definition
    var id: String { term }
}

/// Owns the dictionary mode's results: completes the partial word, looks each candidate up off-main,
/// and drops the ones the dictionary doesn't actually define.
@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var entries: [DefinitionEntry] = []
    /// True between a query arriving and its results landing, so the list can say so instead of
    /// flashing "No definitions found" on the way to a result.
    @Published private(set) var isSearching = false

    /// One round of disk reads per pause in typing rather than one per keystroke.
    private static let debounce = Duration.milliseconds(120)
    /// Each candidate costs a dictionary read, so the completion list is capped well below the ~20
    /// the spell checker offers — past a handful nobody is reading the rows anyway.
    private static let maxCandidates = 12
    private static let cacheLimit = 32

    private var task: Task<Void, Never>?
    private var cache: [String: [DefinitionEntry]] = [:]
    private var insertions: [String] = []

    /// Drives the list. `nil` or empty clears it.
    func search(_ partial: String?) {
        guard let partial, !partial.isEmpty else {
            task?.cancel()
            task = nil
            isSearching = false
            entries = []
            return
        }
        let key = partial.lowercased()
        task?.cancel()
        if let cached = cache[key] {
            task = nil
            isSearching = false
            entries = cached
            return
        }
        isSearching = true
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            // Spell-check completions are AppKit and main-actor bound; the lookups they feed are not.
            let candidates = Self.candidates(partial: partial)
            let found = await Task.detached(priority: .userInitiated) {
                candidates.compactMap { word -> DefinitionEntry? in
                    guard let raw = DictionaryLookup.definition(for: word) else { return nil }
                    return DefinitionEntry(
                        term: word, definition: DefinitionParser.parse(raw, term: word))
                }
            }.value
            guard !Task.isCancelled else { return }
            self.remember(key, found)
        }
    }

    /// The typed word first — it is what the user asked for, and the spell checker doesn't always
    /// rank it first ("ru" offers "running" ahead of "run").
    private static func candidates(partial: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for word in [partial] + DictionaryCompletions.words(for: partial) {
            let key = word.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            ordered.append(word)
            if ordered.count == maxCandidates { break }
        }
        return ordered
    }

    private func remember(_ key: String, _ found: [DefinitionEntry]) {
        if cache.updateValue(found, forKey: key) == nil {
            insertions.append(key)
            if insertions.count > Self.cacheLimit {
                cache.removeValue(forKey: insertions.removeFirst())
            }
        }
        isSearching = false
        entries = found
    }
}
