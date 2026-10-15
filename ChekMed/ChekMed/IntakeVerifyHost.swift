#if DEBUG
import Foundation
import SwiftUI

/// DEBUG-only SwiftUI intake verification host.
/// Never compiles into Release. Never selected unless every activation gate matches.
/// Does not replace `CHECKMED_TH1_VERIFY`. TH-1 remains first in AppDelegate and WindowGroup.
enum IntakeVerify {
    static let requiredUDID = TH1LocalVerification.requiredUDID
    static let verifyFlag = "CHECKMED_INTAKE_VERIFY"
    static let sceneFlag = "CHECKMED_INTAKE_VERIFY_SCENE"
    static let fixtureOwnerId = UUID(uuidString: "D34130F1-0000-4000-8000-000000000011")!
    static let fixtureProfileId = UUID(uuidString: "D34130F1-0000-4000-8000-000000000012")!
    static let fixtureFamilyProfileId = UUID(uuidString: "D34130F1-0000-4000-8000-000000000013")!
    static let fixtureLogId = UUID(uuidString: "D34130F1-0000-4000-8000-000000000021")!

    static var simulatorUDID: String? {
        let env = ProcessInfo.processInfo.environment
        let raw = env["SIMULATOR_UDID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[verifyFlag] == "1"
    }

    /// Optional auto-open scene. DEBUG host only. Never read in Release.
    static var autoSceneRaw: String? {
        guard isAllowed else { return nil }
        let raw = ProcessInfo.processInfo.environment[sceneFlag]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    static var isSimulatorRuntime: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Fail closed: DEBUG + flag + simulator compile + exact CoreSimulator UDID.
    static var isAllowed: Bool {
        #if targetEnvironment(simulator)
        isRequested && simulatorUDID == requiredUDID
        #else
        false
        #endif
    }

    static var isMisconfiguredRequest: Bool {
        isRequested && !isAllowed
    }

    /// Isolate AppDelegate whenever the flag is present, including mismatched UDID/device.
    static var shouldIsolateProcess: Bool {
        isRequested
    }

    static func logActivation(stage: String) {
        print(
            "[INTAKE-VERIFY] \(stage) requested=\(isRequested) allowed=\(isAllowed) "
                + "simulatorCompile=\(isSimulatorRuntime) "
                + "simUDID=\(simulatorUDID ?? "nil") required=\(requiredUDID)"
        )
        print("[INTAKE-VERIFY] skipped Auth.start bindStores SyncEngine.bind GID ReminderScheduler DEBUG contracts")
        print("[INTAKE-VERIFY] TH-1 requested=\(TH1LocalVerification.isRequested) — TH-1 still wins if both flags are set")
        print("[INTAKE-VERIFY] autoScene=\(autoSceneRaw ?? "nil")")
    }

    static func fixtureDay() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 8))!
    }
}

struct IntakeVerifyDeniedHost: View {
    var body: some View {
        let _ = IntakeVerify.logActivation(stage: "DENIED")
        VStack(spacing: 12) {
            Text("Intake verification denied")
                .font(.headline)
            Text("Require DEBUG, CHECKMED_INTAKE_VERIFY=1, simulator, UDID \(IntakeVerify.requiredUDID).")
                .multilineTextAlignment(.center)
            Text("Observed UDID: \(IntakeVerify.simulatorUDID ?? "nil")")
                .font(.caption.monospaced())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .accessibilityIdentifier("intake-verify-denied")
    }
}

private enum IntakeVerifyScene: String, Identifiable {
    case returningAdd
    case returningStartNew
    case firstTime
    case unfinishedResume
    case forceSaveFail
    case freeOneSlot
    case freeAtCap
    case inspectTree

    var id: String { rawValue }
}

private enum IntakeVerifyPresented: Identifiable {
    case intake
    case resume

    var id: String {
        switch self {
        case .intake: "intake"
        case .resume: "resume"
        }
    }
}

struct IntakeVerifyHost: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(TodayPathStore.self) private var path

    private static var didAutoOpenThisProcess = false

    @State private var treatments: CheckMedStore
    @State private var presented: IntakeVerifyPresented?
    @State private var lastScene: IntakeVerifyScene?
    @State private var lastNavigation = "none"
    @State private var inspectText = ""
    /// True only after the unfinished resume queue reached the Dr. Cooper ready screen.
    @State private var resumeReachedReady = false
    /// One-shot so SwiftUI cannot dismiss the resume cover twice.
    @State private var didDismissResumeCompletion = false

    init() {
        IntakeVerify.logActivation(stage: "HOST INIT")
        _treatments = State(initialValue: CheckMedStore(isolatedInMemoryForContracts: true))
    }

