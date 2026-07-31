import SwiftUI

/// The dictionary mode's result list: one row per matching word, ordered as the spell checker offers
/// them with the typed word pulled to the top. Enter opens `DictionaryDetail` for the selected row.
struct DictionaryList: View {
    let results: [DefinitionEntry]
    let selectedID: DefinitionEntry.ID?
    let detailed: Bool
    let scrollToken: UUID
    let onSelect: (DefinitionEntry) -> Void
    let onActivate: () -> Void
    let onActions: (DefinitionEntry) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: "Results", isFirst: true)
                    ForEach(results) { entry in
                        DictionaryRow(
                            entry: entry, selected: entry.id == selectedID, detailed: detailed
                        )
                        .id(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(entry)
                            onActivate()
                        }
                        .onRightClick { onActions(entry) }
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
        entry.definition.sections.first?.senses.first ?? ""
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
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                                if section.senses.count > 1 {
                                    Text("\(index + 1)")
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                Text(sense)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
