import SwiftUI

/// The inline definition card pinned above the app results, sharing `CalculatorCard`'s frame so the
/// two read as one family. Selectable like a row: Enter copies the definition, ⌘↵ opens Dictionary.app.
struct DictionaryCard: View {
    let entry: DefinitionEntry
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(entry.term)
                .font(.body.weight(.semibold))
            Text(entry.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                // Capped so one long entry can't push the app results off the first screen. The
                // card scrolls with the list, so this is a framing choice, not a layout constraint.
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xxxl)
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