    var body: some View {
        Group {
            if presented == nil {
                hub
            } else {
                CheckMedTheme.background.ignoresSafeArea()
            }
        }
        .environment(treatments)
        .onAppear {
            if inspectText.isEmpty {
                session.debugBindIntakeVerification(
                    ownerId: IntakeVerify.fixtureOwnerId,
                    profileId: IntakeVerify.fixtureProfileId,
                    onboarded: true,
                    planConfirmed: true
                )
                inspectText = snapshot()
            }
            if !Self.didAutoOpenThisProcess, let raw = IntakeVerify.autoSceneRaw, let scene = IntakeVerifyScene(rawValue: raw) {
                Self.didAutoOpenThisProcess = true
                begin(scene)
            }
        }
        .fullScreenCover(item: $presented) { item in
            switch item {
            case .intake:
                AddPrescriptionIntakeHost(
                    onFinished: {
                        lastNavigation = "post-journey (first-time/unfinished)"
                        presented = nil
                        inspectText = snapshot()
                    },
                    onCancel: {
                        lastNavigation = "cancelled"
                        presented = nil
                    }
                )
                .environment(session)
                .environment(treatments)
                .environment(path)
                .environment(entitlements)
            case .resume:
                ResumePlanSetupFlow()
                    .environment(session)
                    .environment(treatments)
                    .environment(path)
                    .environment(entitlements)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { entitlements.showPaywall },
            set: { entitlements.showPaywall = $0 }
        )) {
            PaywallView()
                .environment(session)
                .environment(entitlements)
        }
        .onChange(of: presented) { _, newValue in
            if newValue == nil {
                inspectText = snapshot()
            }
        }
        .onChange(of: session.postJourneyStep) { _, step in
            guard presented == .resume, lastScene == .unfinishedResume else { return }
            if step == .philReady {
                resumeReachedReady = true
            }
            dismissResumeCoverIfGenuinelyComplete()
        }
        .onChange(of: session.showResumeSetup) { _, _ in
            dismissResumeCoverIfGenuinelyComplete()
        }
    }

    /// Dismiss only after GO TO HOME (`finishResumeSetup`), never on Confirm Back
    /// (`showResumeSetup = false` without reaching ready) and never for Add / Start New covers.
    private func dismissResumeCoverIfGenuinelyComplete() {
        guard presented == .resume, lastScene == .unfinishedResume else { return }
        guard resumeReachedReady else { return }
        guard session.showResumeSetup == false else { return }
        guard !didDismissResumeCompletion else { return }
        didDismissResumeCompletion = true
        lastNavigation = "resume finished → hub"
        presented = nil
        inspectText = snapshot()
        print("[INTAKE-VERIFY] resume finished → hub")
    }

