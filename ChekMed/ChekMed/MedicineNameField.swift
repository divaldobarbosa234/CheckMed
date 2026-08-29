import SwiftUI

struct MedicineNameField: View {
    @Environment(SessionStore.self) private var session
    let title: String
    @Binding var text: String
    var showsChrome: Bool = true

    @FocusState private var focused: Bool

    private var matches: [MedicationCatalogEntry] {
        MedicationCatalog.suggestions(matching: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            TextField(title, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
                .accessibilityHint(session.t(.medicineSuggestHint))
            if focused, showsChrome {
                suggestionChrome
            }
        }
    }

    @ViewBuilder
    private var suggestionChrome: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Text(session.t(.medicineSuggestHint))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else if matches.isEmpty {
            Text(session.t(.medicineSuggestNoMatch))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        text = entry.name
                        focused = false
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.system(.body, design: .rounded).weight(.heavy))
                                    .foregroundStyle(CheckMedTheme.ink)
                                if !entry.subtitle.isEmpty {
                                    Text(entry.subtitle)
                                        .font(.system(.caption2, design: .rounded).weight(.bold))
                                        .foregroundStyle(CheckMedTheme.muted)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.uturn.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CheckMedTheme.primaryShadow)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(shortcut(for: index), modifiers: [.command])
                    if index < matches.count - 1 {
                        Divider()
                    }
                }
            }
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CheckMedTheme.ink, lineWidth: 2)
            )
        }
    }

    private func shortcut(for index: Int) -> KeyEquivalent {
        switch index {
        case 0: "1"
        case 1: "2"
        case 2: "3"
        case 3: "4"
        case 4: "5"
        case 5: "6"
        case 6: "7"
        case 7: "8"
        default: "1"
        }
    }
}
