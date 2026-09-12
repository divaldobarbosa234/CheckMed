import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CheckMedStore.self) private var treatments
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.rootDestination {
            case .restoring, .resolvingPostAuth:
                restoring
            case .firstTime:
                FirstTimeOnboardingView()
                    .transition(.opacity)
            case .resumeSetup:
                ResumePlanSetupFlow()
                    .onAppear {
                        if session.pendingPostJourneySetup, !session.showResumeSetup {
                            session.beginResumeSetup()
                        }
                    }
                    .transition(.opacity)
            case .returningWelcome:
                ReturningWelcomeFlow()
                    .transition(.opacity)
            case .accountProfile:
                AccountProfileSetupView(
                    onFinished: { session.markProfileSetupComplete() }
                )
            case .addPrescription:
                AddPrescriptionIntakeHost(
                    onFinished: {
                        // Journey already started the post-journey queue — never jump Home.
                        session.beginResumeSetup()
                    },
                    onCancel: { session.finishFreshPlan(select: .home) }
                )
                .transition(.opacity)
            case .home:
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
            session.noteRootDestinationPresented()
        }
        .onChange(of: session.rootDestination) { _, _ in
            session.noteRootDestinationPresented()
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
        switch session.rootDestination {
        case .resumeSetup, .firstTime:
            session.noteIncompleteSetupBackground()
        default:
            if session.needsUnfinishedPlan(treatments: treatments) {
                session.noteIncompleteSetupBackground()
            }
        }
    }
}
