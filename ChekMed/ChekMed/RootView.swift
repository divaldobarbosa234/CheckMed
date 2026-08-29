import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var showSignIn = false

    var body: some View {
        Group {
            if session.isRestoring {
                restoring
            } else if session.kind == .welcome {
                WelcomeView(onSignIn: { showSignIn = true })
            } else {
                MainTabView()
            }
        }
        .sheet(isPresented: $showSignIn) {
            NavigationStack { SignInView() }
        }
    }

    private var restoring: some View {
        VStack(spacing: 16) {
            PhilView(size: 120)
            ProgressView()
            Text("Checking your session")
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }
}
