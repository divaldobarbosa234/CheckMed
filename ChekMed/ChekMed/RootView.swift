import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @State private var wasCompleteAtLaunch = false
    @State private var returningSplashDone = false
    @State private var didCaptureLaunchState = false

    var body: some View {
        Group {
            if session.isRestoring {
                restoring
            } else if !session.hasCompletedOnboarding {
                FirstTimeOnboardingView()
            } else if session.needsPrivacyAcknowledgement {
                PrivacyConsentView(onAccept: { session.acknowledgePrivacy() })
                    .transition(.opacity)
            } else if session.kind == .authenticated, session.needsAccountProfile {
                AccountProfileSetupView()
            } else if wasCompleteAtLaunch, !returningSplashDone {
                SplashView(seconds: 1.2) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        returningSplashDone = true
                    }
                }
                .transition(.opacity)
            } else {
                MainTabView()
            }
        }
        .sheet(isPresented: Binding(
            get: { entitlements.showPaywall },
            set: { entitlements.showPaywall = $0 }
        )) {
            NavigationStack { PaywallView() }
        }
        .environment(\.locale, session.locale.foundationLocale)
        .onAppear { captureLaunchStateIfNeeded() }
        .onChange(of: session.isRestoring) { _, _ in
            captureLaunchStateIfNeeded()
        }
    }

    private func captureLaunchStateIfNeeded() {
        guard !session.isRestoring, !didCaptureLaunchState else { return }
        didCaptureLaunchState = true
        wasCompleteAtLaunch = session.hasCompletedOnboarding
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
