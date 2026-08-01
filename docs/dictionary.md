# Dictionary lookup

> **Status: implemented.** The "Alternatives considered" and "Risks" sections are kept because the
> shape changed twice while building; trim them once it settles.

Look words up in the dictionaries macOS already has, from the palette, without leaving it.

## User journey

1. Summon the palette.
2. Type `define ` — the palette switches to Dictionary mode and the prefix disappears from the field.
3. Keep typing. Matching words resolve live, a keystroke behind — `define he` offers `he`, `her`,
   `hello`, each with its first sense.
4. `↵` opens the full entry; `⌘↵` hands the word to Dictionary.app.

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

**The returned format is undocumented.** Captured from macOS 26, the grammar is:

```
<headword> [<syl·la·bi·fied>] | <pronunciation> | [<variants>] [<part of speech>] <senses> [<trailers>]
```

Two wrinkles the captures exposed: a part of speech can be two words (`her` labels its second half
`possessive determiner`, and matching the bare `determiner` inside it loses the section), and the
headword slot can carry a homograph number (`ha 1` is the first of several entries for that spelling,
not a word called "ha 1").

*The whole entry is a single line — there are no newlines anywhere.* Sections have to be recovered
from vocabulary, not whitespace. Everything past the headword is optional: `New York` has no part of
speech and goes straight to numbered senses, `run` has no syllabified form, `quickly` has neither
numbers nor trailers. Senses are numbered `1 2 3 …` in sequence, sub-senses open with `•`, examples
follow a colon, and the entry ends in some subset of `PHRASES`, `PHRASAL VERBS`, `DERIVATIVES`,
`USAGE` and `ORIGIN`.

Two facts drive the parser:

- **Trailers are most of the payload.** They start 43% into `run` and 26% into `apple`, so dropping
  them removes 57% and 74% of those entries — and none of it is the definition.
- **Sequential numbering is what makes sense-splitting safe.** Requiring the *next expected* integer
  is why `1664`, `$1,300` and `population 19,490,297` aren't mistaken for sense markers.
- **A part of speech only opens a section after a sense ends.** `her` defines its pronoun as "used as
  the object of a *verb* or *preposition* to refer to…"; mid-sentence those are ordinary words, and
  treating them as markers split one section into five.

The parser is still **best-effort with a raw fallback**: anything it can't structure comes back as a
single unlabelled section holding the text verbatim, so `sections` is never empty and the view has no
failure case. A definition the user can read beats a tidy model that occasionally shows nothing.

`DCSGetTermRangeInString` (also public) resolves the actual term boundary, which handles multi-word
terms and trailing punctuation. `DictionaryLookup` uses it as a **fallback, not a normalisation
step**: the string is looked up as typed first, and the term range is only tried when that misses.
Run the other way round it could narrow a query that already resolved, so as written it can only turn
a miss into a hit.

There is **no public API for structured results** — no part of speech, no enumerated senses.
`DCSCopyRecordsForSearchString` and `DCSCopyDefinitionMarkup` would provide them but are private and
undocumented; they are not worth the breakage risk, and are deliberately not used.

That isn't just a preference. Raycast's dictionary feature imports exactly two DCS symbols:

```
$ nm -u /Applications/Raycast.app/Contents/MacOS/Raycast | grep -i dcs
_DCSCopyTextDefinition
_DCSGetTermRangeInString
```

Both public, and both are used here too — `DCSGetTermRangeInString` was the one lead that dump gave
us, wired in as the miss-path fallback described above.

`nm -u` only lists undefined *C* symbols, so on its own it rules out the private DCS functions but
says nothing about an Objective-C or Swift call. In particular it can't see AppKit's
`NSView.showDefinition(for:at:options:)` — the public call behind the system Look Up panel, which
renders exactly like Dictionary.app because it *is* Dictionary.app's view. That is the obvious
explanation for a detail pane that looks identical to Dictionary.app, so it was worth checking
against the selector table too:

```
$ strings -a /Applications/Raycast.app/Contents/MacOS/Raycast | grep -i definition
… AIToolDefinition, FunctionDefinition, GRDB's TableDefinition/ColumnDefinition/… , and
"Find definition for a word in active dictionaries…"
```

No `showDefinition`. The only definition-shaped strings are an ORM's schema types and the feature's
own description — and that description confirms the dictionary feature lives in this binary, so the
absence is meaningful rather than a case of looking in the wrong place.

Between the two checks the private markup call and the system panel are both excluded, which leaves
parsing the plain-text blob. **The ceiling here is set by parsing, not by API access** — a detail
view that reads like Dictionary.app is a typography and completeness problem, not a missing API.

## Layout

- `Core/Dictionary/`
  - `DefinitionParser.swift` — **Foundation-only and pure.** Blob in, `Definition` out. No CoreServices,
    no AppKit, no Combine, no clock. This is the file `Tools/dictionary-test.swift` compiles.
  - `DictionaryLookup.swift` — the CoreServices call and nothing else. `nonisolated`, returns a
    plain `String?`. Kept separate *only* so the parser stays harness-compilable — the same reason
    the custom-command confirmation gate lives in `AppCore` rather than in `ShellCommandRunner`.
  - `DictionaryStore.swift` — `@MainActor ObservableObject`, owned by `AppCore`. Debounce,
    cancellation, LRU cache, published `[DefinitionEntry]`.
  - `DictionaryCompletions.swift` — the `NSSpellChecker` candidate list. AppKit, `@MainActor`.
- `Features/Dictionary/DictionaryView.swift` — the result list, its row, and the detail view.
- `Tools/dictionary-test.swift` — the harness.

## Model

```swift
struct Definition: Equatable, Sendable {
    let headword: String
    let pronunciation: String?      // the `| ˈapəl |` span, when present
    let sections: [Section]         // one per part of speech; never empty

    struct Section: Equatable, Sendable {
        let partOfSpeech: String?   // nil for the unparsed fallback
        let senses: [Sense]
    }

    struct Sense: Equatable, Sendable {
        let definition: String
        let example: String?        // the usage examples after the colon
        let subSenses: [Sense]      // the `•` qualifiers; never nested further
    }
}
```

**The parser keeps what the row throws away.** A row has one line and shows `definition` alone; the
detail view scrolls, so it shows the examples and sub-senses too. Trimming in the view rather than in
the parser is what closes the gap with Dictionary.app — `run`'s first verb sense is one line in a row
and ten sub-senses in the detail.

The fallback is a single `Section(partOfSpeech: nil, senses: [rawBlob])`. `sections` is never empty,
so the view and the selection model have no special case to carry.

## Selection

`PaletteMode.dictionary` is a sub-screen like Clipboard or Emoji, so the header shows a back chevron.
One row per matching word; `resultCount == dictResults.count`, no card at index 0 and no offset
arithmetic, which keeps the *"flat `selection` index must match the visible row order"* invariant true
by construction.

`↵` opens `DictionaryDetail` for the selected row. That detail is a screen *inside* the mode rather
than a mode of its own — `resultCount` drops to 0 while it is up (nothing there is selectable), and
Escape and the back chevron pop it before leaving the mode. A second `PaletteMode` would have meant
another seven `switch` arms for a screen with no selection model.

Because it has no rows, ↑/↓ there **scroll** rather than moving a selection. That is a real scroll —
`ScrollPosition` nudged by a fixed step, clamped against the extent reported by
`onScrollGeometryChange`, the same geometry the scrollbar already reads.

An earlier attempt anchored on senses and used `scrollTo(id:)`. It felt like jumping, and worse it
could not reach either end: `.center` on the first sense leaves the headword clipped above it, and
once on the last sense there is nowhere further to go even with content still below. Anchors move
*between things*; this needs to move *through* them.

The step and the clamp live in the view because it is the only place that knows the content's extent;
the key handler just states a direction. Plain `@State` throughout, so a keypress touches no
publisher. The footer's action group stays visible even though `count` is 0, because ↵ and ⌘K both
still do something there.

