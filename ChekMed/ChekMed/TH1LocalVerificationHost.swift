#if DEBUG
import Foundation
import SwiftUI

/// DEBUG-only Treatment History verification host.
/// Never compiles into Release. Never selected unless every activation gate matches.
enum TH1LocalVerification {
    static let requiredUDID = "D34130F1-4D47-4FC7-B14B-C19388076947"
    static let verifyFlag = "CHECKMED_TH1_VERIFY"
    static let emptyFlag = "CHECKMED_TH1_EMPTY"
    /// DEBUG-only. Runs in-memory TreatmentLifecycleContractChecks on the TH-1 host.
    /// Never selected in Release. Does not start RootView, auth, or ReminderScheduler.
    static let lifecycleContractsFlag = "CHECKMED_LIFECYCLE_CONTRACTS"
    /// DEBUG-only. Opens Treatment Detail on the isolated host with a synthetic scene.
    static let detailSceneFlag = "CHECKMED_TH2_DETAIL"
    static let detailTabFlag = "CHECKMED_TH2_TAB"
    static let fixtureOwnerId = UUID(uuidString: "D34130F1-0000-4000-8000-000000000001")!
    static let fixtureProfileId = UUID(uuidString: "D34130F1-0000-4000-8000-000000000002")!

    enum DetailScene: String {
        case completed
        case current
        case future
        case empty
    }

    /// Process environment from CoreSimulator / `SIMCTL_CHILD_*`, not assumed from the outer shell.
    static var simulatorUDID: String? {
        let env = ProcessInfo.processInfo.environment
        let raw = env["SIMULATOR_UDID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[verifyFlag] == "1"
    }

    static var wantsEmptyHistory: Bool {
        ProcessInfo.processInfo.environment[emptyFlag] == "1"
    }

    static var wantsLifecycleContracts: Bool {
        isAllowed && ProcessInfo.processInfo.environment[lifecycleContractsFlag] == "1"
    }

    static var detailScene: DetailScene? {
        guard isAllowed else { return nil }
        return DetailScene(rawValue: ProcessInfo.processInfo.environment[detailSceneFlag] ?? "")
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

    /// Flag is on but identity/runtime gates failed. Do not fall through to RootView.
    static var isMisconfiguredRequest: Bool {
        isRequested && !isAllowed
    }

    /// Isolate AppDelegate whenever the flag is present, including mismatched UDID/device.
    static var shouldIsolateProcess: Bool {
        isRequested
    }

    static func logActivation(stage: String) {
        print(
            "[TH1-VERIFY] \(stage) requested=\(isRequested) allowed=\(isAllowed) "
                + "simulatorCompile=\(isSimulatorRuntime) "
                + "simUDID=\(simulatorUDID ?? "nil") required=\(requiredUDID) "
                + "empty=\(wantsEmptyHistory)"
        )
        print("[TH1-VERIFY] skipped Auth.start bindStores SyncEngine.bind GID ReminderScheduler DEBUG contracts")
    }
}

struct TH1LocalVerificationDeniedHost: View {
    var body: some View {
        let _ = TH1LocalVerification.logActivation(stage: "DENIED")
        VStack(spacing: 16) {
            Text("TH-1 verification refused")
                .font(.headline)
            Text("Require DEBUG, CHECKMED_TH1_VERIFY=1, simulator, UDID \(TH1LocalVerification.requiredUDID).")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("Observed UDID: \(TH1LocalVerification.simulatorUDID ?? "nil")")
                .font(.caption.monospaced())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            print("[TH1-VERIFY] refuse RootView — fail closed")
        }
    }
}

struct TH1LocalVerificationHost: View {
    @Environment(SessionStore.self) private var session
    @State private var treatments: CheckMedStore
    @State private var path = NavigationPath()
    @State private var didSeed = false

    init() {
        TH1LocalVerification.logActivation(stage: "HOST INIT")
        _treatments = State(initialValue: Self.makeStore())
    }

    var body: some View {
        NavigationStack(path: $path) {
            TreatmentHistoryScreen(go: { path.append($0) })
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route, path: $path)
                }
        }
        .environment(treatments)
        .task {
            await isolateThenSeedIfNeeded()
        }
    }

