import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CheckMedStore.self) private var treatments
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.auth.isRestoring || session.isResolvingPostAuth {
                restoring
            } else if !session.hasCompletedOnboarding || session.kind != .authenticated {
                FirstTimeOnboardingView()
            } else if session.needsPrivacyAcknowledgement {
                PrivacyConsentView(onAccept: { session.acknowledgePrivacy() })
                    .transition(.opacity)
            } else if session.kind == .authenticated, session.needsAccountProfile {
                AccountProfileSetupView()
            } else if session.showResumeSetup {
                ResumePlanSetupFlow()
                    .transition(.opacity)
            } else if session.startFreshPrescription {
                AddPrescriptionIntakeHost(
                    onFinished: {
                        if session.needsNotificationsPrompt {
                            session.beginResumeSetup()
                        } else {
                            session.finishFreshPlan(select: .treatments)
                        }
                    },
                    onCancel: { session.finishFreshPlan(select: .home) }
                )
                .transition(.opacity)
            } else if session.showReturningWelcome {
                ReturningWelcomeFlow()
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
        .alert(session.t(.unfinishedPlanHeadline), isPresented: Binding(
            get: { session.showLeaveHealthWarning },
            set: { if !$0 { session.clearLeaveHealthWarning() } }
        )) {
            Button(session.t(.ok), role: .cancel) { session.clearLeaveHealthWarning() }
        } message: {
            Text(session.t(.leaveHealthWarning))
        }
        .environment(\.locale, session.locale.foundationLocale)
        .preferredColorScheme(.light)
        .onAppear {
            Engagement.ping()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                noteIncompleteLeaveIfNeeded()
            }
            if phase == .active {
                Engagement.ping()
                ReminderScheduler.shared.reschedule()
            }
        }
    }

    private var restoring: some View {
        VStack(spacing: 16) {
            PhilReadingImage(size: 112)
            ProgressView()
                .tint(CheckMedTheme.flowDot)
            Text(session.t(.restoring))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }

    private func noteIncompleteLeaveIfNeeded() {
        let inResume = session.showResumeSetup
        let inOnboardingTail = !session.hasCompletedOnboarding && session.kind == .authenticated
        if inResume || inOnboardingTail || session.needsUnfinishedPlan(treatments: treatments) {
            session.noteIncompleteSetupBackground()
        }
    }
}
