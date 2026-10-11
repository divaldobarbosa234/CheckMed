import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

enum FirstTimePhase: String, Equatable {
    case splash
    case language
    case howItWorks
    case privacy
    case signIn
    case careContext
    case profile
    case addMedication
    case camera
    case manualEntry
    case analysing
    case slotLimit
    case confirm
    case planResume
    case organize
    case notifications
    case alarmSetup
    case trial
    case ready

    var requiresAuth: Bool {
        switch self {
        case .splash, .language, .privacy, .signIn:
            false
        default:
            true
        }
    }

    var persistable: Bool { self != .splash && self != .analysing && self != .slotLimit }
}

struct FirstTimeOnboardingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(TodayPathStore.self) private var path
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.scenePhase) private var scenePhase

    @State private var phase: FirstTimePhase = .splash
    @State private var addMethod: OnboardingAddMethod = .photo
    @State private var draft = OnboardingPrescriptionDraft.empty
    @State private var drafts = [OnboardingPrescriptionDraft.empty]
    @State private var pendingImport: PendingPrescriptionImport = .none
    @State private var showPhotosPicker = false
    @State private var showPDFImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var afterSplash: FirstTimePhase = .language
    @State private var didBootstrapPhase = false
    @State private var importToken = 0
    @State private var detectedDrafts: [OnboardingPrescriptionDraft] = []
    @State private var selectedDetectionKeys: Set<String> = []
    @State private var didNeedSlotGate = false
    @State private var oldPrescriptionWarningDate: Date? = nil
    @State private var didCommitPlan = false
    @State private var didFinishWelcome = false
    @State private var didFinishCareContext = false

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView {
                    session.markIntroSplashSeen()
                    #if DEBUG
                    print(
                        "[CheckMed] splash done → afterSplash=\(afterSplash) "
                            + "preAuth=\(session.hasFinishedPreAuthFunnel) "
                            + "unlocked=\(session.isSessionUnlocked) "
                            + "onboarded=\(session.hasCompletedOnboarding) "
                            + "postAuth=\(String(describing: session.postAuthKind)) "
                            + "root=\(session.rootDestination)"
                    )
                    #endif
                    advance(to: afterSplash, persist: afterSplash.persistable, animated: false)
                }
            case .language:
                LanguageOnboardingView {
                    session.markLanguageChosen()
                    advance(to: .privacy)
                }
                .transition(insert)
            case .howItWorks:
                HowItWorksView(
                    onContinue: { finishWelcome() },
                    onSkip: { finishWelcome() }
                )
                .transition(insert)
            case .privacy:
                PrivacyConsentView(onAccept: {
                    // PrivacyConsentView already called acknowledgePrivacy().
                    // Always show Sign-in this install — restored Apple session must not skip it.
                    advance(to: .signIn)
                })
                .transition(insert)
            case .signIn:
                NavigationStack {
                    SignInView(onAuthenticated: {
                        session.markSignInScreenCompleted()
                    })
                }
                .transition(insert)
            case .careContext:
                CareContextOnboardingView(onContinue: { finishCareContext() })
                    .transition(insert)
            case .profile:
                AccountProfileSetupView(
                    showsSignOut: true,
                    onFinished: {
                        // Profile must finish before medication scan — never force PDF mid-profile.
                        advance(to: .addMedication)
                    }
                )
                .transition(insert)
            case .addMedication:
                OnboardingAddMedicationView(
                    onPhoto: {
                        startImport(.photo) { advance(to: .camera) }
                    },
                    onChoosePhotos: {
                        startImport(.photo) { showPhotosPicker = true }
                    },
                    onPDF: {
                        startImport(.pdf) { showPDFImporter = true }
                    },
                    onManual: {
                        startImport(.manual) {
                            draft = .empty
                            drafts = [.empty]
                            pendingImport = .none
                            advance(to: .manualEntry)
                        }
                    },
                    onBack: {
                        // Only reopen profile when identity is still incomplete.
                        // Never re-enter name/birth/nouns after setup is done.
                        if session.needsIdentityProfile {
                            advance(to: .profile)
                        }
                    }
                )
                .transition(insert)
            case .camera:
                OnboardingCameraView(
                    onCaptured: { data in
                        pendingImport = .image(Data(data))
                        draft = .empty
                        drafts = [.empty]
                        advance(to: .analysing)
                    },
                    onBack: { advance(to: .addMedication) }
                )
                .transition(insert)
            case .manualEntry:
                OnboardingManualEntryView(
                    draft: $draft,
                    onContinue: {
                        drafts = [draft]
                        advance(to: .analysing)
                    },
                    onBack: { advance(to: .addMedication) }
                )
                .transition(insert)
            case .analysing:
                OnboardingAnalysingView(
                    isShort: addMethod == .manual,
                    work: runImport,
                    onFinished: { presentOldPrescriptionWarningOrContinue() },
                    importToken: importToken
                )
                .transition(insert)
            case .slotLimit:
                ScanSlotLimitView(
                    detected: detectedDrafts,
                    existingCount: treatments.storedMedicineCount,
                    selectedKeys: $selectedDetectionKeys,
                    onUnlockedAll: { continueWithDetectedAll() },
                    onContinueWithSelected: { chosen in
                        drafts = chosen.isEmpty ? [.empty] : chosen
                        draft = drafts[0]
                        advance(to: .confirm)
                    },
                    onBack: { advance(to: .addMedication) }
                )
                .transition(insert)
            case .confirm:
                OnboardingConfirmView(
                    drafts: $drafts,
                    isManual: addMethod == .manual,
                    existingMedicineCount: treatments.storedMedicineCount,
                    source: pendingImport,
                    onConfirm: {
                        for index in drafts.indices { drafts[index].syncDoseTimes() }
                        let capped = drafts.cappedForPlan(isSuper: entitlements.isSuper, existingCount: 0).filter(\.hasMedicineName)
                        ScanLog.confirmed(capped)
                        guard !capped.isEmpty else {
                            #if DEBUG
                            print("[CheckMed] onboarding confirm blocked: empty after cap")
                            #endif
                            return
                        }
                        advance(to: .planResume)
                    },
                    onBack: {
                        if didNeedSlotGate, !entitlements.isSuper {
                            advance(to: .slotLimit)
                        } else {
                            advance(to: addMethod == .manual ? .manualEntry : .addMedication)
                        }
                    }
                )
                .transition(insert)
            case .planResume:
                PlanResumeView(
                    drafts: journeyDraftsForResume(),
                    showsAddMore: false,
                    onContinue: { advanceAfterJourney() },
                    onBack: { advance(to: .confirm) }
                )
                .transition(insert)
            case .organize:
                // Legacy saved phase — jump into the post-journey permission chain.
                Color.clear
                    .onAppear { advanceAfterJourney() }
            case .notifications:
                NotificationsPermissionView(
                    secondaryTitle: session.t(.skip),
                    onEnable: { advancePostJourneyFrom(.notifications) },
                    onSecondary: { advancePostJourneyFrom(.notifications) },
                    onBack: { advance(to: .alarmSetup) }
                )
                .transition(insert)
            case .alarmSetup:
                AlarmSetupView(
                    onEnable: { advancePostJourneyFrom(.alarms) },
                    onSkip: { advancePostJourneyFrom(.alarms) },
                    onBack: { advance(to: .planResume) }
                )
                .transition(insert)
            case .trial:
                OnboardingSuperTrialView {
                    session.markOnboardingPaywallOffered()
                    treatments.setSurfacesPlan(true)
                    path.reload()
                    advancePostJourneyFrom(.trial)
                }
                .transition(insert)
            case .ready:
                OnboardingPhilReadyView {
                    treatments.setSurfacesPlan(true)
                    session.finishResumeSetup()
                    Task {
                        path.reload()
                        ReminderScheduler.shared.reschedule()
                    }
                    Task {
                        await treatments.onNeedsSync?()
                    }
                }
                .transition(insert)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    pendingImport = .image(Data(PrescriptionReader.downsampledJPEG(from: data)))
                    draft = .empty
                    drafts = [.empty]
                    photoItem = nil
                    advance(to: .analysing)
                }
            }
        }
        .prescriptionPDFImporter(isPresented: $showPDFImporter) { url in
            pendingImport = .pdf(url)
            draft = .empty
            drafts = [.empty]
            advance(to: .analysing)
        }
        .onChange(of: entitlements.isSuper) { _, isSuper in
            guard isSuper, phase == .slotLimit else { return }
            continueWithDetectedAll()
        }
        .modifier(OldPrescriptionAgeAlert(
            date: $oldPrescriptionWarningDate,
            onBack: {
                oldPrescriptionWarningDate = nil
                advance(to: addMethod == .manual ? .manualEntry : .addMedication)
            },
            onContinue: {
                oldPrescriptionWarningDate = nil
                routeAfterDetection()
            }
        ))
        .onAppear {
            bootstrapPhase()
            hydrateDraftsIfNeeded(for: phase)
            routeAfterAuthIfNeeded()
        }
        .task {
            bootstrapPhase()
        }
        .onChange(of: session.kind) { oldKind, kind in
            if oldKind == .authenticated, !session.isSessionUnlocked {
                if phase.requiresAuth { return }
                afterSplash = .language
                didBootstrapPhase = false
                advance(to: .splash, persist: false)
            } else if session.isSessionUnlocked {
                // Stay on language / privacy / sign-in until this-install Sign-in completes.
                afterSplash = destinationAfterSplash()
                if phase == .signIn, session.hasCompletedSignInThisInstall {
                    routeAfterAuthIfNeeded()
                }
            }
        }
        .onChange(of: session.postAuthKind) { _, _ in
            routeAfterAuthIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            replayOnboardingIfUnsignedAfterLeaving(phase)
        }
    }

    private func replayOnboardingIfUnsignedAfterLeaving(_ phase: ScenePhase) {
        guard !session.isSessionUnlocked else { return }
        guard !session.auth.isRestoring, !session.isLoading, session.userDataLoadState != .loading else { return }
        if phase == .background {
            session.restartPreAuthOnboarding()
            afterSplash = .language
            didBootstrapPhase = false
        } else if phase == .active, !didBootstrapPhase {
            bootstrapPhase()
        }
    }

    private func routeAfterAuthIfNeeded() {
        guard session.isSessionUnlocked else { return }
        guard session.hasFinishedPreAuthFunnel else { return }
        guard session.hasCompletedSignInThisInstall else { return }
        guard session.restorationComplete else { return }
        if session.hasCompletedOnboarding || session.postAuthKind == .returning { return }
        if session.kind == .authenticated, session.postAuthKind != .newAccount { return }
        guard phase == .signIn else { return }
        advance(to: firstTimePhaseAfterSignIn())
    }

    /// Skip and Continue on Welcome both land here exactly once.
    private func finishWelcome() {
        guard OnboardingWelcomeRouting.consumeWelcomeAdvance(alreadyFinished: didFinishWelcome) else { return }
        didFinishWelcome = true
        session.markHowItWorksSeen()
        advance(to: firstTimePhaseAfterWelcome())
    }

    private func firstTimePhaseAfterWelcome() -> FirstTimePhase {
        firstTimePhase(
            from: OnboardingWelcomeRouting.afterWelcome(
                hasCareContext: session.hasCareContext,
                needsIdentityProfile: session.needsIdentityProfile
            )
        )
    }

    private func finishCareContext() {
        guard OnboardingWelcomeRouting.consumeCareContextAdvance(alreadyFinished: didFinishCareContext) else { return }
        didFinishCareContext = true
        advance(to: firstTimePhaseAfterCareContext())
    }

    private func firstTimePhaseAfterCareContext() -> FirstTimePhase {
        firstTimePhase(
            from: OnboardingWelcomeRouting.afterCareContext(needsIdentityProfile: session.needsIdentityProfile)
        )
    }

    private func firstTimePhaseAfterSignIn() -> FirstTimePhase {
        firstTimePhase(from: OnboardingWelcomeRouting.hostPhase(welcomeRoutingInput()))
    }

    private func firstTimePhase(from step: OnboardingWelcomeRouting.Step) -> FirstTimePhase {
        switch step {
        case .language: return .language
        case .privacy: return .privacy
        case .signIn: return .signIn
        case .welcome: return .howItWorks
        case .careContext: return .careContext
        case .profile: return .profile
        case .addMedication: return .addMedication
        case .home, .restoring: return firstTimePhaseAfterCareContext()
        }
    }

    private func welcomeRoutingInput() -> OnboardingWelcomeRouting.Input {
        OnboardingWelcomeRouting.Input(
            hasChosenLanguage: session.hasChosenLanguage,
            hasAcknowledgedPrivacy: session.hasAcknowledgedPrivacy,
            hasCompletedSignInThisInstall: session.hasCompletedSignInThisInstall,
            isSessionUnlocked: session.isSessionUnlocked,
            hasSeenWelcome: session.hasSeenHowItWorks,
            hasCareContext: session.hasCareContext,
            hasCompletedOnboarding: session.hasCompletedOnboarding,
            isReturningAuthenticated: session.postAuthKind == .returning || session.hasCompletedOnboarding,
            needsIdentityProfile: session.needsIdentityProfile,
            userDataSettled: session.restorationComplete && session.userDataLoadState.isSettled
        )
    }

    private var insert: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 16)),
            removal: .opacity
        )
    }

    private func advance(to next: FirstTimePhase, persist: Bool = true, animated: Bool = true) {
        // Hard gate: never enter scan/medication while identity profile is incomplete.
        let gated: FirstTimePhase
        switch next {
        case .addMedication, .camera, .manualEntry, .analysing, .slotLimit, .confirm:
            gated = session.needsIdentityProfile ? .profile : next
        case .careContext:
            gated = next
        default:
            gated = next
        }
        if gated == .analysing {
            importToken += 1
            didNeedSlotGate = false
            selectedDetectionKeys = []
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) {
                phase = gated
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                phase = gated
            }
        }
        hydrateDraftsIfNeeded(for: gated)
        if persist, gated.persistable {
            session.setFirstTimePhaseRaw(gated.rawValue)
        }
    }

    private func hydrateDraftsIfNeeded(for step: FirstTimePhase) {
        guard step == .planResume || step == .confirm else { return }
        guard drafts.allSatisfy({ !$0.hasMedicineName }) else { return }
        let stored = treatments.draftsFromActivePlan()
        if stored.contains(where: \.hasMedicineName) {
            drafts = stored
        }
    }

    private func bootstrapPhase() {
        if !didBootstrapPhase, session.consumeIncompleteColdLaunchIfNeeded() {
            afterSplash = nextPreAuthPhase(saved: .language)
            didBootstrapPhase = true
            phase = session.auth.isRestoring ? afterSplash : .splash
            return
        }
        afterSplash = destinationAfterSplash()
        if !session.hasFinishedPreAuthFunnel {
            afterSplash = nextPreAuthPhase(saved: afterSplash)
        }
        guard !didBootstrapPhase else {
            routeAfterAuthIfNeeded()
            return
        }
        if !session.hasFinishedPreAuthFunnel {
            afterSplash = nextPreAuthPhase(saved: .language)
            didBootstrapPhase = true
            phase = session.auth.isRestoring ? afterSplash : .splash
            return
        }
        if !session.isSessionUnlocked, !session.auth.isRestoring, !session.isLoading, session.userDataLoadState != .loading {
            session.restartPreAuthOnboarding()
            afterSplash = .language
        }
        didBootstrapPhase = true
        if session.shouldPlayIntroSplash, !session.auth.isRestoring, session.userDataLoadState != .loading {
            phase = .splash
        } else {
            session.markIntroSplashSeen()
            phase = afterSplash
        }
        routeAfterAuthIfNeeded()
    }

    /// Alarms → notifications → trial → Phil. Never jump to Home from journey.
    private func advanceAfterJourney() {
        guard commitOnboardingPlan() else { return }
        session.startPostJourneyQueue()
        advance(to: .alarmSetup)
    }

    @discardableResult
    private func commitOnboardingPlan() -> Bool {
        if didCommitPlan { return true }
        for index in drafts.indices { drafts[index].syncDoseTimes() }
        let capped = drafts.cappedForPlan(isSuper: entitlements.isSuper, existingCount: 0).filter(\.hasMedicineName)
        ScanLog.confirmed(capped)
        guard !capped.isEmpty else {
            #if DEBUG
            print("[CheckMed] onboarding plan-resume commit blocked: empty after cap")
            #endif
            return false
        }
        guard let treatmentId = treatments.seedFromDrafts(
            capped,
            ownerId: session.planOwnerId,
            profileId: session.planProfileId,
            maximumActiveMedicines: entitlements.maximumActiveMedicines
        ) else {
            #if DEBUG
            print("[CheckMed] onboarding seedFromDrafts failed")
            #endif
            return false
        }
        session.markMedicationPlanConfirmed()
        session.markPendingPostJourneySetup()
        treatments.setSurfacesPlan(true)
        treatments.archiveImportedSource(pendingImport, treatmentId: treatmentId)
        if addMethod == .photo || addMethod == .pdf {
            ImportUsage.incrementPhotoPDF(ownerId: session.planOwnerId)
        }
        path.reload()
        didCommitPlan = true
        return true
    }

    private func journeyDraftsForResume() -> [OnboardingPrescriptionDraft] {
        let live = drafts.filter(\.hasMedicineName)
        if !live.isEmpty { return live }
        return treatments.draftsFromActivePlan().filter(\.hasMedicineName)
    }

    private func advancePostJourneyFrom(_ step: SessionStore.PostJourneyStep) {
        if session.postJourneyStep == nil {
            if session.pendingPostJourneySetup {
                session.startPostJourneyQueue()
            } else {
                treatments.setSurfacesPlan(true)
                session.finishResumeSetup()
                return
            }
        }
        if session.postJourneyStep == .philReady || session.postJourneyStep == .done {
            treatments.setSurfacesPlan(true)
            session.finishResumeSetup()
            return
        }
        // Keep queue aligned with the screen the user is leaving.
        if session.postJourneyStep != step {
            session.syncPostJourneyStep(step)
        }
        let next = session.advancePostJourney(isSuper: entitlements.isSuper)
        if next == .done {
            treatments.setSurfacesPlan(true)
            session.finishResumeSetup()
            return
        }
        advance(to: firstTimePhase(for: next))
    }

    private func firstTimePhase(for step: SessionStore.PostJourneyStep) -> FirstTimePhase {
        switch step {
        case .notifications: return .notifications
        case .alarms: return .alarmSetup
        case .trial: return .trial
        case .philReady, .done: return .ready
        }
    }

    private func destinationAfterSplash() -> FirstTimePhase {
        var saved = FirstTimePhase(rawValue: session.firstTimePhaseRaw) ?? .language
        if saved == .splash || saved == .analysing || saved == .slotLimit { saved = .language }

        // Pre-auth funnel (UserDefaults) always wins — delete+reinstall clears these flags
        // even when Keychain still says onboarded. Never jump to .ready / .addMedication here.
        if !session.hasFinishedLegalPreAuth || !session.hasCompletedSignInThisInstall {
            return nextPreAuthPhase(saved: saved)
        }

        // Funnel done but session still locked (shouldn't happen after Sign-in complete).
        guard session.isSessionUnlocked else { return .signIn }

        // Mid post-journey queue always wins over “already onboarded”.
        if let step = session.postJourneyStep, step != .done {
            return firstTimePhase(for: step)
        }

        // Returning / Keychain: RootView should have left FirstTimeOnboarding already.
        // If we are still here, do not open Adicionar receita.
        let keychainDone = ProfileSetupKeychain.isComplete(for: session.auth.userId)
            || ProfileSetupKeychain.isOnboardingComplete(for: session.auth.userId)
        if session.hasCompletedOnboarding || session.postAuthKind == .returning || keychainDone {
            if session.pendingPostJourneySetup { return .planResume }
            // Stay idle; root router will present ReturningWelcome / Home.
            return .signIn
        }

        switch saved {
        case .language, .howItWorks, .privacy, .signIn, .careContext:
            return firstTimePhaseAfterSignIn()
        case .profile:
            return session.needsIdentityProfile ? .profile : .addMedication
        case .confirm where session.hasConfirmedMedicationPlan || treatments.activeTreatmentCount > 0,
             .planResume where session.hasConfirmedMedicationPlan || treatments.activeTreatmentCount > 0:
            return .planResume
        case .organize:
            return .alarmSetup
        case .notifications, .alarmSetup, .trial, .ready, .addMedication, .camera, .manualEntry:
            return saved
        default:
            return saved
        }
    }

    /// Resume the earliest unfinished first-time step
    /// (language → privacy → sign-in → Welcome).
    private func nextPreAuthPhase(saved: FirstTimePhase) -> FirstTimePhase {
        switch OnboardingWelcomeRouting.hostPhase(welcomeRoutingInput()) {
        case .language: return .language
        case .privacy: return .privacy
        case .signIn: return .signIn
        case .welcome: return .howItWorks
        case .careContext: return .careContext
        case .profile: return .profile
        case .addMedication: return .addMedication
        case .home, .restoring:
            break
        }
        _ = saved
        return .signIn
    }

    private func startImport(_ next: OnboardingAddMethod, proceed: () -> Void) {
        guard entitlements.gatePrescriptionAdd(
            method: next,
            existingCount: treatments.storedMedicineCount,
            photoPDFUsed: ImportUsage.photoPDFCount(ownerId: session.planOwnerId)
        ) else { return }
        addMethod = next
        proceed()
    }

    private func runImport() async {
        switch pendingImport {
        case .none:
            if drafts.filter(\.hasMedicineName).isEmpty {
                drafts = [draft]
            }
        case .image(let data):
            let parsed = await PrescriptionReader.drafts(fromImageData: data)
            applyDetected(parsed)
        case .pdf(let url):
            let parsed = await PrescriptionReader.drafts(fromPDF: url)
            applyDetected(parsed)
        }
        if drafts.isEmpty {
            drafts = [.empty]
        }
    }

    private func applyDetected(_ parsed: [OnboardingPrescriptionDraft]) {
        let named = parsed.preparedDetectedMedicines()
        detectedDrafts = named
        selectedDetectionKeys = []
        if named.contains(where: \.hasMedicineName) {
            drafts = named
            draft = drafts[0]
        }
    }

    private func presentOldPrescriptionWarningOrContinue() {
        if addMethod != .manual,
           let date = ScanPipeline.oldPrescriptionDateToWarn(in: detectedDrafts) {
            ScanLog.document("oldPrescription warning date=\(ScanPipeline.iso(date)) thresholdDays=\(ScanPipeline.oldPrescriptionThresholdDays)")
            oldPrescriptionWarningDate = date
            return
        }
        routeAfterDetection()
    }

    private func routeAfterDetection() {
        let named = detectedDrafts.uniqueNamedMedicines
        let existing = treatments.storedMedicineCount
        ScanLog.document("slotGate detected=\(named.count) existing=\(existing) remaining=\(entitlements.freeMedicineSlotsRemaining(existingCount: existing))")
        if addMethod != .manual,
           entitlements.needsScanSlotLimit(detectedCount: named.count, existingCount: existing) {
            didNeedSlotGate = true
            drafts = named.isEmpty ? [.empty] : named
            advance(to: .slotLimit)
            return
        }
        didNeedSlotGate = false
        drafts = named.isEmpty ? drafts : named
        if drafts.isEmpty { drafts = [.empty] }
        advance(to: .confirm)
    }

    private func continueWithDetectedAll() {
        let named = detectedDrafts.uniqueNamedMedicines
        drafts = named.isEmpty ? [.empty] : named
        draft = drafts[0]
        didNeedSlotGate = false
        advance(to: .confirm)
    }
}

