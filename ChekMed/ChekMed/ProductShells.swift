import SwiftUI

enum ProductRoute: Hashable {
    case review
    case treatment
    case medicine(String)
    case paywall
    case family
}

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

struct ProductRouteView: View {
    let route: ProductRoute
    @Binding var path: NavigationPath

    var body: some View {
        switch route {
        case .review:
            PlaceholderScreen(
                title: "Review",
                bubble: "You check every field. I never invent a medicine. Confirm is what turns a scan into today's path.",
                bodyText: "Preview, raw text, and editable fields land in Phase 4. This shell keeps the click-through: Scan → Review → Treatment.",
                primaryLabel: "Continue to treatment",
                onPrimary: { path.append(ProductRoute.treatment) },
                secondaryLabel: "Back to scan",
                onSecondary: pop
            )
        case .treatment:
            PlaceholderScreen(
                title: "Treatment",
                bubble: "This is the editor after you verify. Remaining days and the original document arrive with import.",
                bodyText: "Phase 2 shell. Phase 3 stores treatments locally. Open a medicine to see the detail placeholder.",
                primaryLabel: "Open a medicine",
                onPrimary: { path.append(ProductRoute.medicine("vitamin-d")) },
                secondaryLabel: "Back",
                onSecondary: pop
            )
        case .medicine(let id):
            PlaceholderScreen(
                title: "Medicine",
                bubble: "This card is \(id). How to take it, timeline, and the original prescription stay with the treatment you verified.",
                bodyText: "Detail, how-to-take, and knowledge screens stay shells until Phase 4. Not medical advice.",
                primaryLabel: "Back to treatment",
                onPrimary: pop
            )
        case .paywall:
            PaywallView()
        case .family:
            FamilyView()
        }
    }

    private func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
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
                    text: "An account keeps this prescription with you. Guest can browse Home — cloud scan waits for a real session."
                )
                Text("Account required to sync")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                Text("Photo and PDF stay on this phone until you sign in. Then Phase 3 can sync to your CheckMed account.")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                CheckMedButton(title: "Create account", action: onCreateAccount)
                CheckMedButton(title: "Keep browsing as guest", style: .ghost, action: onDismiss)
            }
            .padding(24)
            .background(CheckMedTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(16)
        }
        .accessibilityAddTraits(.isModal)
    }
}
