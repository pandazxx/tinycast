import Foundation

/// One definition as the palette shows it.
struct DefinitionEntry: Equatable, Sendable {
    let term: String
    let definition: Definition
}

/// Owns the inline definition card's state: debounces the query, runs the blocking lookup off-main,
/// and memoizes what it finds.
@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var entry: DefinitionEntry?

    /// One disk read per pause in typing rather than one per keystroke.
    private static let debounce = Duration.milliseconds(120)
    /// Bounded so a long session can't grow this without limit — misses are cached too, since a
    /// word the dictionary doesn't have is re-typed as often as one it does.
    private static let cacheLimit = 32

    private var task: Task<Void, Never>?
    private var cache: [String: DefinitionEntry?] = [:]
    private var insertions: [String] = []

    /// Drives the card. `nil` clears it — the query stopped reading as a `define` lookup.
    func lookup(_ term: String?) {
        guard let term, !term.isEmpty else {
            task?.cancel()
            task = nil
            entry = nil
            return
        }
        let key = term.lowercased()
        task?.cancel()
        if let cached = cache[key] {
            task = nil
            entry = cached
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            // Parsed off-main too: `run` is 20 KB of single-line text to walk.
            let parsed = await Task.detached(priority: .userInitiated) {
                DictionaryLookup.definition(for: term).map {
                    DefinitionEntry(term: term, definition: DefinitionParser.parse($0, term: term))
                }
            }.value
            guard !Task.isCancelled, let self else { return }
            self.remember(key, parsed)
        }
    }

    /// The card is only replaced once the next result lands, so the panel doesn't strobe mid-word.
    private func remember(_ key: String, _ result: DefinitionEntry?) {
        if cache.updateValue(result, forKey: key) == nil {
            insertions.append(key)
            if insertions.count > Self.cacheLimit {
                cache.removeValue(forKey: insertions.removeFirst())
            }
        }
        entry = result
    }
}