struct LanguageOnboardingView: View {
    @Environment(SessionStore.self) private var session
    var onContinue: () -> Void

    @State private var locale: AppLocale = .english

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            PhilGlassesImage(size: 108)
            Text(session.t(.languageHeadline))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(CheckMedTheme.ink)
            Text(session.t(.languageSubhead))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            LanguageWheelPicker(locale: $locale) { session.setLocale($0) }
            Spacer(minLength: 8)
            CheckMedButton(title: session.t(.continueButton)) {
                session.setLocale(locale)
                onContinue()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear { locale = session.locale }
        .accessibilityLabel(session.t(.language))
    }
}

struct HowItWorksView: View {
    @Environment(SessionStore.self) private var session
    var onContinue: () -> Void
    var onSkip: () -> Void

    @State private var playback = HowItWorksPlayback()
    @State private var didFinish = false

    private var beats: [L10n.FlowBeat] { L10n.onboardingFlowBeats(session.locale) }
    private var points: [L10n.Key] {
        [.welcomePointOrganize, .welcomePointRemind, .welcomePointProgress]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(session.t(.skip)) { finish(onSkip) }
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.navy)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .accessibilityLabel(session.t(.skip))
                    .accessibilityIdentifier("welcome-skip")
            }
            .padding(.horizontal, 16)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    mediaCentered
                        .frame(maxWidth: 280)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    VStack(spacing: 8) {
                        Text(session.t(.welcomeCooperTitle))
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(CheckMedTheme.navy)
                            .multilineTextAlignment(.center)
                        Text(session.t(.welcomeCooperLead))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, key in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(CheckMedTheme.primary.opacity(0.18))
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 6)
                                Text(session.t(key))
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(CheckMedTheme.navy)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            VStack(spacing: 10) {
                Text(session.t(.welcomeNotMedical))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                CheckMedButton(title: session.t(.continueButton), action: { finish(onContinue) })
                    .accessibilityIdentifier("welcome-continue")
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .safeAreaPadding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.welcomeCream.ignoresSafeArea())
        .accessibilityLabel(session.t(.welcomeCooperTitle))
        .onAppear { playback.start(beatCount: max(beats.count, 1)) }
        .onDisappear { playback.stop() }
    }

    private func finish(_ action: () -> Void) {
        guard OnboardingWelcomeRouting.consumeWelcomeAdvance(alreadyFinished: didFinish) else { return }
        didFinish = true
        action()
    }

    @ViewBuilder
    private var mediaCentered: some View {
        ZStack {
            Image("phil_onboarding_01_intro")
                .resizable()
                .scaledToFit()
            if let player = playback.player {
                OnboardingFlowPlayerLayer(player: player, rate: HowItWorksPlayback.playbackRate)
            } else if beats.indices.contains(playback.beat) {
                Image(beats[playback.beat].imageName)
                    .resizable()
                    .scaledToFit()
                    .id(playback.beat)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.welcomeCream)
        .accessibilityHidden(true)
    }
}

