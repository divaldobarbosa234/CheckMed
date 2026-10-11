import GoogleSignIn
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let clientID = AuthConfig.googleClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        ReminderScheduler.shared.configure()
        #if DEBUG
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
            let journeyTreeFailures = TreatmentJourneyClassificationContractChecks.failures()
            let lifecycleFailures = await MainActor.run { TreatmentLifecycleContractChecks.failures() }
            let capacitySafetyFailures = await MainActor.run { MedicationCapacitySafetyContractChecks.failures() }
            let titleFailures = await MainActor.run { TreatmentTitleContractChecks.failures() }
            let missedAckFailures = await MainActor.run { MissedDosePresentationContractChecks.failures() }
            let skippedLabelFailures = CompletedSkippedLabelContractChecks.failures()
            let welcomeFailures = OnboardingWelcomeContractChecks.failures()
            let superTrialFailures = SuperTrialContractChecks.failures()
            let clockFailures = CheckMedClockContractChecks.failures()
            let rewardFailures = RewardEngineContractChecks.failures()
            let syncTransportFailures = await SyncTransportContractChecks.failures()
            let syncOutboxFailures = await SyncOutboxContractChecks.failures()
            let syncProtocolFailures = await SyncProtocolContractChecks.failures()
            let failures = doseFailures + gamificationFailures + journeyFailures + weeklyFailures + streakFailures + philFailures + prescriptionDateFailures + laterAddFailures + journeyTreeFailures + lifecycleFailures + capacitySafetyFailures + titleFailures + missedAckFailures + skippedLabelFailures + welcomeFailures + superTrialFailures + clockFailures + rewardFailures + syncTransportFailures + syncOutboxFailures + syncProtocolFailures
            print("DoseLoop failures:", doseFailures)
            print("Gamification failures:", gamificationFailures)
            print("DailyJourney failures:", journeyFailures)
            print("WeeklyProgress failures:", weeklyFailures)
            print("Streak failures:", streakFailures)
            print("PhilCoach failures:", philFailures)
            print("PrescriptionDate failures:", prescriptionDateFailures)
            print("LaterAddPersist failures:", laterAddFailures)
            print("JourneyTree failures:", journeyTreeFailures)
            print("TreatmentLifecycle failures:", lifecycleFailures)
            print("MedicationCapacitySafety failures:", capacitySafetyFailures)
            print("TreatmentTitle failures:", titleFailures)
            print("MissedDosePresentation failures:", missedAckFailures)
            print("CompletedSkippedLabel failures:", skippedLabelFailures)
            print("OnboardingWelcome failures:", welcomeFailures)
            print("SuperTrial failures:", superTrialFailures)
            print("TestClock failures:", clockFailures)
            print("RewardEngine failures:", rewardFailures)
            print("SyncTransport failures:", syncTransportFailures)
            print("SyncOutbox failures:", syncOutboxFailures)
            print("SyncProtocol failures:", syncProtocolFailures)
            let report = [
                "DoseLoop failures: \(doseFailures)",
                "Gamification failures: \(gamificationFailures)",
                "DailyJourney failures: \(journeyFailures)",
                "WeeklyProgress failures: \(weeklyFailures)",
                "Streak failures: \(streakFailures)",
                "PhilCoach failures: \(philFailures)",
                "PrescriptionDate failures: \(prescriptionDateFailures)",
                "LaterAddPersist failures: \(laterAddFailures)",
                "JourneyTree failures: \(journeyTreeFailures)",
                "TreatmentLifecycle failures: \(lifecycleFailures)",
                "MedicationCapacitySafety failures: \(capacitySafetyFailures)",
                "TreatmentTitle failures: \(titleFailures)",
                "MissedDosePresentation failures: \(missedAckFailures)",
                "CompletedSkippedLabel failures: \(skippedLabelFailures)",
                "OnboardingWelcome failures: \(welcomeFailures)",
                "SuperTrial failures: \(superTrialFailures)",
                "TestClock failures: \(clockFailures)",
                "RewardEngine failures: \(rewardFailures)",
                "SyncTransport failures: \(syncTransportFailures)",
                "SyncOutbox failures: \(syncOutboxFailures)",
                "SyncProtocol failures: \(syncProtocolFailures)",
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
                    lifecycleFailures.isEmpty ? nil : "TREATMENT LIFECYCLE FAILURE: \(lifecycleFailures.joined(separator: "; "))",
                    capacitySafetyFailures.isEmpty ? nil : "MEDICATION CAPACITY SAFETY FAILURE: \(capacitySafetyFailures.joined(separator: "; "))",
                    titleFailures.isEmpty ? nil : "TREATMENT TITLE FAILURE: \(titleFailures.joined(separator: "; "))",
                    missedAckFailures.isEmpty ? nil : "MISSED DOSE PRESENTATION FAILURE: \(missedAckFailures.joined(separator: "; "))",
                    skippedLabelFailures.isEmpty ? nil : "COMPLETED SKIPPED LABEL FAILURE: \(skippedLabelFailures.joined(separator: "; "))",
                    welcomeFailures.isEmpty ? nil : "ONBOARDING WELCOME FAILURE: \(welcomeFailures.joined(separator: "; "))",
                    superTrialFailures.isEmpty ? nil : "SUPER TRIAL FAILURE: \(superTrialFailures.joined(separator: "; "))",
                    clockFailures.isEmpty ? nil : "TEST CLOCK FAILURE: \(clockFailures.joined(separator: "; "))",
                    journeyTreeFailures.isEmpty ? nil : "JOURNEY TREE FAILURE: \(journeyTreeFailures.joined(separator: "; "))",
                    rewardFailures.isEmpty ? nil : "REWARD ENGINE FAILURE: \(rewardFailures.joined(separator: "; "))",
                    syncTransportFailures.isEmpty ? nil : "SYNC TRANSPORT FAILURE: \(syncTransportFailures.joined(separator: "; "))",
                    syncOutboxFailures.isEmpty ? nil : "SYNC OUTBOX FAILURE: \(syncOutboxFailures.joined(separator: "; "))",
                    syncProtocolFailures.isEmpty ? nil : "SYNC PROTOCOL FAILURE: \(syncProtocolFailures.joined(separator: "; "))",
                ].compactMap { $0 }.joined(separator: " | ")
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
    @State private var treatments = CheckMedStore()
    @State private var path = TodayPathStore()
    @State private var entitlements = EntitlementStore()
    @State private var syncEngine = SyncEngine()
    @State private var family = FamilyStore()
    @State private var voice = PhilVoice()

    var body: some Scene {
        WindowGroup {
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
                    treatments.bindIdentity(ownerId: session.planOwnerId, profileId: profileId)
                    family.applyScope(to: treatments, primaryProfileId: session.planProfileId)
                }
                .onChange(of: session.timeZoneName) { _, _ in
                    treatments.setTimeZone(session.foundationTimeZone)
                    ReminderScheduler.shared.reschedule(force: true)
                }
                .onChange(of: session.locale) { _, _ in
                    ReminderScheduler.shared.reschedule(force: true)
                }
                .onChange(of: entitlements.isSuper) { _, isSuper in
                    if !isSuper {
                        family.selectPrimary()
                        family.applyScope(to: treatments, primaryProfileId: session.planProfileId)
                    }
                    ReminderScheduler.shared.reschedule(force: true)
                }
        }
    }

    private func bindStores() {
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
        session.onBindAuthenticatedIdentity = { [treatments, syncEngine, session, family] in
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
