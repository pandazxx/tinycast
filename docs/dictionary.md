# Dictionary lookup

> **Status: design, not yet implemented.** The "Alternatives considered", "Risks" and "Rollout"
> sections exist to get the shape agreed before code is written, and should be trimmed once the
> feature ships and this becomes a plain subsystem doc like [calculator.md](calculator.md).

Look a word up in the dictionaries macOS already has, from the palette, without leaving it.

## User journey

1. Summon the palette.
2. Type `define ` — the palette switches to Dictionary mode and the prefix disappears from the field.
3. Keep typing the word. Definitions resolve live, a keystroke behind.
4. `↵` copies the selected sense; `⌘↵` opens the word in Dictionary.app.

`define` is also a command entry, so typing `dict` or `define` with nothing after it finds
**Define Word** in the launcher and enters the mode that way — discoverable without knowing the
prefix, and hotkey-bindable like any other command.

## Why this is a good fit

It is fully **offline** and needs no entitlement: the dictionaries are already on disk and already
licensed to the user. Note this explicitly against the *"every networked feature ships off and is
consent-gated"* invariant in [`AGENTS.md`](../AGENTS.md) — that rule does not apply here, because
nothing leaves the machine. There is no toggle, no consent dialog, and no store-level gate to
re-check. If a future revision adds an online source, that changes and `CurrencyRateStore` becomes
the model to follow.

## The system API

`DCSCopyTextDefinition` (CoreServices / DictionaryServices), public since 10.5 and not deprecated:

```swift
DCSCopyTextDefinition(nil, word as CFString, CFRange(location: 0, length: word.utf16.count))
```

- Passing `nil` for the dictionary consults whatever the user has enabled in Dictionary.app, in their
  priority order. There is no way to name a dictionary or to get results from more than one.
- It returns **plain text**, or `NULL` when nothing matches.
- It is synchronous and hits disk, so it must not run on the main actor.
- No entitlement, and Tinycast is not sandboxed (`app-sandbox` is `false`).

**The returned format is undocumented and unstable.** It is roughly

```
apple | ˈapəl | noun 1 the round fruit of a tree of the rose family… • the tree bearing such
fruit… 2 (in phrases) …  | ORIGIN Old English æppel …
```

— pipes around the pronunciation, `•` for sub-senses, digits opening numbered senses, and a trailing
`ORIGIN` / `PHRASES` block. That shape varies by dictionary and by locale. So the parser is
explicitly **best-effort with a raw fallback**: anything it cannot structure is displayed verbatim
rather than dropped. A definition the user can read beats a tidy model that occasionally shows
nothing.

`DCSGetTermRangeInString` (also public) resolves the actual term boundary, which handles multi-word
terms and inflections (`running` → `run`). Use it to normalise the query before lookup.

There is **no public API for structured results** — no part of speech, no enumerated senses.
`DCSCopyRecordsForSearchString` and `DCSCopyDefinitionMarkup` would provide them but are private and
undocumented; they are not worth the breakage risk, and are deliberately not used.

## Layout

- `Core/Dictionary/`
  - `DefinitionParser.swift` — **Foundation-only and pure.** Blob in, `Definition` out. No CoreServices,
    no AppKit, no Combine, no clock. This is the file `Tools/dictionary-test.swift` compiles.
  - `DictionaryLookup.swift` — the CoreServices call and nothing else. `nonisolated`, returns a
    plain `String?`. Kept separate *only* so the parser stays harness-compilable — the same reason
    the custom-command confirmation gate lives in `AppCore` rather than in `ShellCommandRunner`.
  - `DictionaryStore.swift` — `@MainActor ObservableObject`, owned by `AppCore`. Debounce,
    cancellation, memo, published result.
- `Features/Dictionary/DictionaryView.swift` — the split-pane view.
- `Tools/dictionary-test.swift` — the harness.

## Model

```swift
struct Definition: Equatable, Sendable {
    let headword: String
    let pronunciation: String?      // the `| ˈapəl |` span, when present
    let sections: [Section]         // one per part of speech; never empty
    let origin: String?

    struct Section: Equatable, Sendable {
        let partOfSpeech: String?   // nil for the unparsed fallback
        let senses: [String]
    }
}
```

The fallback is a single `Section(partOfSpeech: nil, senses: [rawBlob])`. `sections` is never empty,
so the view and the selection model have no special case to carry.

## Selection

Dictionary mode reuses the **clipboard split-pane shape**: list on the left at
`Theme.Size.clipboardListWidth`, detail on the right. One row per `Section` — usually one to three
(noun / verb / adjective) — with that section's senses rendered in the scrollable right pane.

This keeps the *"flat `selection` index must match the visible row order exactly"* invariant true by
construction: `resultCount == definition?.sections.count ?? 0`, with no inline card at index 0 and no
offset arithmetic. Long definitions get a scrolling pane instead of a card that would overflow the
panel.

## Async pipeline

Mirrors the shapes already in the codebase rather than inventing a new one:

- Keystroke → `DictionaryStore.query(_:)` on the main actor.
- **Debounce ~120 ms**, cancelling any in-flight lookup, so a fast typist triggers one disk read
  rather than eight.
- The lookup itself runs `nonisolated` via `Task.detached(priority: .userInitiated)` and returns a
  `Sendable` value, per the concurrency boundary in [architecture.md](architecture.md).
