import Foundation
import Supabase

private struct ReplicaPhilSnap: Sendable {
    var status: String
    var updatedAt: Date
}

private struct ReplicaPayload: Sendable {
    var treatments: [TreatmentSnapshot]
    var medicines: [MedicineSnapshot]
    var schedules: [DoseScheduleSnapshot]
    var logs: [DoseLogSnapshot]
    var phil: ReplicaPhilSnap?
}

private struct ReplicaPushPayload: Sendable {
    var treatments: [RemoteTreatment]
    var medicines: [RemoteMedicine]
    var schedules: [RemoteSchedule]
    var logs: [RemoteLog]
}

@MainActor
enum SyncTransportCycle {
    static func run<Payload>(
        pull: () async throws -> Payload,
        push: (Payload) async throws -> Void
    ) async throws {
        let payload = try await pull()
        try await push(payload)
    }
}

@MainActor
final class SyncCycleCoordinator {
    struct Request: Equatable {
        var logSince: Date?
        var shouldPush: Bool
    }

    typealias Runner = @MainActor (Request) async -> Bool

    private let runner: Runner
    private var inFlight: Task<Bool, Never>?
    private var queuedRequest: Request?

    init(runner: @escaping Runner) {
        self.runner = runner
    }

    func enqueue(_ request: Request) -> Task<Bool, Never> {
        if let inFlight {
            queuedRequest = Self.merged(queuedRequest, request)
            return inFlight
        }
        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.drain(startingWith: request)
        }
        inFlight = task
        return task
    }

    private func drain(startingWith initial: Request) async -> Bool {
        var request = initial
        var allSucceeded = true
        while true {
            allSucceeded = await runner(request) && allSucceeded
            guard let next = queuedRequest else {
                inFlight = nil
                return allSucceeded
            }
            queuedRequest = nil
            request = next
        }
    }

    private static func merged(_ queued: Request?, _ incoming: Request) -> Request {
        guard let queued else { return incoming }
        let logSince: Date?
        switch (queued.logSince, incoming.logSince) {
        case let (.some(lhs), .some(rhs)):
            logSince = min(lhs, rhs)
        default:
            // `nil` requests the complete log replica and therefore dominates.
            logSince = nil
        }
        return Request(
            logSince: logSince,
            shouldPush: queued.shouldPush || incoming.shouldPush
        )
    }
}

private enum SyncEngineError: LocalizedError {
    case missingStore
    case missingClient
    case missingOwner
    case missingProfile
    case sessionChanged

    var errorDescription: String? {
        switch self {
        case .missingStore: "Sync store unavailable"
        case .missingClient: "Sync client unavailable"
        case .missingOwner: "Sync owner unavailable"
        case .missingProfile: "Sync profile unavailable"
        case .sessionChanged: "Sync session changed"
        }
    }
}

/// Last-write-wins replica of local SwiftData. Auth required. Screens do not call this.
@Observable
@MainActor
final class SyncEngine {
    struct RestoreOutcome {
        var hasTreatments: Bool
        var failed: Bool
    }

    @ObservationIgnored
    private weak var store: CheckMedStore?
    @ObservationIgnored
    private weak var session: SessionStore?
    @ObservationIgnored
    private weak var family: FamilyStore?
    private var lastSyncSucceeded = true
    @ObservationIgnored
    private lazy var cycleCoordinator = SyncCycleCoordinator { [weak self] request in
        guard let self else { return false }
        return await self.runSync(
            logSince: request.logSince,
            shouldPush: request.shouldPush
        )
    }

    func bind(store: CheckMedStore, session: SessionStore) {
        self.store = store
        self.session = session
        store.onNeedsSync = { [weak self] in
            guard let self else { return }
            await self.syncIfSignedIn()
        }
    }

    /// Await the replica pull. Network runs off MainActor; results are applied here.
    /// Failed fetch keeps local cache. Empty local + failed fetch → `failed`.
    func restoreUserData() async -> RestoreOutcome {
        guard let store else {
            LaunchLog.error("restore: store missing")
            return RestoreOutcome(hasTreatments: false, failed: true)
        }

        let hadLocal = store.hasExistingTreatments
        LaunchLog.data("restore start localTreatments=\(hadLocal)")
        let ok = await cycleCoordinator.enqueue(
            SyncCycleCoordinator.Request(
                logSince: Date().addingTimeInterval(-8 * 86_400),
                shouldPush: false
            )
        ).value
        let has = store.hasExistingTreatments || hadLocal
        if ok {
            LaunchLog.data(has ? "restore loadedWithData" : "restore loadedWithNoData")
        } else {
            LaunchLog.error("restore pull failed keepLocal=\(has)")
        }
        return RestoreOutcome(hasTreatments: has, failed: !ok && !has)
    }

