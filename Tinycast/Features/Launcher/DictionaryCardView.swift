import SwiftUI

/// The inline definition card pinned above the app results, sharing `CalculatorCard`'s frame so the
/// two read as one family. Selectable like a row: Enter copies the definition, ⌘↵ opens Dictionary.app.
struct DictionaryCard: View {
    let entry: DefinitionEntry
    let selected: Bool
    @State private var hovered = false

    /// `run` parses to 13 verb senses and 14 noun ones. The card is a glance, not the entry — ⌘↵
    /// opens Dictionary.app for the rest, and Enter copies every sense.
    private static let maxSections = 3
    private static let maxSenses = 3

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var sections: [Definition.Section] {
        Array(entry.definition.sections.prefix(Self.maxSections))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                Text(entry.definition.headword)
                    .font(.body.weight(.semibold))
                if let pronunciation = entry.definition.pronunciation {
                    Text(pronunciation)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    if let partOfSpeech = section.partOfSpeech {
                        Text(partOfSpeech)
                            .font(.callout.italic())
                            .foregroundStyle(.secondary)
                    }
                    let senses = Array(section.senses.prefix(Self.maxSenses))
                    ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            if senses.count > 1 {
                                Text("\(index + 1)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            Text(sense)
                                .font(.callout)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
