import Foundation
import Supabase

/// Last-write-wins replica of local SwiftData. Auth required. Screens do not call this.
@Observable
@MainActor
final class SyncEngine {
    @ObservationIgnored
    private weak var store: CheckMedStore?
    @ObservationIgnored
    private weak var session: SessionStore?
    private var isSyncing = false
    private var queued = false

    func bind(store: CheckMedStore, session: SessionStore) {
        self.store = store
        self.session = session
        store.onNeedsSync = { [weak self] in
            await self?.syncIfSignedIn()
        }
    }

    func syncIfSignedIn() async {
        if isSyncing {
            queued = true
            return
        }
        guard let session, session.kind == .authenticated else { return }
        guard let store, let client = session.auth.supabaseForSync else { return }
        guard let ownerId = session.auth.userId else { return }
        isSyncing = true
        defer {
            isSyncing = false
            if queued {
                queued = false
                Task { await syncIfSignedIn() }
            }
        }

        let profileId: UUID
        if let existing = session.profileId {
            profileId = existing
        } else if let fetched = await fetchProfileId(client: client, ownerId: ownerId) {
            profileId = fetched
        } else {
            return
        }
        store.bindIdentity(ownerId: ownerId, profileId: profileId)

        await pull(client: client, ownerId: ownerId, into: store)
        await push(client: client, ownerId: ownerId, profileId: profileId, from: store)
        store.saveAfterSync()
    }

    private func fetchProfileId(client: SupabaseClient, ownerId: UUID) async -> UUID? {
        struct Row: Decodable { let id: UUID }
        do {
            let rows: [Row] = try await client
                .from("profiles")
                .select("id")
                .eq("owner_id", value: ownerId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first?.id
        } catch {
            return nil
        }
    }

    private func pull(client: SupabaseClient, ownerId: UUID, into store: CheckMedStore) async {
        if let rows: [RemoteTreatment] = try? await fetch(client, table: "treatments", ownerId: ownerId) {
            for row in rows { store.mergeTreatment(row.snapshot) }
        }
        if let rows: [RemoteMedicine] = try? await fetch(client, table: "medicines", ownerId: ownerId) {
            for row in rows { store.mergeMedicine(row.snapshot) }
        }
        if let rows: [RemoteSchedule] = try? await fetch(client, table: "dose_schedules", ownerId: ownerId) {
            for row in rows { store.mergeSchedule(row.snapshot) }
        }
        if let rows: [RemoteLog] = try? await fetch(client, table: "dose_logs", ownerId: ownerId) {
            for row in rows { store.mergeLog(row.snapshot) }
        }
    }

    private func push(
        client: SupabaseClient,
        ownerId: UUID,
        profileId: UUID,
        from store: CheckMedStore
    ) async {
        let treatments = store.treatmentSnapshots().compactMap { RemoteTreatment($0, ownerId: ownerId, profileId: profileId) }
        let medicines = store.medicineSnapshots().compactMap { RemoteMedicine($0, ownerId: ownerId, profileId: profileId) }
        let schedules = store.scheduleSnapshots().compactMap { RemoteSchedule($0, ownerId: ownerId, profileId: profileId) }
        let logs = store.logSnapshots().compactMap { RemoteLog($0, ownerId: ownerId, profileId: profileId) }
        _ = try? await upsert(client, table: "treatments", rows: treatments)
        _ = try? await upsert(client, table: "medicines", rows: medicines)
        _ = try? await upsert(client, table: "dose_schedules", rows: schedules)
        _ = try? await upsert(client, table: "dose_logs", rows: logs)
    }

    private func fetch<T: Decodable>(
        _ client: SupabaseClient,
        table: String,
        ownerId: UUID
    ) async throws -> [T] {
        try await client
            .from(table)
            .select()
            .eq("owner_id", value: ownerId.uuidString)
            .execute()
            .value
    }

    private func upsert<T: Encodable>(
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

private struct RemoteTreatment: Codable {
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
        self.profileId = snapshot.profileId ?? profileId
        self.title = snapshot.title
        self.status = snapshot.status
        self.startDate = Self.stamp(snapshot.startDate)
        self.endDate = snapshot.endDate.map(Self.stamp)
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(from stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(stamp.prefix(10)))
    }
}

private struct RemoteMedicine: Codable {
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
        self.profileId = snapshot.profileId ?? profileId
        self.treatmentId = snapshot.treatmentId
        self.name = snapshot.name
        self.doseLabel = snapshot.doseLabel
        self.frequency = snapshot.frequency
        self.duration = snapshot.duration
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }
}

private struct RemoteSchedule: Codable {
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
        self.profileId = snapshot.profileId ?? profileId
        self.medicineId = snapshot.medicineId
        self.timeOfDay = snapshot.timeOfDay
        self.period = snapshot.period
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }
}

private struct RemoteLog: Codable {
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
        self.profileId = snapshot.profileId ?? profileId
        self.scheduleId = snapshot.scheduleId
        self.scheduledAt = snapshot.scheduledAt
        self.status = snapshot.status
        self.loggedAt = snapshot.loggedAt
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
    }
}