    /// Pulls then pushes the signed-in replica. `false` means the network load failed —
    /// local rows must be kept. Never treat a failed fetch as "no data".
    @discardableResult
    func syncIfSignedIn() async -> Bool {
        await cycleCoordinator.enqueue(
            SyncCycleCoordinator.Request(logSince: nil, shouldPush: true)
        ).value
    }

    private func runSync(logSince: Date?, shouldPush: Bool) async -> Bool {
        guard let session, session.kind == .authenticated else { return true }
        guard let store else {
            LaunchLog.error(SyncEngineError.missingStore.localizedDescription)
            return false
        }
        guard let client = session.auth.supabaseForSync else {
            LaunchLog.error(SyncEngineError.missingClient.localizedDescription)
            return false
        }
        guard let ownerId = session.auth.userId else {
            LaunchLog.error(SyncEngineError.missingOwner.localizedDescription)
            return false
        }
        LaunchLog.sync("request push=\(shouldPush) owner=\(ownerId.uuidString.prefix(8))")

        do {
            try await SyncTransportCycle.run(pull: { () async throws -> ReplicaPushPayload? in
                let replica = try await NetworkDeadline.run(seconds: 20) {
                    try await SyncEngine.fetchReplica(client: client, ownerId: ownerId, logSince: logSince)
                }
                await store.applyRemoteReplica(
                    treatments: replica.treatments,
                    medicines: replica.medicines,
                    schedules: replica.schedules,
                    logs: replica.logs
                )
                if let phil = replica.phil {
                    store.applyRemotePhilPlan(status: phil.status, ownerId: ownerId, updatedAt: phil.updatedAt)
                } else if store.hasExistingTreatments, !store.philPlanStatus().planExists {
                    store.setPhilPlanStatus(.active)
                }
                // A successful pull remains local even if the following upload fails.
                store.saveAfterSync()
                try await self.pullFamily(client: client, ownerId: ownerId)

                let profileId: UUID
                if let existing = session.profileId {
                    profileId = existing
                } else {
                    profileId = try await self.fetchProfileId(client: client, ownerId: ownerId)
                }
                guard session.kind == .authenticated, session.auth.userId == ownerId else {
                    throw SyncEngineError.sessionChanged
                }
                store.bindIdentity(ownerId: ownerId, profileId: profileId)
                store.adoptProfile(from: session.localPlanProfileId, to: profileId)
                guard shouldPush else { return nil }

                let treatments = store.treatmentSnapshots().compactMap { RemoteTreatment($0, ownerId: ownerId, profileId: profileId) }
                let medicines = store.medicineSnapshots().compactMap { RemoteMedicine($0, ownerId: ownerId, profileId: profileId) }
                let schedules = store.scheduleSnapshots().compactMap { RemoteSchedule($0, ownerId: ownerId, profileId: profileId) }
                let logs = store.logSnapshots().compactMap { RemoteLog($0, ownerId: ownerId, profileId: profileId) }
                return ReplicaPushPayload(
                    treatments: treatments,
                    medicines: medicines,
                    schedules: schedules,
                    logs: logs
                )
            }, push: { payload in
                guard let payload else { return }
                guard session.kind == .authenticated, session.auth.userId == ownerId else {
                    throw SyncEngineError.sessionChanged
                }
                try await SyncEngine.pushReplica(
                    client: client,
                    treatments: payload.treatments,
                    medicines: payload.medicines,
                    schedules: payload.schedules,
                    logs: payload.logs
                )
                try await self.pushFamily(client: client, ownerId: ownerId)
            })
            lastSyncSucceeded = true
            return true
        } catch {
            lastSyncSucceeded = false
            LaunchLog.error("sync failed: \(error.localizedDescription)")
            return false
        }
    }

