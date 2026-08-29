import SwiftUI

struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    var onSignIn: () -> Void
    var onGetStarted: () -> Void

    var body: some View {
        VStack {
            Text(session.t(.welcomeKicker))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(CheckMedTheme.muted)
                .padding(.top, 12)
            Spacer()
            VStack(spacing: 16) {
                PhilView(size: 148)
                Text(session.t(.welcomeHi))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(CheckMedTheme.ink)
                Text(session.t(.welcomeHelp))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            Spacer()
            VStack(spacing: 12) {
                CheckMedButton(title: session.t(.getStarted), action: onGetStarted)
                CheckMedButton(title: session.t(.haveAccount), style: .secondary, action: onSignIn)
                SafetyCaption()
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .accessibilityLabel(session.t(.welcomeKicker))
    }
}
