import GoogleSignIn
import SwiftUI
import UIKit

#if DEBUG
/// Explicit launch-only DEBUG contract runner. Interactive Debug does not set this.
enum DebugContractLaunch {
    static let environmentKey = "CHECKMED_DEBUG_CONTRACTS"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }
}
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        if CapacityContractLaunch.shouldIsolateProcess {
            CapacityContractLaunch.runFromAppDelegate()
            return true
        }
        if SeedDurableContractLaunch.shouldIsolateProcess {
            SeedDurableContractLaunch.runFromAppDelegate()
            return true
        }
        if TH1LocalVerification.shouldIsolateProcess {
            TH1LocalVerification.logActivation(stage: "AppDelegate")
            return true
        }
        if IntakeVerify.shouldIsolateProcess {
            IntakeVerify.logActivation(stage: "AppDelegate")
            return true
        }
        #endif
        if let clientID = AuthConfig.googleClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        ReminderScheduler.shared.configure()
        #if DEBUG
        AuthIsolationDiagnostics.recordLaunch()
        #endif
        #if DEBUG
        // Interactive Debug must not run the heavyweight suite. Explicit
        // CHECKMED_DEBUG_CONTRACTS=1 still executes every suite and asserts.
        if CapacityContractLaunch.isRequested {
            print(
                "[CheckMed] DEBUG contracts skipped (capacity-only). "
                    + "Full suite requires \(DebugContractLaunch.environmentKey)=1."
            )
        } else if DebugContractLaunch.isRequested {
            Task {
            let rewardReport = RewardEngineContractChecks.runtimeReport()
            print("RewardEngine runtime:\n\(rewardReport)")
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? rewardReport.write(
                    to: docs.appendingPathComponent("checkmed-reward-contracts.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            let doseFailures = DoseLoopContractChecks.failures()
            let gamificationFailures = GamificationContractChecks.failures()
            let journeyFailures = DailyMedicationJourneyContractChecks.failures()
            let weeklyFailures = WeeklyMedicationProgressContractChecks.failures()
            let streakFailures = AdherenceStreakContractChecks.failures()
            let philFailures = PhilCoachContractChecks.failures()
            let prescriptionDateFailures = PrescriptionDateContractChecks.failures()
            let laterAddFailures = LaterAddPersistContractChecks.failures()
            let confirmSlotFailures = ConfirmMedicineSlotCapacityContractChecks.failures()
            let journeyTreeFailures = TreatmentJourneyClassificationContractChecks.failures()
            let lifecycleFailures = await MainActor.run { TreatmentLifecycleContractChecks.failures() }
            let capacitySafetyFailures = await MainActor.run { MedicationCapacitySafetyContractChecks.failures() }
            let titleFailures = await MainActor.run { TreatmentTitleContractChecks.failures() }
            let missedAckFailures = await MainActor.run { MissedDosePresentationContractChecks.failures() }
            let skippedLabelFailures = CompletedSkippedLabelContractChecks.failures()
            let welcomeFailures = OnboardingWelcomeContractChecks.failures()
            let quietDayFailures = await MainActor.run { HomeQuietDayContractChecks.failures() }
            let superTrialFailures = SuperTrialContractChecks.failures()
            let clockFailures = CheckMedClockContractChecks.failures()
            let rewardFailures = RewardEngineContractChecks.failures()
            let syncTransportFailures = await SyncTransportContractChecks.failures()
            let syncOutboxFailures = await SyncOutboxContractChecks.failures()
            let syncProtocolFailures = await SyncProtocolContractChecks.failures()
            let syncProtocolE2EFailures = await SyncProtocolE2EContractChecks.failures()
            let failures = doseFailures + gamificationFailures + journeyFailures + weeklyFailures + streakFailures + philFailures + prescriptionDateFailures + laterAddFailures + confirmSlotFailures + journeyTreeFailures + lifecycleFailures + capacitySafetyFailures + titleFailures + missedAckFailures + skippedLabelFailures + welcomeFailures + quietDayFailures + superTrialFailures + clockFailures + rewardFailures + syncTransportFailures + syncOutboxFailures + syncProtocolFailures + syncProtocolE2EFailures
            print("DoseLoop failures:", doseFailures)
            print("Gamification failures:", gamificationFailures)
            print("DailyJourney failures:", journeyFailures)
            print("WeeklyProgress failures:", weeklyFailures)
            print("Streak failures:", streakFailures)
            print("PhilCoach failures:", philFailures)
            print("PrescriptionDate failures:", prescriptionDateFailures)
            print("LaterAddPersist failures:", laterAddFailures)
            print("ConfirmMedicineSlotCapacity failures:", confirmSlotFailures)
            print("JourneyTree failures:", journeyTreeFailures)
            print("TreatmentLifecycle failures:", lifecycleFailures)
            print("MedicationCapacitySafety failures:", capacitySafetyFailures)
            print("TreatmentTitle failures:", titleFailures)
            print("MissedDosePresentation failures:", missedAckFailures)
            print("CompletedSkippedLabel failures:", skippedLabelFailures)
            print("OnboardingWelcome failures:", welcomeFailures)
            print("HomeQuietDay failures:", quietDayFailures)
            print("SuperTrial failures:", superTrialFailures)
            print("TestClock failures:", clockFailures)
            print("RewardEngine failures:", rewardFailures)
            print("SyncTransport failures:", syncTransportFailures)
            print("SyncOutbox failures:", syncOutboxFailures)
            print("SyncProtocol failures:", syncProtocolFailures)
            print("SyncProtocolE2E failures:", syncProtocolE2EFailures)
            let report = [
                "DoseLoop failures: \(doseFailures)",
                "Gamification failures: \(gamificationFailures)",
                "DailyJourney failures: \(journeyFailures)",
                "WeeklyProgress failures: \(weeklyFailures)",
                "Streak failures: \(streakFailures)",
                "PhilCoach failures: \(philFailures)",
                "PrescriptionDate failures: \(prescriptionDateFailures)",
                "LaterAddPersist failures: \(laterAddFailures)",
                "ConfirmMedicineSlotCapacity failures: \(confirmSlotFailures)",
                "JourneyTree failures: \(journeyTreeFailures)",
                "TreatmentLifecycle failures: \(lifecycleFailures)",
                "MedicationCapacitySafety failures: \(capacitySafetyFailures)",
                "TreatmentTitle failures: \(titleFailures)",
                "MissedDosePresentation failures: \(missedAckFailures)",
                "CompletedSkippedLabel failures: \(skippedLabelFailures)",
                "OnboardingWelcome failures: \(welcomeFailures)",
                "HomeQuietDay failures: \(quietDayFailures)",
                "SuperTrial failures: \(superTrialFailures)",
                "TestClock failures: \(clockFailures)",
                "RewardEngine failures: \(rewardFailures)",
                "SyncTransport failures: \(syncTransportFailures)",
                "SyncOutbox failures: \(syncOutboxFailures)",
                "SyncProtocol failures: \(syncProtocolFailures)",
                "SyncProtocolE2E failures: \(syncProtocolE2EFailures)",
                "allEmpty: \(failures.isEmpty)",
            ].joined(separator: "\n")
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? report.write(
                    to: docs.appendingPathComponent("checkmed-debug-contracts.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            assert(
                failures.isEmpty,
                [
                    doseFailures.isEmpty ? nil : "DOSE LOOP FAILURE: \(doseFailures.joined(separator: "; "))",
                    gamificationFailures.isEmpty ? nil : "GAMIFICATION FAILURE: \(gamificationFailures.joined(separator: "; "))",
                    journeyFailures.isEmpty ? nil : "DAILY JOURNEY FAILURE: \(journeyFailures.joined(separator: "; "))",
                    weeklyFailures.isEmpty ? nil : "WEEKLY PROGRESS FAILURE: \(weeklyFailures.joined(separator: "; "))",
                    streakFailures.isEmpty ? nil : "STREAK FAILURE: \(streakFailures.joined(separator: "; "))",
                    philFailures.isEmpty ? nil : "PHIL COACH FAILURE: \(philFailures.joined(separator: "; "))",
                    prescriptionDateFailures.isEmpty ? nil : "PRESCRIPTION DATE FAILURE: \(prescriptionDateFailures.joined(separator: "; "))",
                    laterAddFailures.isEmpty ? nil : "LATER ADD PERSIST FAILURE: \(laterAddFailures.joined(separator: "; "))",
                    confirmSlotFailures.isEmpty ? nil : "CONFIRM MEDICINE SLOT CAPACITY FAILURE: \(confirmSlotFailures.joined(separator: "; "))",
                    lifecycleFailures.isEmpty ? nil : "TREATMENT LIFECYCLE FAILURE: \(lifecycleFailures.joined(separator: "; "))",
                    capacitySafetyFailures.isEmpty ? nil : "MEDICATION CAPACITY SAFETY FAILURE: \(capacitySafetyFailures.joined(separator: "; "))",
                    titleFailures.isEmpty ? nil : "TREATMENT TITLE FAILURE: \(titleFailures.joined(separator: "; "))",
                    missedAckFailures.isEmpty ? nil : "MISSED DOSE PRESENTATION FAILURE: \(missedAckFailures.joined(separator: "; "))",
                    skippedLabelFailures.isEmpty ? nil : "COMPLETED SKIPPED LABEL FAILURE: \(skippedLabelFailures.joined(separator: "; "))",
                    welcomeFailures.isEmpty ? nil : "ONBOARDING WELCOME FAILURE: \(welcomeFailures.joined(separator: "; "))",
                    quietDayFailures.isEmpty ? nil : "HOME QUIET DAY FAILURE: \(quietDayFailures.joined(separator: "; "))",
                    superTrialFailures.isEmpty ? nil : "SUPER TRIAL FAILURE: \(superTrialFailures.joined(separator: "; "))",
                    clockFailures.isEmpty ? nil : "TEST CLOCK FAILURE: \(clockFailures.joined(separator: "; "))",
                    journeyTreeFailures.isEmpty ? nil : "JOURNEY TREE FAILURE: \(journeyTreeFailures.joined(separator: "; "))",
                    rewardFailures.isEmpty ? nil : "REWARD ENGINE FAILURE: \(rewardFailures.joined(separator: "; "))",
                    syncTransportFailures.isEmpty ? nil : "SYNC TRANSPORT FAILURE: \(syncTransportFailures.joined(separator: "; "))",
                    syncOutboxFailures.isEmpty ? nil : "SYNC OUTBOX FAILURE: \(syncOutboxFailures.joined(separator: "; "))",
                    syncProtocolFailures.isEmpty ? nil : "SYNC PROTOCOL FAILURE: \(syncProtocolFailures.joined(separator: "; "))",
                    syncProtocolE2EFailures.isEmpty ? nil : "SYNC PROTOCOL E2E FAILURE: \(syncProtocolE2EFailures.joined(separator: "; "))",
                ].compactMap { $0 }.joined(separator: " | ")
            )
        }
        } else {
            print(
                "[CheckMed] DEBUG contracts skipped (interactive). "
                    + "Set \(DebugContractLaunch.environmentKey)=1 to run the full suite."
            )
        }
        #endif
        return true
    }
}


@main
struct ChekMedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var treatments = Self.makeAppStore()
    @State private var path = TodayPathStore()
    @State private var entitlements = EntitlementStore()
    @State private var syncEngine = SyncEngine()
    @State private var family = FamilyStore()
    @State private var voice = PhilVoice()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if TH1LocalVerification.isAllowed {
                TH1LocalVerificationHost()
                    .environment(session)
                    .environment(entitlements)
                    .environment(path)
                    .environment(\.locale, session.locale.foundationLocale)
            } else if TH1LocalVerification.isMisconfiguredRequest {
                TH1LocalVerificationDeniedHost()
            } else if IntakeVerify.isAllowed {
                IntakeVerifyHost()
                    .environment(session)
                    .environment(entitlements)
                    .environment(path)
                    .environment(\.locale, session.locale.foundationLocale)
            } else if IntakeVerify.isMisconfiguredRequest {
                IntakeVerifyDeniedHost()
            } else if CapacityContractLaunch.isRequested {
                CapacityContractHost()
            } else if SeedDurableContractLaunch.isRequested {
                SeedDurableContractHost()
            } else {
                standardRoot
            }
            #else
            standardRoot
            #endif
        }
    }

    /// DEBUG intake isolate must not open the ordinary on-disk store.
    /// TH-1 and production keep `CheckMedStore()` (disk, `liveStore` assignment).
    private static func makeAppStore() -> CheckMedStore {
        #if DEBUG
        if CapacityContractLaunch.shouldIsolateProcess {
            return CheckMedStore(isolatedInMemoryForContracts: true)
        }
        if SeedDurableContractLaunch.shouldIsolateProcess {
            return CheckMedStore(isolatedInMemoryForContracts: true)
        }
        if IntakeVerify.shouldIsolateProcess && !TH1LocalVerification.shouldIsolateProcess {
            return CheckMedStore(isolatedInMemoryForContracts: true)
        }
        #endif
        return CheckMedStore()
    }

    @ViewBuilder
    private var standardRoot: some View {
        RootView()
            .environment(session)
            .environment(treatments)
            .environment(path)
            .environment(entitlements)
            .environment(syncEngine)
            .environment(family)
            .environment(voice)
            .environment(\.locale, session.locale.foundationLocale)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            .onAppear { bindStores() }
            .onChange(of: session.kind) { _, _ in
                bindStores()
            }
            .onChange(of: session.profileId) { _, profileId in
                guard authorizeAuthenticatedBinding() else { return }
                treatments.bindIdentity(ownerId: session.planOwnerId, profileId: profileId)
                family.applyScope(to: treatments, primaryProfileId: session.planProfileId)
            }
            .onChange(of: session.timeZoneName) { _, _ in
                guard authorizeAuthenticatedBinding() else { return }
                treatments.setTimeZone(session.foundationTimeZone)
                ReminderScheduler.shared.reschedule(force: true)
            }
            .onChange(of: session.locale) { _, _ in
                guard authorizeAuthenticatedBinding() else { return }
                ReminderScheduler.shared.reschedule(force: true)
            }
            .onChange(of: entitlements.isSuper) { _, isSuper in
                guard authorizeAuthenticatedBinding() else { return }
                if !isSuper {
                    family.selectPrimary()
                    family.applyScope(to: treatments, primaryProfileId: session.planProfileId)
                }
                ReminderScheduler.shared.reschedule(force: true)
            }
    }

    private func bindStores() {
        guard authorizeAuthenticatedBinding() else {
            session.startAuthIfNeeded()
            return
        }
        let ownerId = session.planOwnerId
        let profileId = session.planProfileId
        if let authId = session.auth.userId, authId != session.localPlanOwnerId {
            treatments.adoptOwner(from: session.localPlanOwnerId, to: authId, profileId: profileId)
        }
        family.load(ownerId: session.auth.userId ?? ownerId)
        treatments.bindIdentity(ownerId: ownerId, profileId: profileId)
        treatments.setTimeZone(session.foundationTimeZone)
        family.applyScope(to: treatments, primaryProfileId: profileId)
        path.bind(store: treatments)
        #if DEBUG
        CheckMedClock.installCommandBridge(
            timeZone: { [session] in session.foundationTimeZone },
            onApplied: { [treatments, path] in
                treatments.invalidateTimeDerivedCachesForTestClock()
                path.reload()
            }
        )
        #endif
        syncEngine.bind(store: treatments, session: session)
        syncEngine.bindFamily(family)
        session.onWillSignOut = { [syncEngine] in
            syncEngine.invalidateSession()
        }
        session.onPrepareAccountDeletion = { [syncEngine] ownerId in
            await syncEngine.beginAccountDeletion(ownerId: ownerId)
        }
        session.onCancelAccountDeletion = { [syncEngine] ownerId in
            syncEngine.cancelAccountDeletion(ownerId: ownerId)
        }
        treatments.onRecordsChanged = { [path] in
            FreezeDiag.log("onRecordsChanged() CALLED from ChekMedApp.bindStores")
            LaunchLog.home("onRecordsChanged → coalesced path.reload")
            path.scheduleReload()
            ReminderScheduler.shared.reschedule(force: false)
        }
        ReminderScheduler.shared.bind(
            store: treatments,
            session: session,
            entitlements: entitlements,
            voice: voice,
            path: path
        )
        session.onLocalTreatmentsCheck = { [treatments] in
            treatments.hasExistingTreatments
        }
        session.onCanonicalOwnerIds = { [treatments] in
            treatments.canonicalOwnerIds()
        }
        session.onBindAuthenticatedIdentity = { [treatments, syncEngine, session, family] in
            guard Self.bindingAuthorized(session: session, treatments: treatments) else { return }
            let ownerId = session.planOwnerId
            let profileId = session.planProfileId
            if let authenticatedOwnerId = session.auth.userId {
                syncEngine.activateSession(ownerId: authenticatedOwnerId)
            }
            if let authId = session.auth.userId, authId != session.localPlanOwnerId {
                treatments.adoptOwner(from: session.localPlanOwnerId, to: authId, profileId: profileId)
            }
            treatments.bindIdentity(ownerId: ownerId, profileId: profileId)
            treatments.setTimeZone(session.foundationTimeZone)
            family.applyScope(to: treatments, primaryProfileId: session.planProfileId)
            applyLoadedPlanVisibility()
        }
        session.onPhilPlanPersist = { [treatments] status in
            treatments.setPhilPlanStatus(status)
        }
        session.onPostAuthSync = { [treatments, syncEngine, session, family] in
            guard Self.bindingAuthorized(session: session, treatments: treatments) else {
                return SessionStore.UserDataRestoreResult(hasTreatments: false, failed: true)
            }
            let ownerId = session.planOwnerId
            let profileId = session.planProfileId
            if let authenticatedOwnerId = session.auth.userId {
                syncEngine.activateSession(ownerId: authenticatedOwnerId)
            }
            if let authId = session.auth.userId, authId != session.localPlanOwnerId {
                treatments.adoptOwner(from: session.localPlanOwnerId, to: authId, profileId: profileId)
            }
            treatments.bindIdentity(ownerId: ownerId, profileId: profileId)
            if profileId != session.localPlanProfileId {
                treatments.adoptProfile(from: session.localPlanProfileId, to: profileId)
            }
            treatments.setTimeZone(session.foundationTimeZone)
            let restore = await syncEngine.restoreUserData()
            if let remoteId = session.profileId, remoteId != session.localPlanProfileId {
                treatments.adoptProfile(from: session.localPlanProfileId, to: remoteId)
            }
            family.applyScope(to: treatments, primaryProfileId: session.planProfileId)
            applyLoadedPlanVisibility()
            return SessionStore.UserDataRestoreResult(
                hasTreatments: treatments.hasExistingTreatments,
                failed: restore.failed && !treatments.hasExistingTreatments
            )
        }
        if session.isSessionUnlocked {
            applyLoadedPlanVisibility()
        }
        if session.kind != .authenticated {
            _ = treatments.reconcileUnconfirmedMedicationPlan(session: session)
            session.noteLocalDataBound()
        }
        treatments.removeDuplicateMedicinesIfNeeded()
        session.startAuthIfNeeded()
    }

    private var isDebugIsolatedLaunch: Bool {
        #if DEBUG
        CapacityContractLaunch.shouldIsolateProcess
            || SeedDurableContractLaunch.shouldIsolateProcess
            || TH1LocalVerification.shouldIsolateProcess
            || IntakeVerify.shouldIsolateProcess
        #else
        false
        #endif
    }

    private func authorizeAuthenticatedBinding() -> Bool {
        Self.bindingAuthorized(session: session, treatments: treatments, isolated: isDebugIsolatedLaunch)
    }

    /// Fail closed before adoptOwner / bindIdentity / replica for a different auth user.
    /// Does not write DoseLogs or cancel reminders.
    @discardableResult
    private static func bindingAuthorized(
        session: SessionStore,
        treatments: CheckMedStore,
        isolated: Bool = false
    ) -> Bool {
        if isolated { return true }
        guard let authId = session.auth.userId else { return true }
        #if DEBUG
        if session.debugSkipInstallOwnerGuard { return true }
        #endif
        let decision = InstallAccountGuard.evaluate(
            incoming: authId,
            persistedBound: InstallAccountGuard.boundOwnerId(),
            localOwner: session.localPlanOwnerId,
            existingOwners: treatments.canonicalOwnerIds()
        )
        switch decision {
        case .allow:
            return true
        case .claim:
            session.claimInstallOwnerIfNeeded(authId)
            return true
        case .reject:
            session.noteInstallOwnerRejected()
            return false
        }
    }

    /// Show Home treatments from local SwiftData as soon as identity is bound.
    /// Replica may still run in the background; that must not keep `surfacesPlan` false.
    private func applyLoadedPlanVisibility() {
        _ = treatments.reconcileUnconfirmedMedicationPlan(session: session)
        if treatments.hasExistingTreatments {
            if !session.hasConfirmedMedicationPlan {
                session.markMedicationPlanConfirmed()
            }
            if treatments.hasActivePlan {
                treatments.setSurfacesPlan(true)
            }
        }
        session.notePlanSurfaceReady()
        if treatments.surfacesPlan {
            LaunchLog.restore("plan surface localTreatments=\(treatments.hasExistingTreatments) active=\(treatments.hasActivePlan)")
        }
    }
}
