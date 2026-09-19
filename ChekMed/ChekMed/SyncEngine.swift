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
    private var inFlight: Task<Bool, Never>?
    private var queued = false
    private var lastSyncSucceeded = true
    private var replicaRestoreActive = false

    func bind(store: CheckMedStore, session: SessionStore) {
        self.store = store
        self.session = session
        store.onNeedsSync = { [weak self] in
            guard let self, !self.replicaRestoreActive else { return }
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
        replicaRestoreActive = true
        defer { replicaRestoreActive = false }

        let hadLocal = store.hasExistingTreatments
        LaunchLog.data("restore start localTreatments=\(hadLocal)")
        let ok = await runSync(
            logSince: Date().addingTimeInterval(-8 * 86_400),
            shouldPush: false
        )
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
        await startSyncIfNeeded(logSince: nil, push: true).value
    }

    private func startSyncIfNeeded(logSince: Date?, push: Bool) -> Task<Bool, Never> {
        if let inFlight {
            queued = queued || push
            return inFlight
        }
        let task = Task { [weak self] in
            guard let self else { return false }
            let ok = await self.runSync(logSince: logSince, shouldPush: push)
            let followUp = self.queued
            self.queued = false
            self.inFlight = nil
            if followUp {
                _ = await self.startSyncIfNeeded(logSince: nil, push: true).value
            }
            return ok
        }
        inFlight = task
        return task
    }

    private func runSync(logSince: Date?, shouldPush: Bool) async -> Bool {
        guard let session, session.kind == .authenticated else { return true }
        guard let store, let client = session.auth.supabaseForSync else { return true }
        guard let ownerId = session.auth.userId else { return true }
        LaunchLog.sync("request push=\(shouldPush) owner=\(ownerId.uuidString.prefix(8))")

        var pullFailed = false
        do {
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
        } catch {
            pullFailed = true
            LaunchLog.error("sync pull: \(error.localizedDescription)")
        }
        await pullFamily(client: client, ownerId: ownerId)

        let profileId: UUID?
        if let existing = session.profileId {
            profileId = existing
        } else {
            profileId = await fetchProfileId(client: client, ownerId: ownerId)
        }
        if let profileId {
            store.bindIdentity(ownerId: ownerId, profileId: profileId)
            store.adoptProfile(from: session.localPlanProfileId, to: profileId)
            if shouldPush {
                let treatments = store.treatmentSnapshots().compactMap { RemoteTreatment($0, ownerId: ownerId, profileId: profileId) }
                let medicines = store.medicineSnapshots().compactMap { RemoteMedicine($0, ownerId: ownerId, profileId: profileId) }
                let schedules = store.scheduleSnapshots().compactMap { RemoteSchedule($0, ownerId: ownerId, profileId: profileId) }
                let logs = store.logSnapshots().compactMap { RemoteLog($0, ownerId: ownerId, profileId: profileId) }
                Task.detached {
                    await SyncEngine.pushReplica(
                        client: client,
                        treatments: treatments,
                        medicines: medicines,
                        schedules: schedules,
                        logs: logs
                    )
                }
                Task { await self.pushFamily(client: client, ownerId: ownerId) }
            }
        }
        store.saveAfterSync()
        lastSyncSucceeded = !pullFailed
        return lastSyncSucceeded
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
            guard let self, !self.replicaRestoreActive else { return }
            await self.syncIfSignedIn()
        }
    }

    private func pullFamily(client: SupabaseClient, ownerId: UUID) async {
        struct Row: Decodable {
            var extraFamilyId: UUID?
            var extraFamilyName: String?
            enum CodingKeys: String, CodingKey {
                case extraFamilyId = "extra_family_id"
                case extraFamilyName = "extra_family_name"
            }
        }
        guard let family else { return }
        do {
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
        } catch {
            LaunchLog.error("family pull: \(error.localizedDescription)")
        }
    }

    private func pushFamily(client: SupabaseClient, ownerId: UUID) async {
        struct Patch: Encodable {
            var extra_family_id: UUID?
            var extra_family_name: String?
        }
        let extra = family?.extra
        _ = try? await client
            .from("profiles")
            .update(Patch(extra_family_id: extra?.id, extra_family_name: extra?.name))
            .eq("owner_id", value: ownerId.uuidString)
            .execute()
    }

    private func fetchProfileId(client: SupabaseClient, ownerId: UUID) async -> UUID? {
        struct Row: Decodable { let id: UUID }
        do {
            let rows: [Row] = try await NetworkDeadline.run(seconds: 12) {
                try await client
                    .from("profiles")
                    .select("id")
                    .eq("owner_id", value: ownerId.uuidString)
                    .limit(1)
                    .execute()
                    .value
            }
            return rows.first?.id
        } catch {
            LaunchLog.error("profile id fetch: \(error.localizedDescription)")
            return nil
        }
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
    ) async {
        _ = try? await upsert(client, table: "treatments", rows: treatments)
        _ = try? await upsert(client, table: "medicines", rows: medicines)
        _ = try? await upsert(client, table: "dose_schedules", rows: schedules)
        _ = try? await upsert(client, table: "dose_logs", rows: logs)
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
