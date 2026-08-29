import SwiftUI

struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    var onSignIn: () -> Void
    var onGetStarted: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                PhilView(size: 148)
                Text("CheckMed")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(CheckMedTheme.ink)
                Text("Hi, I’m Phil. I help you understand, organize, and follow your treatments — one path at a time.")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            Spacer()
            VStack(spacing: 12) {
                CheckMedButton(title: "Get started", action: onGetStarted)
                CheckMedButton(title: "I already have an account", style: .secondary, action: onSignIn)
                CheckMedButton(title: "Continue as guest", style: .ghost) {
                    session.continueAsGuest()
                }
                SafetyCaption()
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }
}
