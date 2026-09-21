import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CheckMedStore.self) private var treatments
    @Environment(\.scenePhase) private var scenePhase
    @State private var showMissedSummary = false

    var body: some View {
        Group {
            switch session.rootDestination {
            case .restoring, .resolvingPostAuth:
                restoring
            case .loadError:
                loadError
            case .firstTime:
                FirstTimeOnboardingView()
            case .resumeSetup:
                ResumePlanSetupFlow()
                    .onAppear {
                        if session.pendingPostJourneySetup, !session.showResumeSetup {
                            session.beginResumeSetup()
                        }
                    }
            case .returningWelcome:
                ReturningWelcomeFlow()
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
            case .home:
                MainTabView()
            }
        }
        // fullScreenCover so Super can appear over an already-open sheet (e.g. Nearby pharmacies from +).
        .fullScreenCover(isPresented: Binding(
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
        .sheet(isPresented: $showMissedSummary) {
            NavigationStack {
                MissedDoseSummarySheet {
                    #if DEBUG
                    let ids = treatments.unresolvedDosesForSummary().map(\.id.uuidString).joined(separator: ",")
                    print("[MISSED-DIAG] SUMMARY DISMISSED ids=\(ids) reason=userDone")
                    #endif
                    showMissedSummary = false
                }
            }
            .presentationDetents([.medium, .large])
        }
        .environment(\.locale, session.locale.foundationLocale)
        .preferredColorScheme(.light)
        .onAppear {
            Engagement.ping()
            session.noteRootDestinationPresented()
            LaunchLog.nav("presented \(session.rootDestination)")
        }
        .onChange(of: session.rootDestination) { _, dest in
            LaunchLog.nav("destination \(dest)")
            session.noteRootDestinationPresented()
            if dest == .home {
                evaluateMissedSummaryAfterDoseDataReady(reason: "rootDestination.home")
            } else {
                showMissedSummary = false
            }
        }
        .onChange(of: treatments.revision) { _, _ in
            // Close only when canonical unresolved is empty. Do not re-open the
            // sheet on every later Challenge confirmation.
            guard showMissedSummary else { return }
            presentMissedSummaryIfNeeded()
        }
        .onChange(of: session.restorationComplete) { _, complete in
            if complete {
                evaluateMissedSummaryAfterDoseDataReady(reason: "restorationComplete")
            } else {
                showMissedSummary = false
            }
        }
        .onChange(of: session.isPlanSurfaceReady) { _, ready in
            if ready {
                evaluateMissedSummaryAfterDoseDataReady(reason: "planSurfaceReady")
            }
        }
        .onChange(of: scenePhase) { oldPhase, phase in
            if phase == .background {
                noteIncompleteLeaveIfNeeded()
            }
            if phase == .active {
                Engagement.ping()
                ReminderScheduler.shared.reschedule(force: false)
                // inactive → active fires for sheets, Control Center, and some
                // SwiftUI animations (Home mood). Only a real background resume
                // should open the missed-dose dialogue.
                if oldPhase == .background {
                    evaluateMissedSummaryAfterDoseDataReady(reason: "scenePhase.backgroundToActive")
                }
            }
        }
    }

    private var restoring: some View {
        VStack(spacing: 16) {
            PhilReadingImage(size: 112)
            ProgressView()
                .tint(CheckMedTheme.onPrimary)
            Text(session.t(.restoringPlan))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.onPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.primary)
    }

    private var loadError: some View {
        VStack(spacing: 16) {
            PhilReadingImage(size: 112)
            Text(session.t(.planLoadErrorHeadline))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(CheckMedTheme.ink)
            Text(session.t(.planLoadErrorBody))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            CheckMedButton(title: session.t(.tryAgain)) {
                session.retryUserDataLoad()
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }

    /// Session restore-ready signal is `session.restorationComplete`
    /// (`userDataLoadState.isSettled`). Dose rows are then reconciled with the
    /// existing `refreshDoseLogsForDisplay()` before the summary eligibility check.
    private func evaluateMissedSummaryAfterDoseDataReady(reason: String) {
        guard session.rootDestination == .home,
              session.restorationComplete,
              session.isPlanSurfaceReady else { return }
        LaunchLog.data("DATA RESTORATION START reason=\(reason)")
        FreezeDiag.log("DATA RESTORATION START reason=\(reason)")
        treatments.refreshDoseLogsForDisplay()
        LaunchLog.data("DATA RESTORATION COMPLETE reason=\(reason)")
        FreezeDiag.log("DATA RESTORATION COMPLETE reason=\(reason)")
        presentMissedSummaryIfNeeded()
    }

    private func presentMissedSummaryIfNeeded() {
        guard session.rootDestination == .home else { return }
        let eligible = treatments.unresolvedDosesForSummary()
        let shouldShow = !eligible.isEmpty
        #if DEBUG
        print(
            "[MISSED-DIAG] SUMMARY PRESENTATION eligible=\(shouldShow) count=\(eligible.count) ids=\(eligible.map(\.id.uuidString).joined(separator: ","))"
        )
        #endif
        if showMissedSummary != shouldShow {
            showMissedSummary = shouldShow
        }
        LaunchLog.data("showMissedSummary = \(showMissedSummary)")
        FreezeDiag.log("showMissedSummary = \(showMissedSummary)")
    }

    private func noteIncompleteLeaveIfNeeded() {
        // `.firstTime` alone is not an unfinished treatment. Splash, language,
        // Sign-in, and Google must not record "this plan still needs you".
        if session.needsUnfinishedPlan(treatments: treatments) {
            session.noteIncompleteSetupBackground()
            return
        }
        if session.rootDestination == .resumeSetup, session.pendingPostJourneySetup {
            session.noteIncompleteSetupBackground()
        }
    }
}

private struct MissedDoseSummarySheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(TodayPathStore.self) private var path
    var onClose: () -> Void

    private var doses: [CheckMedStore.UnresolvedDose] { treatments.unresolvedDosesForSummary() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(doses.count > 1 ? session.t(.missedYouMissedSeveral) : session.t(.missedYouMissedOne))
                    .font(.system(.title2, design: .rounded).weight(.black))
                MissedDoseList(doses: doses) {
                    path.reload()
                    if treatments.unresolvedDosesForSummary().isEmpty {
                        #if DEBUG
                        print("[MISSED-DIAG] SUMMARY DISMISSED ids= reason=unresolvedEmptyAfterConfirm")
                        #endif
                        onClose()
                    }
                }
            }
            .padding(20)
        }
        .background(CheckMedTheme.background)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(session.t(.done)) { onClose() }
            }
        }
    }
}
