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
                    if session.kind == .authenticated {
                        Task { await syncEngine.syncIfSignedIn() }
                    }
                }
                .onChange(of: session.profileId) { _, _ in
                    bindStores()
                }
                .onChange(of: session.timeZoneName) { _, _ in
                    treatments.setTimeZone(session.foundationTimeZone)
                    ReminderScheduler.shared.reschedule()
                }
                .onChange(of: session.locale) { _, _ in
                    ReminderScheduler.shared.reschedule()
                }
                .onChange(of: entitlements.isSuper) { _, isSuper in
                    if !isSuper {
                        family.selectPrimary()
                        family.applyScope(to: treatments, primaryProfileId: session.planProfileId)
                    }
                    treatments.pruneDuplicateAndFreeCap(isSuper: isSuper)
                    ReminderScheduler.shared.reschedule()
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
            path.reload()
            ReminderScheduler.shared.reschedule()
        }
        ReminderScheduler.shared.bind(
            store: treatments,
            session: session,
            entitlements: entitlements,
            voice: voice
        )
        session.onPostAuthSync = { [treatments, syncEngine, session, family] in
            let ownerId = session.planOwnerId
            let profileId = session.planProfileId
            if let authId = session.auth.userId, authId != session.localPlanOwnerId {
                treatments.adoptOwner(from: session.localPlanOwnerId, to: authId, profileId: profileId)
            }
            treatments.bindIdentity(ownerId: ownerId, profileId: profileId)
            treatments.setTimeZone(session.foundationTimeZone)
            await syncEngine.syncIfSignedIn()
            family.applyScope(to: treatments, primaryProfileId: profileId)
            let purged = treatments.reconcileUnconfirmedMedicationPlan(session: session)
            if purged {
                await syncEngine.syncIfSignedIn()
            }
            return treatments.hasExistingTreatments
        }
        // Local / guest path: reconcile without waiting for auth sync.
        _ = treatments.reconcileUnconfirmedMedicationPlan(session: session)
        path.reload()
        treatments.pruneDuplicateAndFreeCap(isSuper: entitlements.isSuper)
        ReminderScheduler.shared.reschedule()
        session.startAuthIfNeeded()
    }
}
