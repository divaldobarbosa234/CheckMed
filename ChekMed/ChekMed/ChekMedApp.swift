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
            try? await Task.sleep(nanoseconds: 400_000_000)
            let failures = DoseLoopContractChecks.failures()
            assert(failures.isEmpty, "Dose loop checks failed: \(failures.joined(separator: "; "))")
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
                    treatments.pruneDuplicateAndFreeCap(isSuper: isSuper)
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
        syncEngine.bind(store: treatments, session: session)
        syncEngine.bindFamily(family)
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
            voice: voice
        )
        session.onLocalTreatmentsCheck = { [treatments] in
            treatments.hasExistingTreatments
        }
        session.onBindAuthenticatedIdentity = { [treatments, session, family] in
            let ownerId = session.planOwnerId
            let profileId = session.planProfileId
            if let authId = session.auth.userId, authId != session.localPlanOwnerId {
                treatments.adoptOwner(from: session.localPlanOwnerId, to: authId, profileId: profileId)
            }
            treatments.bindIdentity(ownerId: ownerId, profileId: profileId)
            treatments.setTimeZone(session.foundationTimeZone)
            family.applyScope(to: treatments, primaryProfileId: session.planProfileId)
        }
        session.onPhilPlanPersist = { [treatments] status in
            treatments.setPhilPlanStatus(status)
        }
        session.onPostAuthSync = { [treatments, syncEngine, session, family] in
            let ownerId = session.planOwnerId
            let profileId = session.planProfileId
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
            _ = treatments.reconcileUnconfirmedMedicationPlan(session: session)
            if treatments.hasExistingTreatments {
                session.markMedicationPlanConfirmed()
                treatments.setSurfacesPlan(true)
            }
            return SessionStore.UserDataRestoreResult(
                hasTreatments: treatments.hasExistingTreatments,
                failed: restore.failed && !treatments.hasExistingTreatments
            )
        }
        if session.kind != .authenticated {
            _ = treatments.reconcileUnconfirmedMedicationPlan(session: session)
            session.noteLocalDataBound()
        }
        treatments.pruneDuplicateAndFreeCap(isSuper: entitlements.isSuper)
        session.startAuthIfNeeded()
    }
}
