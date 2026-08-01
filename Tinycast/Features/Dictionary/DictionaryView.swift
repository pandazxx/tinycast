import SwiftUI

/// The dictionary mode's result list: one row per matching word, ordered as the spell checker offers
/// them with the typed word pulled to the top. Enter opens `DictionaryDetail` for the selected row.
struct DictionaryList: View {
    /// Results then suggestions in one array, which is what the flat selection indexes — the same
    /// shape `LauncherList` uses with `favoriteCount`, so the rendered order and the index cannot
    /// drift apart.
    let entries: [DefinitionEntry]
    /// Where "Did you mean?" begins; `entries.count` when there are no suggestions.
    let suggestionsStart: Int
    let selectedID: DefinitionEntry.ID?
    let detailed: Bool
    let scrollToken: UUID
    let onSelect: (DefinitionEntry) -> Void
    let onActivate: () -> Void
    let onActions: (DefinitionEntry) -> Void

    @ViewBuilder
    private func rows(_ entries: [DefinitionEntry]) -> some View {
        ForEach(entries) { entry in
            DictionaryRow(entry: entry, selected: entry.id == selectedID, detailed: detailed)
                .id(entry.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(entry)
                    onActivate()
                }
                .onRightClick { onActions(entry) }
        }
    }

    var body: some View {
        let boundary = min(max(suggestionsStart, 0), entries.count)
        let results = Array(entries.prefix(boundary))
        let suggestions = Array(entries.dropFirst(boundary))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !results.isEmpty {
                        SectionHeader(title: "Results", isFirst: true)
                        rows(results)
                    }
                    if !suggestions.isEmpty {
                        SectionHeader(title: "Did you mean?", isFirst: results.isEmpty)
                        rows(suggestions)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scrollToken) {
                if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
            }
        }
    }
}

/// One matching word. Compact is a single line — word then the first sense, the shape a launcher row
/// already has. Detailed splits it so the pronunciation and part of speech get their own line.
private struct DictionaryRow: View {
    let entry: DefinitionEntry
    let selected: Bool
    let detailed: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// The first sense of the first section — what the word most likely means.
    private var summary: String {
        entry.definition.sections.first?.senses.first?.definition ?? ""
    }

    private var qualifier: String? {
        let parts = [entry.definition.pronunciation, entry.definition.sections.first?.partOfSpeech]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    var body: some View {
        Group {
            if detailed {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                        Text(entry.definition.headword)
                            .font(.body.weight(.medium))
                        if let qualifier {
                            Text(qualifier)
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    Text(entry.definition.headword)
                        .font(.body.weight(.medium))
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, detailed ? Theme.Spacing.lg : Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// One sense: the definition, its examples, and the `•` sub-senses that qualify it. Only the detail
/// view uses this — a row has one line and shows `definition` alone.
private struct SenseView: View {
    let sense: Definition.Sense
    let number: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            if let number {
                Text("\(number)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(sense.definition)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let example = sense.example {
                    Text(example)
                        .font(.callout.italic())
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(sense.subSenses.enumerated()), id: \.offset) { _, sub in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(sub.definition)
                                .fixedSize(horizontal: false, vertical: true)
                            if let example = sub.example {
                                Text(example)
                                    .italic()
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A scroll request for the detail view: a signed step, plus a nonce so back-to-back presses of the
/// same arrow still fire `onChange`. Mirrors `EmojiScrollIntent`.
struct DetailScrollIntent: Equatable {
    var steps: Int = 0
    var nonce = UUID()
}

/// The full entry for one word, reached with Enter. ↑/↓ scroll it by a fixed step rather than moving
/// between anchors: anchoring can't reach the true top or bottom — `.center` on the first sense
/// leaves the headword clipped above it — and it reads as jumping rather than scrolling.
struct DictionaryDetail: View {
    let entry: DefinitionEntry
    let scroll: DetailScrollIntent

    /// Roughly two lines of body text, so a press moves a readable amount without losing your place.
    private static let step: CGFloat = 56

    @State private var position = ScrollPosition()
    @State private var metrics = Metrics()

    /// What the arrows need: where we are, and how far there is left to go.
    private struct Metrics: Equatable {
        var offset: CGFloat = 0
        /// The largest offset that still shows content — scrolling past it just leaves blank space.
        var maximum: CGFloat = 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    Text(entry.definition.headword)
                        .font(.title2.weight(.semibold))
                    if let pronunciation = entry.definition.pronunciation {
                        Text(pronunciation)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                ForEach(Array(entry.definition.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if let partOfSpeech = section.partOfSpeech {
                            Text(partOfSpeech)
                                .font(.body.italic())
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(section.senses.enumerated()), id: \.offset) { index, sense in
                            SenseView(
                                sense: sense,
                                number: section.senses.count > 1 ? index + 1 : nil)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.xxl)
            .hideNativeScrollers()
        }
        .scrollPosition($position)
        // The same geometry the scrollbar reads, kept so the arrows can clamp to the real extent
        // instead of running off either end.
        .onScrollGeometryChange(for: Metrics.self) { geo in
            Metrics(
                offset: geo.contentOffset.y + geo.contentInsets.top,
                maximum: max(
                    0,
                    geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom
                        - geo.containerSize.height))
        } action: { _, new in
            metrics = new
        }
        .onChange(of: scroll) {
            guard scroll.steps != 0 else { return }
            let target = min(
                max(metrics.offset + CGFloat(scroll.steps) * Self.step, 0), metrics.maximum)
            withAnimation(.easeOut(duration: 0.12)) {
                position.scrollTo(y: target)
            }
        }
        .edgeDissolve()
        .thinScrollbar()
    }
}
