import Foundation
import os

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
    /// Words the query is a prefix of, exact match first.
    @Published private(set) var results: [DefinitionEntry] = []
    /// Words the query looks like a misspelling of — shown under "Did you mean?", and never
    /// duplicating a row already in `results`.
    @Published private(set) var suggestions: [DefinitionEntry] = []
    /// True between a query arriving and its results landing, so the list can say so instead of
    /// flashing "No definitions found" on the way to a result.
    @Published private(set) var isSearching = false
    /// `results + suggestions` in rendered order. Plain, not `@Published` — read at event time by
    /// the key handlers, which must not touch a publisher while SwiftUI is dispatching. Every other
    /// mode reaches its rows through a method call for the same reason; reading the published array
    /// here is what made ↑/↓ fault with "publishing changes from within view updates".
    private(set) var rows: [DefinitionEntry] = []

    /// One round of disk reads per pause in typing rather than one per keystroke. Measured on a real
    /// session the work itself is 12–68 ms, so the wait was the largest single term in how long a
    /// result took to appear — 80 ms keeps the coalescing while giving most of that back.
    private static let debounce = Duration.milliseconds(80)
    /// Each candidate costs a dictionary read, so the completion list is capped well below the ~20
    /// the spell checker offers — past a handful nobody is reading the rows anyway.
    private static let maxCandidates = 12
    /// "Did you mean?" only earns its keep when little prefix-matches — and asking for it is a
    /// second main-actor spell-checker round-trip, which measured as the only work that blocks the
    /// UI. Below this many results it is worth the call; above, the answer is already on screen.
    private static let suggestWhenFewerThan = 5
    private static let cacheLimit = 32

    /// Debug level, so the instrumentation is dropped unless someone is collecting it — NSLog would
    /// cost more than the work it measures at one message per keystroke. See docs/development.md.
    private nonisolated static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tinycast.app", category: "dictionary")

    private var task: Task<Void, Never>?
    private var cache: [String: Found] = [:]
    private var insertions: [String] = []

    /// Drives the list. `nil` or empty clears it.
    func search(_ partial: String?) {
        guard let partial, !partial.isEmpty else {
            task?.cancel()
            task = nil
            isSearching = false
            results = []
            suggestions = []
            rows = []
            return
        }
        let key = partial.lowercased()
        task?.cancel()
        if let cached = cache[key] {
            task = nil
            isSearching = false
            results = cached.results
            suggestions = cached.suggestions
            rows = cached.results + cached.suggestions
            Self.log.debug(
                "define \(partial, privacy: .private): cache hit, \(cached.results.count + cached.suggestions.count, privacy: .public) results"
            )
            return
        }
        isSearching = true
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            // Spell-check completions are AppKit and main-actor bound; the lookups they feed are not.
            // Timed from after the debounce: the wait is deliberate, the work is what can drag.
            let started = ContinuousClock.now
            let candidates = Self.candidates(partial: partial)
            let completed = ContinuousClock.now
            let batch = candidates
            let found = await Task.detached(priority: .userInitiated) {
                // One `seen` across both lists: a word can only earn one row, wherever it lands.
                var seen = Set<String>()
                return Found(
                    results: batch.results.compactMap { Self.define($0, seen: &seen) },
                    suggestions: batch.suggestions.compactMap { Self.define($0, seen: &seen) })
            }.value
            guard !Task.isCancelled else { return }
            Self.logTiming(
                partial: partial, candidates: batch.results.count + batch.suggestions.count,
                found: found.results.count + found.suggestions.count,
                complete: completed - started, lookup: ContinuousClock.now - completed)
            self.remember(key, found)
        }
    }

    /// The two lists the mode shows, kept apart from candidate selection through to display.
    private struct Batch: Sendable {
        var results: [String] = []
        var suggestions: [String] = []
    }

    /// Deduplicated by the *resolved* headword, not by the candidate word. Distinct candidates share
    /// an entry all the time — `do` and `does` both land on "do" — and since a row shows the headword
    /// the list would otherwise repeat itself, which is what a query of `d` did.
    private nonisolated static func define(_ word: String, seen: inout Set<String>)
        -> DefinitionEntry?
    {
        guard let raw = DictionaryLookup.definition(for: word) else { return nil }
        let definition = DefinitionParser.parse(raw, term: word)
        guard seen.insert(definition.headword.lowercased()).inserted else { return nil }
        return DefinitionEntry(term: word, definition: definition)
    }

    /// The typed word first — it is what the user asked for, and the spell checker doesn't always
    /// rank it first ("ru" offers "running" ahead of "run"). Corrections are filtered against the
    /// completions so a word never appears in both lists, and the cap covers the two together
    /// because the cost is per lookup, not per section.
    private static func candidates(partial: String) -> Batch {
        var seen = Set<String>()
        var batch = Batch()
        for word in [partial] + DictionaryCompletions.completions(for: partial) {
            let key = word.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            batch.results.append(word)
            if batch.results.count == maxCandidates { return batch }
        }
        guard batch.results.count < suggestWhenFewerThan else { return batch }
        for word in DictionaryCompletions.corrections(for: partial) {
            let key = word.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            batch.suggestions.append(word)
            if batch.results.count + batch.suggestions.count == maxCandidates { break }
        }
        return batch
    }

    /// The per-word figure is the one that matters: it is `maxCandidates` multiplied by that number
    /// which decides how the mode feels, so it says directly whether the cap needs lowering.
    private nonisolated static func logTiming(
        partial: String, candidates: Int, found: Int, complete: Duration, lookup: Duration
    ) {
        let completeMs = milliseconds(complete)
        let lookupMs = milliseconds(lookup)
        let perWord = candidates == 0 ? 0 : lookupMs / Double(candidates)
        // Formatted up front rather than interpolated into the log message, so the numbers stay
        // readable as one public string while the query itself remains redactable.
        let summary = String(
            format: "%d candidates, %d defined in %.1fms (complete %.1fms, lookup+parse %.1fms, %.1fms/word)",
            candidates, found, completeMs + lookupMs, completeMs, lookupMs, perWord)
        log.debug("define \(partial, privacy: .private): \(summary, privacy: .public)")
    }

    private nonisolated static func milliseconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1_000_000_000_000_000
    }

    /// What a completed search produced, cached as one unit so a hit restores both lists.
    private struct Found: Sendable {
        let results: [DefinitionEntry]
        let suggestions: [DefinitionEntry]
    }

    private func remember(_ key: String, _ found: Found) {
        if cache.updateValue(found, forKey: key) == nil {
            insertions.append(key)
            if insertions.count > Self.cacheLimit {
                cache.removeValue(forKey: insertions.removeFirst())
            }
        }
        isSearching = false
        results = found.results
        suggestions = found.suggestions
        rows = found.results + found.suggestions
    }
}