    private var hub: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DEBUG intake verification")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .accessibilityIdentifier("intake-verify-hub")
                    Text(
                        "In-memory store only. Real AddPrescriptionIntakeHost / ResumePlanSetupFlow. "
                            + "No production Supabase, Auth.start, or ReminderScheduler.configure."
                    )
                    .font(.footnote)
                    .foregroundStyle(CheckMedTheme.muted)
                    Text("isSuper=\(entitlements.isSuper ? "true" : "false") (forced free in this host)")
                        .font(.caption.monospaced())
                    sceneButton("A/B Returning add (CURRENT)", .returningAdd)
                    sceneButton("C Returning Start New (CURRENT+FUTURE)", .returningStartNew)
                    sceneButton("D First-time empty", .firstTime)
                    sceneButton("E Unfinished resume", .unfinishedResume)
                    sceneButton("F Force canonical save failure", .forceSaveFail)
                    sceneButton("G Free, one slot left (2 medicines)", .freeOneSlot)
                    sceneButton("H Free at capacity (3 medicines)", .freeAtCap)
                    sceneButton("J Seed inspect tree (family + DoseLog)", .inspectTree)
                    Button("Refresh inspect") { inspectText = snapshot() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("intake-verify-refresh-inspect")
                    Text("lastNavigation=\(lastNavigation)")
                        .font(.caption.monospaced())
                        .accessibilityIdentifier("intake-verify-last-nav")
                    Text(inspectText)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("intake-verify-inspect")
                }
                .padding(20)
            }
            .background(CheckMedTheme.background)
            .navigationTitle("Intake verify")
        }
    }

    private func sceneButton(_ title: String, _ scene: IntakeVerifyScene) -> some View {
        Button(title) {
            begin(scene)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("intake-verify-scene-\(scene.rawValue)")
    }

    private func begin(_ scene: IntakeVerifyScene) {
        let store = CheckMedStore(isolatedInMemoryForContracts: true)
        treatments = store
        lastScene = scene
        lastNavigation = "none"
        resumeReachedReady = false
        didDismissResumeCompletion = false
        entitlements.showPaywall = false
        store.debugFailNextCanonicalSave = false
        seed(scene, store: store)
        inspectText = snapshot()
        switch scene {
        case .inspectTree:
            presented = nil
            lastNavigation = "inspect only"
        case .unfinishedResume:
            lastNavigation = "opened resume"
            presented = .resume
        default:
            lastNavigation = "opened intake"
            presented = .intake
        }
    }

    private func seed(_ scene: IntakeVerifyScene, store: CheckMedStore) {
        let owner = IntakeVerify.fixtureOwnerId
        let profile = IntakeVerify.fixtureProfileId
        let family = IntakeVerify.fixtureFamilyProfileId
        let day = IntakeVerify.fixtureDay()
        let futureStart = day.addingTimeInterval(14 * 24 * 60 * 60)
        let end = day.addingTimeInterval(7 * 24 * 60 * 60)

        func bind(onboarded: Bool, planConfirmed: Bool) {
            store.debugContractBind(ownerId: owner, profileId: profile)
            session.debugBindIntakeVerification(
                ownerId: owner,
                profileId: profile,
                onboarded: onboarded,
                planConfirmed: planConfirmed
            )
        }

        func current(
            medicines: [String],
            logStatus: String? = "taken"
        ) {
            let first = medicines[0]
            let inserted = store.debugInsertPlan(
                title: "Verify Current",
                status: "active",
                startDate: day,
                endDate: end,
                medicineName: first,
                ownerId: owner,
                profileId: profile,
                scheduleTime: "08:00",
                logStatus: logStatus,
                logScheduledAt: day,
                logId: IntakeVerify.fixtureLogId
            )
            for name in medicines.dropFirst() {
                store.debugInsertMedicine(
                    treatmentId: inserted.treatmentId,
                    name: name,
                    ownerId: owner,
                    profileId: profile,
                    scheduleTime: "20:00"
                )
            }
        }

        switch scene {
        case .returningAdd, .forceSaveFail:
            bind(onboarded: true, planConfirmed: true)
            current(medicines: ["CurrentMed"])
            store.debugFailNextCanonicalSave = (scene == .forceSaveFail)
        case .returningStartNew:
            bind(onboarded: true, planConfirmed: true)
            current(medicines: ["CurrentMed"])
            store.debugInsertPlan(
                title: "Verify Future",
                status: "active",
                startDate: futureStart,
                endDate: futureStart.addingTimeInterval(7 * 24 * 60 * 60),
                medicineName: "FutureMed",
                ownerId: owner,
                profileId: profile,
                scheduleTime: "09:00"
            )
        case .firstTime:
            bind(onboarded: false, planConfirmed: false)
        case .unfinishedResume:
            bind(onboarded: false, planConfirmed: false)
            current(medicines: ["UnfinishedMed"], logStatus: nil)
            session.showResumeSetup = true
        case .freeOneSlot:
            bind(onboarded: true, planConfirmed: true)
            current(medicines: ["CurrentMed", "CurrentMed2"])
        case .freeAtCap:
            bind(onboarded: true, planConfirmed: true)
            current(medicines: ["CurrentMed", "CurrentMed2", "CurrentMed3"])
        case .inspectTree:
            // Insert the extra-profile row while the store is unbound so `stamp()`
            // cannot rewrite it onto the selected profile (writeProfileId is nil).
            store.debugInsertPlan(
                title: "Family Extra",
                status: "active",
                startDate: day,
                endDate: end,
                medicineName: "FamilyExtra",
                ownerId: owner,
                profileId: family,
                scheduleTime: "08:00"
            )
            bind(onboarded: true, planConfirmed: true)
            current(medicines: ["CurrentMed"])
            store.debugInsertPlan(
                title: "Verify Future",
                status: "active",
                startDate: futureStart,
                endDate: futureStart.addingTimeInterval(7 * 24 * 60 * 60),
                medicineName: "FutureMed",
                ownerId: owner,
                profileId: profile,
                scheduleTime: "09:00"
            )
        }
        print("[INTAKE-VERIFY] seeded scene=\(scene.rawValue) failNext=\(store.debugFailNextCanonicalSave)")
        print("[INTAKE-VERIFY] \(snapshot())")
    }

    private func snapshot() -> String {
        let counts = treatments.debugLiveRecordCounts()
        let treatmentsDump = treatments.treatmentSnapshots()
            .map { "t[\($0.status)] \($0.title) profile=\($0.profileId?.uuidString ?? "nil")" }
            .joined(separator: " | ")
        let medicinesDump = treatments.medicineSnapshots()
            .map { "m:\($0.name) profile=\($0.profileId?.uuidString ?? "nil")" }
            .joined(separator: " | ")
        let familyAllSame = treatments.debugLiveMedicationRowsMatch(
            ownerId: IntakeVerify.fixtureOwnerId,
            profileId: IntakeVerify.fixtureProfileId
        )
        return [
            "scene=\(lastScene?.rawValue ?? "none")",
            "onboarded=\(session.hasCompletedOnboarding) planConfirmed=\(session.hasConfirmedMedicationPlan)",
            "owner=\(session.planOwnerId.uuidString)",
            "hasCurrent=\(treatments.hasCurrentTreatment) scopedLiveMeds=\(treatments.storedMedicineCount)",
            "allCounts t=\(counts.treatments) m=\(counts.medicines) s=\(counts.schedules) logs=\(counts.logs)",
            "doseLog=\(treatments.debugDoseStatus(IntakeVerify.fixtureLogId) ?? "nil")",
            "allRowsSamePrimaryProfile=\(familyAllSame)",
            "failNext=\(treatments.debugFailNextCanonicalSave)",
            treatmentsDump.isEmpty ? "treatments=(none)" : treatmentsDump,
            medicinesDump.isEmpty ? "medicines=(none)" : medicinesDump,
        ].joined(separator: "\n")
    }
}
#endif