@MainActor
@Observable
private final class HowItWorksPlayback {
    /// Cropped clip length after last-frame hold (ffprobe).
    static let convertedDuration = 8.25
    static let playbackRate: Float = 1.0
    static let videoResource = "phil_onboarding_flow"

    var beat = 0
    var player: AVPlayer?
    var didReachEnd = false
    var hasBundledVideo: Bool {
        Bundle.main.url(forResource: Self.videoResource, withExtension: "mp4") != nil
    }

    private var duration = HowItWorksPlayback.convertedDuration
    private var beatCount = 5
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var ignoringPlayerSync = false

    func start(beatCount: Int) {
        self.beatCount = max(1, beatCount)
        didReachEnd = false
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: Self.videoResource, withExtension: "mp4") else { return }
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        avPlayer.audiovisualBackgroundPlaybackPolicy = .pauses
        let interval = CMTime(seconds: 0.08, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                self?.syncBeat(to: seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.didReachEnd = true
                self?.player?.pause()
            }
        }
        player = avPlayer
        playSlow()
        Task { await loadDuration(from: url) }
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
    }

    func advance(beatCount: Int, seekVideo: Bool = true) {
        guard beat < beatCount - 1 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            beat += 1
        }
        if seekVideo { seekPlayer(toBeat: beat, beatCount: beatCount) }
    }

    func retreat(beatCount: Int) {
        guard beat > 0 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            beat -= 1
        }
        seekPlayer(toBeat: beat, beatCount: beatCount)
    }

    func playSlow() {
        player?.playImmediately(atRate: Self.playbackRate)
    }

    private func loadDuration(from url: URL) async {
        if let loaded = try? await AVURLAsset(url: url).load(.duration),
           loaded.seconds.isFinite,
           loaded.seconds > 0 {
            duration = loaded.seconds
        }
    }

    private func syncBeat(to seconds: Double) {
        guard !ignoringPlayerSync else { return }
        guard duration > 0, beatCount > 0 else { return }
        guard seconds.isFinite, seconds >= 0 else { return }
        let slice = duration / Double(beatCount)
        let index = min(beatCount - 1, max(0, Int(seconds / slice)))
        guard index != beat else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            beat = index
        }
    }

    private func seekPlayer(toBeat index: Int, beatCount: Int) {
        guard let player, duration > 0, beatCount > 0 else { return }
        ignoringPlayerSync = true
        let slice = duration / Double(beatCount)
        let seconds = slice * Double(index)
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: CMTime(seconds: 0.04, preferredTimescale: 600)
        ) { [weak self] _ in
            Task { @MainActor in
                self?.ignoringPlayerSync = false
                self?.playSlow()
            }
        }
    }
}

private struct OnboardingFlowPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    var rate: Float = HowItWorksPlayback.playbackRate

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.isUserInteractionEnabled = false
        view.clipsToBounds = false
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.backgroundColor = .clear
        uiView.playerLayer.backgroundColor = UIColor.clear.cgColor
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = .resizeAspect
        let duration = player.currentItem?.duration.seconds ?? 0
        let atEnd = duration.isFinite && player.currentTime().seconds + 0.05 >= duration
        if player.timeControlStatus != .playing, duration.isFinite, !atEnd {
            player.playImmediately(atRate: rate)
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