- **One-deep memo** keyed on the normalised word, exactly like `CalcMemo`, so re-renders from hover
  or selection don't re-read the disk.
- **The previous result stays on screen while the next resolves.** Clearing to empty on every
  keystroke makes the pane strobe; the calculator card has the same property.

Cache is bounded — a small LRU (~32 entries) rather than an unbounded dictionary, to respect the
under-100 MB rule.

## Actions

| Key | Action |
| --- | --- |
| `↵` | Copy the selected section's senses |
| `⌘↵` | Open the word in Dictionary.app (`dict://` via `NSWorkspace`) |
| `⌘K` | Actions menu: Copy Definition, Copy Word, Open in Dictionary |

`⌘⌫` has no meaning here and stays `.ignored`.

## Plumbing checklist

Adding `PaletteMode.dictionary` touches the seven `switch vm.mode` sites in `RootPaletteView.swift`
plus the mode's own declaration:

| Where | What |
| --- | --- |
| `Core/AppCore.swift` (`PaletteMode`) | case + `title` / `systemImage` / `placeholder` |
| `Core/AppCore.swift` | `dictionary` store wired in `start()`; `runCommand` case |
| `Core/CommandRegistry.swift` | `CommandID.defineWord` + name + SF Symbol |
| `RootPaletteView.swift:66` | `resultCount` |
| `RootPaletteView.swift:108` | `actionsContent` |
| `RootPaletteView.swift:358` | `⌘↵` / `⌥↵` secondary action |
| `RootPaletteView.swift:414` | `⌘⌫` — returns `.ignored` |
| `RootPaletteView.swift:503` | `content(…)` — the split pane |
| `RootPaletteView.swift:660` | `actionPillLabel` |
| `RootPaletteView.swift:764` | `activateSelection` |
| `RootPaletteView.swift` (`onChange`) | the `define ` prefix hand-off |

There is currently **no prefix mechanism anywhere in the palette** — modes are entered by Tab, a
hotkey, or a command entry. `define ` is therefore a new input concept, and it should stay a single
special case in one place rather than a general prefix registry until a second prefix actually exists.

## Testing

`Tools/dictionary-test.swift` compiles the real `DefinitionParser.swift` and asserts against
**fixtures captured from a real Mac** — the blob text pasted in as string literals. That is what
keeps the parser honest about a format nobody documents, and it means the interesting half of this
feature is testable in the Linux agent container (`swiftc Tinycast/Core/Dictionary/DefinitionParser.swift
Tools/dictionary-test.swift`) as well as in CI on macOS.

Cases worth fixing in place: a multi-sense noun, a word with several parts of speech, a word with no
pronunciation, an inflected form, a two-word term, a word with an `ORIGIN` block, and — most
importantly — a deliberately malformed blob that must come back as the raw fallback rather than
crash or produce an empty `sections`.

## Alternatives considered

**An inline card in launcher mode**, like the calculator's. Far less plumbing — no new mode, three
touch points instead of eleven. Rejected because a definition is paragraphs, not a line: the card
would either truncate or push the panel past its fixed frame, and `PaletteWindowController` solely
owns that frame. Worth revisiting only if we ever want a one-line gloss rather than a real entry.

**Private DictionaryServices APIs** for structured results. Rejected — undocumented, and a silent
break on a macOS update would be invisible until a user reported it.

**Parsing the Dictionary.app bundles directly** (`Body.data` / `KeyText.data`). Gives real structure,
but means reimplementing Apple's container format against files that are not a published interface.
Far too much weight for one palette mode.

**Foundation Models / an LLM** to generate definitions. Rejected: not a lookup, invents text, and
would make an offline feature depend on model availability.

**`dict://` only**, punting to Dictionary.app. That is the `⌘↵` action, not the feature — it leaves
the palette, which is the thing the palette exists to avoid.

## Risks and open questions

- **The blob format is the whole risk.** Mitigated by the raw fallback and by fixture-driven tests,
  but the parser's real-world accuracy cannot be judged until we have real output.
- **A user with no dictionaries enabled**, or a non-English system, gets `NULL`. The empty state must
  say something better than "No results" — it should name the cause and point at Dictionary.app's
  preferences.
- **Inflections and phrases** may miss even when the base word exists. `DCSGetTermRangeInString`
  helps; `NSSpellChecker.completions(forPartialWordRange:)` is a possible "did you mean" follow-up,
  deliberately out of scope for the first cut.
- **Open: capture fixtures.** This is the one step that needs a Mac. Everything else can be built and
  tested from the container plus CI. Until then the parser is written against a format described from
  memory, which is exactly the kind of assumption that should not reach `main` unverified.
- **Open: does the prefix consume the word?** Proposed: `define ` (with the trailing space) switches
  mode and hands the remainder over, so the field shows just the word. The alternative — keeping
  `define apple` in the field — is simpler but leaves dead text the user has to delete to search a
  second word.

## Rollout

Three PRs, each independently reviewable and green:

1. `DefinitionParser` + `Tools/dictionary-test.swift` + fixtures. No UI, no CoreServices. Fully
   testable in the container.
2. `DictionaryLookup` + `DictionaryStore` + `AppCore` wiring. Still no UI; the store can be exercised
   by a temporary command.
3. `PaletteMode.dictionary`, the view, the command entry and the `define ` prefix.

Add the link to the subsystem list in [`AGENTS.md`](../AGENTS.md) with step 3, when there is a
subsystem to point at.