    nonisolated private static func fetchReplica(
        client: SupabaseClient,
        ownerId: UUID,
        logSince: Date?
    ) async throws -> ReplicaPayload {
        let treatments: [RemoteTreatment] = try await fetchTable(client, table: "treatments", ownerId: ownerId)
        let medicines: [RemoteMedicine] = try await fetchTable(client, table: "medicines", ownerId: ownerId)
        let schedules: [RemoteSchedule] = try await fetchTable(client, table: "dose_schedules", ownerId: ownerId)
        let logs: [RemoteLog] = try await fetchTable(
            client,
            table: "dose_logs",
            ownerId: ownerId,
            scheduledSince: logSince
        )
        // `phil_plans` is not in the live schema; skip the round trip.
        return ReplicaPayload(
            treatments: treatments.map(\.snapshot),
            medicines: medicines.map(\.snapshot),
            schedules: schedules.map(\.snapshot),
            logs: logs.map(\.snapshot),
            phil: nil
        )
    }

    func bindFamily(_ family: FamilyStore) {
        self.family = family
        family.onCloudSync = { [weak self] in
            guard let self else { return }
            await self.syncIfSignedIn()
        }
    }

    private func pullFamily(client: SupabaseClient, ownerId: UUID) async throws {
        struct Row: Decodable {
            var extraFamilyId: UUID?
            var extraFamilyName: String?
            enum CodingKeys: String, CodingKey {
                case extraFamilyId = "extra_family_id"
                case extraFamilyName = "extra_family_name"
            }
        }
        guard let family else { return }
        let rows: [Row] = try await NetworkDeadline.run(seconds: 12) {
            try await client
                .from("profiles")
                .select("extra_family_id, extra_family_name")
                .eq("owner_id", value: ownerId.uuidString)
                .limit(1)
                .execute()
                .value
        }
        guard let row = rows.first else { return }
        if let name = row.extraFamilyName, !name.isEmpty {
            family.applyRemote(id: row.extraFamilyId ?? family.extra?.id ?? UUID(), name: name)
        }
    }

    private func pushFamily(client: SupabaseClient, ownerId: UUID) async throws {
        struct Patch: Encodable {
            var extra_family_id: UUID?
            var extra_family_name: String?
        }
        guard let family else { return }
        let extra = family.extra
        try await client
            .from("profiles")
            .update(Patch(extra_family_id: extra?.id, extra_family_name: extra?.name))
            .eq("owner_id", value: ownerId.uuidString)
            .execute()
    }

    private func fetchProfileId(client: SupabaseClient, ownerId: UUID) async throws -> UUID {
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await NetworkDeadline.run(seconds: 12) {
            try await client
                .from("profiles")
                .select("id")
                .eq("owner_id", value: ownerId.uuidString)
                .limit(1)
                .execute()
                .value
        }
        guard let profileId = rows.first?.id else { throw SyncEngineError.missingProfile }
        return profileId
    }

    nonisolated private static func fetchTable<T: Decodable>(
        _ client: SupabaseClient,
        table: String,
        ownerId: UUID,
        scheduledSince: Date? = nil
    ) async throws -> [T] {
        var query = client.from(table).select().eq("owner_id", value: ownerId.uuidString)
        if let scheduledSince {
            query = query.gte("scheduled_at", value: RemoteLog.isoStamp(scheduledSince))
        }
        return try await query.execute().value
    }

    nonisolated private static func pushReplica(
        client: SupabaseClient,
        treatments: [RemoteTreatment],
        medicines: [RemoteMedicine],
        schedules: [RemoteSchedule],
        logs: [RemoteLog]
    ) async throws {
        try await upsert(client, table: "treatments", rows: treatments)
        try await upsert(client, table: "medicines", rows: medicines)
        try await upsert(client, table: "dose_schedules", rows: schedules)
        try await upsert(client, table: "dose_logs", rows: logs)
    }

    nonisolated private static func upsert<T: Encodable>(
        _ client: SupabaseClient,
        table: String,
        rows: [T]
    ) async throws {
        guard !rows.isEmpty else { return }
        try await client
            .from(table)
            .upsert(rows, onConflict: "id")
            .execute()
    }
}

