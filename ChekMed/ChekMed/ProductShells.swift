import SwiftUI

struct PlaceholderScreen: View {
    let title: String
    let bubble: String
    let bodyText: String
    var primaryLabel = "Back to today's path"
    var onPrimary: (() -> Void)?
    var secondaryLabel: String?
    var onSecondary: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            PhilView(size: 112)
            SpeechBubbleView(text: bubble)
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            Text(bodyText)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            CheckMedButton(title: primaryLabel, action: onPrimary ?? { dismiss() })
            if let secondaryLabel {
                CheckMedButton(title: secondaryLabel, style: .secondary, action: onSecondary ?? { dismiss() })
            }
            SafetyCaption()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountGateView: View {
    let onCreateAccount: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                PhilView(size: 88)
                SpeechBubbleView(
                    text: "An account keeps this prescription with you. Sign in with Apple, Google, or email before the plan can sync."
                )
                Text("Account required to sync")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                Text("Photo and PDF stay on this phone until you sign in. The first treatment editor stays free.")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                CheckMedButton(title: "Create account", action: onCreateAccount)
                CheckMedButton(title: "Not now", style: .ghost, action: onDismiss)
            }
            .padding(24)
            .background(CheckMedTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(16)
        }
        .accessibilityAddTraits(.isModal)
    }
}
