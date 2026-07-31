import SwiftUI

/// The dictionary mode's result list: one row per matching word, ordered as the spell checker offers
/// them with the typed word pulled to the top. Enter opens `DictionaryDetail` for the selected row.
struct DictionaryList: View {
    let results: [DefinitionEntry]
    /// Rendered under "Did you mean?" below the results, and indexed after them by the flat
    /// selection — the visible order is results then suggestions.
    let suggestions: [DefinitionEntry]
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
        ScrollViewReader { proxy in
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

/// The full entry for one word, reached with Enter. Scrolls, because `run` parses to 27 senses.
struct DictionaryDetail: View {
    let entry: DefinitionEntry

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
        .edgeDissolve()
        .thinScrollbar()
    }
}