    @MainActor
    private func isolateThenSeedIfNeeded() async {
        print("[TH1-VERIFY] host task begin — Auth.start must remain uncalled")
        print("[TH1-VERIFY] session.kind=\(String(describing: session.kind)) authStarted=false (bindStores skipped)")
        print("[TH1-VERIFY] supabaseConfigured=\(AuthConfig.isSupabaseConfigured) googleConfigured=\(AuthConfig.isGoogleConfigured)")
        if let url = AuthConfig.supabaseURL {
            print("[TH1-VERIFY] production URL present in Info.plist but unused: \(url.absoluteString)")
        }
        treatments.debugContractBind(
            ownerId: TH1LocalVerification.fixtureOwnerId,
            profileId: TH1LocalVerification.fixtureProfileId
        )
        if TH1LocalVerification.wantsLifecycleContracts {
            let failures = TreatmentLifecycleContractChecks.failures()
            func line(_ tag: String, _ title: String) -> String {
                let status = failures.contains { $0.contains(tag) } ? "FAIL" : "PASS"
                return "\(tag) \(status) \(title)"
            }
            let existingFailed = failures.contains { message in
                !message.contains("finish ") && !message.contains("dose ")
            }
            var rows = [
                failures.isEmpty
                    ? "TreatmentLifecycle allEmpty=true"
                    : "TreatmentLifecycle allEmpty=false count=\(failures.count)",
                line("finish A:", "two current treatments, complete selected UUID only"),
                line("finish B:", "incomplete warning excludes sibling medicines"),
                line("finish C:", "repeat complete is no-op, no duplicate XP"),
                line("finish D:", "future sibling stays future and active"),
                line("finish E:", "wrong-owner/wrong-profile refused"),
                line("finish F:", "reminder drafts keep remaining current treatment"),
                line("finish G:", "bulk completeAll still completes all active"),
                "H \(existingFailed ? "FAIL" : "PASS") existing lifecycle contracts",
                line("finish I:", "cancel is mutation-free"),
                line("finish cmd:", "success/failure follow-up"),
                line("dose A:", "scoped DoseLog query excludes sibling treatment"),
                line("dose mix:", "statuses preserved; deleted and foreign excluded"),
            ]
            rows.append(contentsOf: failures.map { "FAIL \($0)" })
            let report = rows.joined(separator: "\n")
            print("[TH1-VERIFY] lifecycle contracts\n\(report)")
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let data = Data(report.utf8)
                try? data.write(
                    to: docs.appendingPathComponent("checkmed-lifecycle-contracts.txt"),
                    options: .atomic
                )
            }
        }
        if let scene = TH1LocalVerification.detailScene {
            guard !didSeed else { return }
            didSeed = true
            let id = Self.seedTH2Scene(scene, into: treatments)
            print("[TH1-VERIFY] TH-2 scene=\(scene.rawValue) open detail \(id.uuidString)")
            path.append(AppRoute.treatmentDetail(id))
            return
        }
        guard !TH1LocalVerification.wantsEmptyHistory else {
            print("[TH1-VERIFY] empty-history mode — no fixtures inserted")
            return
        }
        guard !didSeed else { return }
        didSeed = true
        Self.seedFixturesIfNeeded(into: treatments)
    }

    private static func storeURL() -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wantsTH2Store = ProcessInfo.processInfo.environment[TH1LocalVerification.detailSceneFlag] != nil
        if wantsTH2Store {
            return folder.appendingPathComponent("th2-verify.store")
        }
        return folder.appendingPathComponent("th1-verify.store")
    }

    private static func makeStore() -> CheckMedStore {
        let url = storeURL()
        if TH1LocalVerification.wantsEmptyHistory {
            removeStoreFiles(at: url)
            UserDefaults.standard.removeObject(forKey: seedDefaultsKey)
        } else if ProcessInfo.processInfo.environment[TH1LocalVerification.detailSceneFlag] != nil {
            removeStoreFiles(at: url)
        }
        do {
            return try CheckMedStore(contractStoreURL: url)
        } catch {
            print("[TH1-VERIFY] dedicated store failed \(error) — using in-memory fallback")
            return CheckMedStore(isolatedInMemoryForContracts: true)
        }
    }

    private static func removeStoreFiles(at url: URL) {
        let extras = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ]
        for file in extras {
            try? FileManager.default.removeItem(at: file)
        }
        print("[TH1-VERIFY] cleared dedicated store at \(url.path)")
    }

    private static let seedDefaultsKey = "checkmed.th1.fixtures.v1"

    private static func seedFixturesIfNeeded(into store: CheckMedStore) {
        if UserDefaults.standard.bool(forKey: seedDefaultsKey) {
            let snapshot = store.journeyTreeSnapshot()
            let count = snapshot.current.count + snapshot.future.count + snapshot.past.count
            if count > 0 {
                print("[TH1-VERIFY] fixtures already present count=\(count)")
                return
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day: (Int, Int, Int) -> Date = { y, m, d in
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        }
        let owner = TH1LocalVerification.fixtureOwnerId
        let profile = TH1LocalVerification.fixtureProfileId

        func insert(
            title: String,
            status: String,
            start: Date,
            end: Date?,
            medicine: String
        ) -> UUID {
            let ids = store.debugInsertPlan(
                title: title,
                status: status,
                startDate: start,
                endDate: end,
                medicineName: medicine,
                ownerId: owner,
                profileId: profile
            )
            print("[TH1-VERIFY] fixture \(title) id=\(ids.treatmentId.uuidString) med=\(medicine) status=\(status)")
            return ids.treatmentId
        }

        let currentId = insert(
            title: "Current combo",
            status: "active",
            start: day(2026, 10, 5),
            end: nil,
            medicine: "Metformin"
        )
        let extra = OnboardingPrescriptionDraft(
            medicine: "Lisinopril",
            dose: "10 mg",
            frequency: "1x daily",
            duration: "30 days",
            timesPerDay: "1",
            doseTimes: ["09:00"],
            sourceText: "TH1 fixture",
            treatmentStartDate: day(2026, 10, 5)
        )
        let appended = store.addFromDrafts(
            [extra],
            ownerId: owner,
            profileId: profile,
            maximumActiveMedicines: 12
        )
        print("[TH1-VERIFY] multi-medicine append onto \(currentId.uuidString) result=\(appended?.uuidString ?? "nil")")

        _ = insert(
            title: "September course",
            status: "completed",
            start: day(2026, 9, 12),
            end: day(2026, 9, 26),
            medicine: "Amoxicilina 500mg"
        )
        _ = insert(
            title: "Accented course",
            status: "completed",
            start: day(2026, 8, 8),
            end: day(2026, 8, 22),
            medicine: "Paracétamol"
        )
        _ = insert(
            title: "Mid-year plan",
            status: "completed",
            start: day(2026, 7, 1),
            end: day(2026, 7, 14),
            medicine: "Ibuprofeno"
        )
        _ = insert(
            title: "Upcoming winter",
            status: "active",
            start: day(2026, 12, 1),
            end: nil,
            medicine: "Vitamina D"
        )
        _ = insert(
            title: "December–January",
            status: "completed",
            start: day(2025, 12, 20),
            end: day(2026, 1, 10),
            medicine: "Amoxicilina"
        )
        _ = insert(
            title: "2024 archive",
            status: "completed",
            start: day(2024, 3, 4),
            end: day(2024, 3, 18),
            medicine: "Omeprazol"
        )
        _ = insert(
            title: "2023 archive",
            status: "completed",
            start: day(2023, 6, 2),
            end: day(2023, 6, 16),
            medicine: "Losartan"
        )

        let snapshot = store.journeyTreeSnapshot()
        print(
            "[TH1-VERIFY] seeded current=\(snapshot.current.count) future=\(snapshot.future.count) past=\(snapshot.past.count)"
        )
        UserDefaults.standard.set(true, forKey: seedDefaultsKey)
    }

    @discardableResult
    private static func seedTH2Scene(
        _ scene: TH1LocalVerification.DetailScene,
        into store: CheckMedStore
    ) -> UUID {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let at: (Int, Int, Int, Int, Int) -> Date = { y, m, d, h, min in
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        let owner = TH1LocalVerification.fixtureOwnerId
        let profile = TH1LocalVerification.fixtureProfileId
        let foreignOwner = UUID(uuidString: "D34130F1-0000-4000-8000-000000000099")!
        let foreignProfile = UUID(uuidString: "D34130F1-0000-4000-8000-000000000098")!

        func plan(
            title: String,
            status: String,
            start: Date,
            end: Date?,
            medicine: String,
            ownerId: UUID = owner,
            profileId: UUID = profile
        ) -> (treatmentId: UUID, medicineId: UUID) {
            let ids = store.debugInsertPlan(
                title: title,
                status: status,
                startDate: start,
                endDate: end,
                medicineName: medicine,
                ownerId: ownerId,
                profileId: profileId
            )
            return (ids.treatmentId, ids.medicineId)
        }

        func extraMedicine(on treatmentId: UUID, name: String, time: String = "08:00") {
            _ = store.debugInsertMedicine(
                treatmentId: treatmentId,
                name: name,
                ownerId: owner,
                profileId: profile,
                scheduleTime: time
            )
        }

        switch scene {
        case .completed:
            let start = at(2026, 9, 26, 12, 0)
            let end = at(2026, 10, 3, 12, 0)
            let row = plan(
                title: "September combo",
                status: "completed",
                start: start,
                end: end,
                medicine: "Amoxicilina 500mg"
            )
            extraMedicine(on: row.treatmentId, name: "Ibuprofeno 400mg")
            for day in [30, 1, 2, 3] {
                let month = day >= 26 ? 9 : 10
                let scheduled = at(2026, month == 9 && day >= 26 ? 9 : 10, day == 30 ? 30 : day, 8, 0)
                let confirmed = at(2026, month == 9 && day >= 26 ? 9 : 10, day == 30 ? 30 : day, 8, 12)
                _ = store.debugInsertDoseLog(
                    treatmentId: row.treatmentId,
                    medicineName: "Amoxicilina 500mg",
                    scheduledAt: scheduled,
                    status: DoseLogStatus.taken.rawValue,
                    loggedAt: confirmed,
                    ownerId: owner,
                    profileId: profile
                )
                _ = store.debugInsertDoseLog(
                    treatmentId: row.treatmentId,
                    medicineName: "Ibuprofeno 400mg",
                    scheduledAt: scheduled,
                    status: DoseLogStatus.taken.rawValue,
                    loggedAt: confirmed,
                    ownerId: owner,
                    profileId: profile
                )
            }
            _ = store.debugInsertDoseLog(
                treatmentId: row.treatmentId,
                medicineName: "Amoxicilina 500mg",
                scheduledAt: at(2026, 10, 2, 8, 0),
                status: DoseLogStatus.taken.rawValue,
                loggedAt: at(2026, 10, 2, 8, 5),
                deletedAt: at(2026, 10, 2, 9, 0),
                ownerId: owner,
                profileId: profile
            )
            print("[TH1-VERIFY] TH-2 completed id=\(row.treatmentId.uuidString)")
            return row.treatmentId

        case .current:
            let start = at(2026, 10, 5, 12, 0)
            let row = plan(
                title: "Current combo",
                status: "active",
                start: start,
                end: at(2026, 11, 5, 12, 0),
                medicine: "Metformin"
            )
            extraMedicine(on: row.treatmentId, name: "Lisinopril", time: "20:00")
            _ = store.debugInsertDoseLog(
                treatmentId: row.treatmentId,
                medicineName: "Metformin",
                scheduledAt: at(2026, 10, 10, 8, 0),
                status: DoseLogStatus.taken.rawValue,
                loggedAt: at(2026, 10, 10, 8, 4),
                ownerId: owner,
                profileId: profile
            )
            _ = store.debugInsertDoseLog(
                treatmentId: row.treatmentId,
                medicineName: "Lisinopril",
                scheduledAt: at(2026, 10, 10, 20, 0),
                status: DoseLogStatus.takenLate.rawValue,
                loggedAt: at(2026, 10, 10, 21, 10),
                ownerId: owner,
                profileId: profile
            )
            _ = store.debugInsertDoseLog(
                treatmentId: row.treatmentId,
                medicineName: "Metformin",
                scheduledAt: at(2026, 10, 11, 8, 0),
                status: DoseLogStatus.missed.rawValue,
                ownerId: owner,
                profileId: profile
            )
            _ = store.debugInsertDoseLog(
                treatmentId: row.treatmentId,
                medicineName: "Lisinopril",
                scheduledAt: at(2026, 10, 11, 20, 0),
                status: DoseLogStatus.skipped.rawValue,
                ownerId: owner,
                profileId: profile
            )
            _ = store.debugInsertDoseLog(
                treatmentId: row.treatmentId,
                medicineName: "Metformin",
                scheduledAt: at(2026, 10, 12, 8, 0),
                status: DoseLogStatus.pending.rawValue,
                ownerId: owner,
                profileId: profile
            )
            _ = store.debugInsertDoseLog(
                treatmentId: row.treatmentId,
                medicineName: "Lisinopril",
                scheduledAt: at(2026, 10, 20, 8, 0),
                status: DoseLogStatus.pending.rawValue,
                ownerId: owner,
                profileId: profile
            )
            let sibling = plan(
                title: "Sibling course",
                status: "active",
                start: start,
                end: nil,
                medicine: "SiblingMed"
            )
            _ = store.debugInsertDoseLog(
                treatmentId: sibling.treatmentId,
                medicineName: "SiblingMed",
                scheduledAt: at(2026, 10, 11, 9, 0),
                status: DoseLogStatus.taken.rawValue,
                loggedAt: at(2026, 10, 11, 9, 1),
                ownerId: owner,
                profileId: profile
            )
            _ = store.debugInsertDoseLog(
                treatmentId: row.treatmentId,
                medicineName: "Metformin",
                scheduledAt: at(2026, 10, 11, 8, 0),
                status: DoseLogStatus.taken.rawValue,
                loggedAt: at(2026, 10, 11, 8, 1),
                ownerId: foreignOwner,
                profileId: foreignProfile
            )
            print("[TH1-VERIFY] TH-2 current id=\(row.treatmentId.uuidString)")
            return row.treatmentId

        case .future:
            let row = plan(
                title: "Upcoming winter",
                status: "active",
                start: at(2026, 12, 1, 12, 0),
                end: at(2026, 12, 31, 12, 0),
                medicine: "Vitamina D"
            )
            print("[TH1-VERIFY] TH-2 future id=\(row.treatmentId.uuidString)")
            return row.treatmentId

        case .empty:
            let row = plan(
                title: "Empty doses plan",
                status: "active",
                start: at(2026, 10, 1, 12, 0),
                end: at(2026, 10, 31, 12, 0),
                medicine: "Omeprazol"
            )
            print("[TH1-VERIFY] TH-2 empty-doses id=\(row.treatmentId.uuidString)")
            return row.treatmentId
        }
    }
}
#endif
