import SwiftUI

enum UnfinishedPlanPromptKind {
    case afterReturn
    case beforeAdd
}

struct UnfinishedPlanPromptView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(TodayPathStore.self) private var path
    let kind: UnfinishedPlanPromptKind
    var onContinueAdd: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            PhilView(size: 140, mood: .sad, smiling: false)
                .padding(.bottom, 16)
            Text(session.t(.unfinishedPlanHeadline))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(CheckMedTheme.ink)
            Text(session.t(.unfinishedPlanBody))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Spacer(minLength: 20)
            VStack(spacing: 12) {
                CheckMedButton(title: session.t(.finishUnfinishedPlan)) {
                    session.beginResumeSetup()
                }
                if kind == .afterReturn {
                    CheckMedButton(title: session.t(.startNewPlan), style: .secondary) {
                        startNew()
                    }
                } else {
                    CheckMedButton(title: session.t(.deletePlanAndStartNew), style: .secondary) {
                        startNew()
                        onContinueAdd?()
                    }
                    CheckMedButton(title: session.t(.unfinishedTryPremium), style: .ghost) {
                        entitlements.presentPaywall()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }

    private func startNew() {
        treatments.deleteActiveTreatments()
        session.clearMedicationPlanConfirmed()
        treatments.setSurfacesPlan(false)
        path.reload()
        session.beginFreshPlan()
    }
}

struct ResumePlanSetupFlow: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(TodayPathStore.self) private var path

    @State private var phase: Phase?
    @State private var drafts: [OnboardingPrescriptionDraft]

    private enum Phase: Equatable {
        case confirm, planResume, notifications, alarmSetup, trial, ready
    }

    init() {
        _phase = State(initialValue: nil)
        _drafts = State(initialValue: [.empty])
    }

    var body: some View {
        Group {
            switch phase {
            case .none:
                Color.clear
                    .onAppear { bootstrap() }
            case .confirm:
                OnboardingConfirmView(
                    drafts: $drafts,
                    isManual: false,
                    existingMedicineCount: 0,
                    onConfirm: {
                        for index in drafts.indices { drafts[index].syncDoseTimes() }
                        let capped = drafts.cappedForPlan(
                            isSuper: entitlements.isSuper,
                            existingCount: 0
                        ).filter(\.hasMedicineName)
                        guard !capped.isEmpty else {
                            #if DEBUG
                            print("[CheckMed] resume confirm blocked: empty after cap")
                            #endif
                            return
                        }
                        let ok = treatments.seedFromDrafts(
                            capped,
                            ownerId: session.planOwnerId,
                            profileId: session.planProfileId
                        )
                        guard ok else {
                            #if DEBUG
                            print("[CheckMed] resume seedFromDrafts failed")
                            #endif
                            return
                        }
                        session.markMedicationPlanConfirmed()
                        session.markPendingPostJourneySetup()
                        treatments.setSurfacesPlan(true)
                        path.reload()
                        phase = .planResume
                    },
                    onBack: { session.showResumeSetup = false }
                )
            case .planResume:
                PlanResumeView(
                    drafts: drafts.filter(\.hasMedicineName),
                    showsAddMore: false,
                    onContinue: { advanceAfterJourney() },
                    onBack: { phase = .confirm }
                )
            case .notifications:
                NotificationsPermissionView(
                    secondaryTitle: session.t(.skip),
                    onEnable: { advancePostJourneyFrom(.notifications) },
                    onSecondary: { advancePostJourneyFrom(.notifications) },
                    onBack: { session.showResumeSetup = false }
                )
            case .alarmSetup:
                AlarmSetupView(
                    onEnable: { advancePostJourneyFrom(.alarms) },
                    onSkip: { advancePostJourneyFrom(.alarms) },
                    onBack: {
                        session.syncPostJourneyStep(.notifications)
                        phase = .notifications
                    }
                )
            case .trial:
                OnboardingSuperTrialView {
                    treatments.setSurfacesPlan(true)
                    path.reload()
                    advancePostJourneyFrom(.trial)
                }
            case .ready:
                OnboardingPhilReadyView {
                    finishToHome()
                }
            }
        }
        .onAppear {
            if drafts.allSatisfy({ !$0.hasMedicineName }) {
                drafts = treatments.draftsFromActivePlan()
            }
            if phase == nil {
                bootstrap()
            }
        }
        .onChange(of: session.postJourneyStep) { _, step in
            guard let step, step != .done else { return }
            // Keep UI in sync when RootView hands off after add-intake journey.
            if phase == nil || isPostJourneyPhase(phase) {
                phase = uiPhase(for: step)
            }
        }
    }

    private func isPostJourneyPhase(_ phase: Phase?) -> Bool {
        switch phase {
        case .notifications, .alarmSetup, .trial, .ready, .none:
            true
        default:
            false
        }
    }

    private func advanceAfterJourney() {
        session.startPostJourneyQueue()
        phase = .notifications
    }

    private func advancePostJourneyFrom(_ step: SessionStore.PostJourneyStep) {
        if session.postJourneyStep == nil {
            session.startPostJourneyQueue()
        }
        if session.postJourneyStep != step {
            session.syncPostJourneyStep(step)
        }
        let next = session.advancePostJourney(isSuper: entitlements.isSuper)
        if next == .done {
            finishToHome()
            return
        }
        phase = uiPhase(for: next)
    }

    private func uiPhase(for step: SessionStore.PostJourneyStep) -> Phase {
        switch step {
        case .notifications: return .notifications
        case .alarms: return .alarmSetup
        case .trial: return .trial
        case .philReady, .done: return .ready
        }
    }

    private func bootstrap() {
        if drafts.allSatisfy({ !$0.hasMedicineName }) {
            drafts = treatments.draftsFromActivePlan()
        }
        // Active post-journey queue (e.g. after add-from-Home journey) — never skip.
        if let step = session.postJourneyStep, step != .done {
            phase = uiPhase(for: step)
            return
        }
        if session.pendingPostJourneySetup {
            session.startPostJourneyQueue()
            phase = .notifications
            return
        }
        if !drafts.contains(where: \.hasMedicineName), !session.hasConfirmedMedicationPlan {
            phase = .confirm
            return
        }
        // Confirmed plan mid unfinished setup: start linear chain at notifications.
        session.startPostJourneyQueue()
        phase = .notifications
    }

    private func finishToHome() {
        session.markOnboardingPaywallOffered()
        treatments.setSurfacesPlan(true)
        path.reload()
        session.finishResumeSetup()
    }
}

struct AddPrescriptionGateHost: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @State private var bypassGate = false

    var body: some View {
        if session.needsUnfinishedPlan(treatments: treatments), !bypassGate {
            UnfinishedPlanPromptView(kind: .beforeAdd, onContinueAdd: {
                bypassGate = true
            })
        } else {
            AddPrescriptionIntakeHost()
        }
    }
}
