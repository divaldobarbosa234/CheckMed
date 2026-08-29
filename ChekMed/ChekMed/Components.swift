import SwiftUI

struct CheckMedButton: View {
    let title: String
    var style: Style = .primary
    let action: () -> Void

    enum Style { case primary, secondary, ghost }

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(.body, design: .rounded).weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(style == .primary ? Color.white : CheckMedTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(CheckMedTheme.ink, lineWidth: style == .secondary ? 2 : 0)
                )
                .shadow(color: style == .primary ? CheckMedTheme.primaryShadow : .clear, radius: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary: CheckMedTheme.primary
        case .secondary: CheckMedTheme.surface
        case .ghost: Color.clear
        }
    }
}

struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CheckMedTheme.ink, lineWidth: 2.5)
            )
    }
}

struct SafetyCaption: View {
    var body: some View {
        Text("OCR is a reading aid. CheckMed never recommends medicines, dosages, or diagnoses.")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.safety)
            .multilineTextAlignment(.center)
    }
}

struct GuestBanner: View {
    let onCreateAccount: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browsing as a guest")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text("Create an account before a prescription photo or PDF can sync to the cloud.")
                    .font(.system(.caption, design: .rounded).weight(.bold))
            }
            .foregroundStyle(CheckMedTheme.ink)
            Spacer(minLength: 8)
            Button("Sign in", action: onCreateAccount)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CheckMedTheme.ink, in: Capsule())
        }
        .padding(12)
        .background(CheckMedTheme.guestBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CheckMedTheme.guestBorder, lineWidth: 2)
        )
    }
}