Row density follows `AppSettings.dictionaryDetailedRows`: one line (word + first sense) or two (word
and pronunciation above, definition below).

Results come in two sections. **Results** are words the query is a prefix of, from
`NSSpellChecker.completions`; **Did you mean?** are words it might be a misspelling of, from
`NSSpellChecker.guesses` — a different call, because completions only ever extend a prefix and so can
never suggest `her` for `ha`. Suggestions are filtered against the results so no word appears twice,
and the flat selection runs results-then-suggestions to match the rendered order.

## Async pipeline

`DCSCopyTextDefinition` does exact lookup only — there is no public "words starting with `ru`" API —
so a query is two steps:

1. **Complete**, on the main actor. `NSSpellChecker.completions(forPartialWordRange:…)` is AppKit and
   main-thread affine, but it returns ~20 strings and costs little. The typed word is pulled to the
   front, because the checker doesn't always rank it first (`ru` offers `running` before `run`).
2. **Look up and parse**, off it. Each candidate is a disk read, so the two lists share a cap of 12 and the
   whole batch runs in one `Task.detached(priority: .userInitiated)`. Candidates the dictionary
   doesn't define — `he's`, `serendipity's` — drop out here, which is also the spelling filter.

Around that: an **80 ms debounce** with cancellation so a fast typist triggers one batch rather than
eight, and a **bounded 32-entry LRU** so backspacing through a word doesn't re-read the disk.

The debounce was 120 ms until a real session was measured. The candidate cap turned out not to be the
cost at all — lookups run 0.6–4.9 ms/word and are off the main actor — while the spell-checker call
*is* on it, at ~12 ms median and one 65 ms outlier. That made the wait itself the largest single term
in how long a result took to appear. Hence 80 ms, and hence the `guesses` call being skipped when the
completions already fill the list: it is a second main-actor round-trip, and "Did you mean?" only
earns it when few things prefix-match.

Each row carries its own parsed `Definition`, so opening the detail view costs nothing.

*The spell checker was chosen over `/usr/share/dict/words` on evidence:* for `ru` it returns
`running, run, rubbish, rush, runs, rub, rumors`, while the word list returns `ruach, ruana, rubasse`.
Inflection-aware and frequency-ordered beats alphabetical.

## Actions

| Key | Action |
| --- | --- |
| `↵` | List: open the detail view. Detail: open the word in Dictionary.app |
| `⌘↵` | List: open in Dictionary.app. Detail: copy the definition |
| `⌘K` | Actions menu: Copy Definition, Copy Word, Open in Dictionary — in both the list and the detail |
| `esc` | Pop the detail view; from the list, close the palette |
| `↑` / `↓` | List: move the selection. Detail: scroll |

`⌘⌫` has no meaning here and stays `.ignored`.

## Plumbing checklist

`PaletteMode.dictionary` touches the seven `switch vm.mode` sites in `RootPaletteView.swift`
(`resultCount`, `actionsContent`, `⌘↵`, `⌘⌫`, `content`, `actionPillLabel`, `activateSelection`) plus
the mode's own declaration in `AppCore.swift`, the `CommandID.defineWord` entry in
`CommandRegistry.swift`, and the `define ` hand-off in `onChange(of: vm.query)`.

That hand-off is deliberately re-entrant: it rewrites `vm.query`, which fires the same handler again,
and the second pass falls through to the search because the mode is no longer `.launcher`.

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

**An inline card in launcher mode**, like the calculator's. This shipped first and was replaced. The
original objection — that a card would overflow the panel — was wrong, since the calculator card
renders inside the launcher's `ScrollView`. What actually killed it is that a card shows *one* word:
there is no room for the candidate list, and typing `define he` should offer `he`, `her`, `hello`
rather than commit to a guess.

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

Shipped. The `NSSpellChecker` completion source, the 12-candidate cap and the 120 ms debounce are the
knobs most likely to need tuning once it has been used in anger — each candidate costs a dictionary
read, so the cap is the one that governs how the mode feels.
