import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @State private var showSignIn = false
    @State private var launch: LaunchPhase = .splash

    private enum LaunchPhase {
        case splash, welcome, onboarding
    }

    var body: some View {
        Group {
            if session.isRestoring {
                restoring
            } else if session.kind == .welcome {
                switch launch {
                case .splash:
                    SplashView { launch = .welcome }
                case .welcome:
                    WelcomeView(
                        onSignIn: { showSignIn = true },
                        onGetStarted: { launch = .onboarding }
                    )
                case .onboarding:
                    OnboardingView(
                        onFinished: {},
                        onCreateAccount: { showSignIn = true },
                        onBack: { launch = .welcome }
                    )
                }
            } else {
                MainTabView()
            }
        }
        .sheet(isPresented: $showSignIn) {
            NavigationStack { SignInView() }
        }
        .sheet(isPresented: Binding(
            get: { entitlements.showPaywall },
            set: { entitlements.showPaywall = $0 }
        )) {
            NavigationStack { PaywallView() }
        }
        .environment(\.locale, session.locale.foundationLocale)
        .onChange(of: session.kind) { _, kind in
            if kind != .welcome {
                launch = .splash
            }
        }
    }

    private var restoring: some View {
        VStack(spacing: 16) {
            PhilView(size: 120)
            ProgressView()
            Text(session.t(.restoring))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }
}