nonisolated private struct RemoteTreatment: Codable, Sendable {
    var id: UUID
    var ownerId: UUID
    var profileId: UUID
    var title: String
    var status: String
    var startDate: String
    var endDate: String?
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case profileId = "profile_id"
        case title, status
        case startDate = "start_date"
        case endDate = "end_date"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var snapshot: TreatmentSnapshot {
        TreatmentSnapshot(
            id: id,
            ownerId: ownerId,
            profileId: profileId,
            title: title,
            status: status,
            startDate: Self.date(from: startDate) ?? Date(),
            endDate: endDate.flatMap(Self.date(from:)),
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    init?(_ snapshot: TreatmentSnapshot, ownerId: UUID, profileId: UUID) {
        guard snapshot.ownerId == nil || snapshot.ownerId == ownerId else { return nil }
        self.id = snapshot.id
        self.ownerId = ownerId
        self.profileId = profileId
        self.title = snapshot.title
        self.status = snapshot.status
        self.startDate = Self.stamp(snapshot.startDate)
        self.endDate = snapshot.endDate.map(Self.stamp)
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }

    private static func stamp(_ date: Date) -> String {
        RemoteLog.dayStamp(date)
    }

    private static func date(from stamp: String) -> Date? {
        RemoteLog.dayDate(from: stamp)
    }
}

nonisolated private struct RemoteMedicine: Codable, Sendable {
    var id: UUID
    var ownerId: UUID
    var profileId: UUID
    var treatmentId: UUID
    var name: String
    var doseLabel: String
    var frequency: String
    var duration: String
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case profileId = "profile_id"
        case treatmentId = "treatment_id"
        case name
        case doseLabel = "dose_label"
        case frequency, duration
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var snapshot: MedicineSnapshot {
        MedicineSnapshot(
            id: id,
            treatmentId: treatmentId,
            ownerId: ownerId,
            profileId: profileId,
            name: name,
            doseLabel: doseLabel,
            frequency: frequency,
            duration: duration,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    init?(_ snapshot: MedicineSnapshot, ownerId: UUID, profileId: UUID) {
        guard snapshot.ownerId == nil || snapshot.ownerId == ownerId else { return nil }
        self.id = snapshot.id
        self.ownerId = ownerId
        self.profileId = profileId
        self.treatmentId = snapshot.treatmentId
        self.name = snapshot.name
        self.doseLabel = snapshot.doseLabel
        self.frequency = snapshot.frequency
        self.duration = snapshot.duration
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }
}

nonisolated private struct RemoteSchedule: Codable, Sendable {
    var id: UUID
    var ownerId: UUID
    var profileId: UUID
    var medicineId: UUID
    var timeOfDay: String
    var period: String
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case profileId = "profile_id"
        case medicineId = "medicine_id"
        case timeOfDay = "time_of_day"
        case period
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var snapshot: DoseScheduleSnapshot {
        DoseScheduleSnapshot(
            id: id,
            medicineId: medicineId,
            ownerId: ownerId,
            profileId: profileId,
            timeOfDay: timeOfDay,
            period: period,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    init?(_ snapshot: DoseScheduleSnapshot, ownerId: UUID, profileId: UUID) {
        guard snapshot.ownerId == nil || snapshot.ownerId == ownerId else { return nil }
        self.id = snapshot.id
        self.ownerId = ownerId
        self.profileId = profileId
        self.medicineId = snapshot.medicineId
        self.timeOfDay = snapshot.timeOfDay
        self.period = snapshot.period
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }
}

nonisolated private struct RemoteLog: Codable, Sendable {
    var id: UUID
    var ownerId: UUID
    var profileId: UUID
    var scheduleId: UUID
    var scheduledAt: Date
    var status: String
    var loggedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case profileId = "profile_id"
        case scheduleId = "schedule_id"
        case scheduledAt = "scheduled_at"
        case status
        case loggedAt = "logged_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var snapshot: DoseLogSnapshot {
        DoseLogSnapshot(
            id: id,
            scheduleId: scheduleId,
            ownerId: ownerId,
            profileId: profileId,
            scheduledAt: scheduledAt,
            status: status,
            loggedAt: loggedAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    init?(_ snapshot: DoseLogSnapshot, ownerId: UUID, profileId: UUID) {
        guard snapshot.ownerId == nil || snapshot.ownerId == ownerId else { return nil }
        self.id = snapshot.id
        self.ownerId = ownerId
        self.profileId = profileId
        self.scheduleId = snapshot.scheduleId
        self.scheduledAt = snapshot.scheduledAt
        self.status = snapshot.status
        self.loggedAt = snapshot.loggedAt
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }

    static func isoStamp(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func dayStamp(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func dayDate(from stamp: String) -> Date? {
        dayFormatter.date(from: String(stamp.prefix(10)))
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
