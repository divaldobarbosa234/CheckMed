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
        path.reload()
        session.beginFreshPlan()
    }
}

struct ResumePlanSetupFlow: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(TodayPathStore.self) private var path

    @State private var phase: Phase
    @State private var drafts: [OnboardingPrescriptionDraft]

    private enum Phase {
        case confirm, organize, notifications, ready
    }

    init() {
        _phase = State(initialValue: .confirm)
        _drafts = State(initialValue: [.empty])
    }

    var body: some View {
        Group {
            switch phase {
            case .confirm:
                OnboardingConfirmView(
                    drafts: $drafts,
                    isManual: true,
                    onConfirm: {
                        treatments.seedFromDrafts(
                            drafts.filter(\.hasMedicineName),
                            ownerId: session.auth.userId,
                            profileId: session.profileId
                        )
                        path.reload()
                        if session.needsNotificationsPrompt {
                            phase = .organize
                        } else {
                            session.finishResumeSetup()
                        }
                    },
                    onBack: { session.showResumeSetup = false }
                )
            case .organize:
                OnboardingOrganizeView(
                    onContinue: { phase = .notifications },
                    onBack: { phase = .confirm }
                )
            case .notifications:
                NotificationsPermissionView(
                    secondaryTitle: session.t(.skip),
                    onEnable: { phase = .ready },
                    onSecondary: { phase = .ready },
                    onBack: { phase = .organize }
                )
            case .ready:
                OnboardingPhilReadyView {
                    session.finishResumeSetup()
                }
            }
        }
        .onAppear { bootstrap() }
    }

    private func bootstrap() {
        drafts = treatments.draftsFromActivePlan()
        if treatments.hasMedicationDaysSet {
            phase = session.needsNotificationsPrompt ? .notifications : .ready
        } else {
            phase = .confirm
        }
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
