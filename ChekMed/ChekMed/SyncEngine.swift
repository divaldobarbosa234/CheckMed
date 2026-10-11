import Foundation
import Network
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
    private var isSuspended = false

    init(runner: @escaping Runner) {
        self.runner = runner
    }

    func enqueue(_ request: Request) -> Task<Bool, Never> {
        guard !isSuspended else {
            return Task { false }
        }
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

    func suspend() {
        isSuspended = true
        queuedRequest = nil
    }

    func suspendAndDrain() async {
        suspend()
        if let inFlight {
            _ = await inFlight.value
        }
    }

    func resume() {
        isSuspended = false
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
    case invalidAcknowledgement
    case protocolConflict
    case unsafeProtocolRollback
    case localPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .missingStore: "Sync store unavailable"
        case .missingClient: "Sync client unavailable"
        case .missingOwner: "Sync owner unavailable"
        case .missingProfile: "Sync profile unavailable"
        case .sessionChanged: "Sync session changed"
        case .invalidAcknowledgement: "Sync acknowledgement invalid"
        case .protocolConflict: "Sync conflict requires resolution"
        case .unsafeProtocolRollback: "Protected sync protocol unavailable"
        case .localPersistenceFailed: "Sync persistence failed"
        }
    }
}

/// Last-write-wins replica of local SwiftData. Auth required. Screens do not call this.
@Observable
@MainActor
final class SyncEngine {
    enum PendingInspectionReason: String {
        case sessionRestore
        case syncRequest
        case foreground
        case networkRecovery
    }

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
    private var networkMonitor: NWPathMonitor?
    @ObservationIgnored
    private var networkWasSatisfied = false
    @ObservationIgnored
    private var sessionGeneration: UInt64 = 0
    @ObservationIgnored
    private var activeOwnerId: UUID?
    @ObservationIgnored
    private var deletionBlockedOwners: Set<UUID> = []
    @ObservationIgnored
    private var expandedReplicaOwners: Set<UUID> = []
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
        startNetworkMonitoringIfNeeded()
    }

    func activateSession(ownerId: UUID) {
        if activeOwnerId != ownerId {
            sessionGeneration &+= 1
            activeOwnerId = ownerId
        }
        deletionBlockedOwners.remove(ownerId)
        cycleCoordinator.resume()
    }

    func invalidateSession() {
        sessionGeneration &+= 1
        activeOwnerId = nil
        cycleCoordinator.suspend()
    }

    func beginAccountDeletion(ownerId: UUID) async {
        deletionBlockedOwners.insert(ownerId)
        sessionGeneration &+= 1
        await cycleCoordinator.suspendAndDrain()
    }

    func cancelAccountDeletion(ownerId: UUID) {
        deletionBlockedOwners.remove(ownerId)
        if session?.kind == .authenticated, session?.auth.userId == ownerId {
            activeOwnerId = ownerId
            cycleCoordinator.resume()
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
        inspectPendingOutbox(reason: .sessionRestore)
        return RestoreOutcome(hasTreatments: has, failed: !ok && !has)
    }

    /// Pulls then pushes the signed-in replica. `false` means the network load failed —
    /// local rows must be kept. Never treat a failed fetch as "no data".
    @discardableResult
    func syncIfSignedIn() async -> Bool {
        if let ownerId = session?.auth.userId,
           let store,
           store.pendingSyncMutationCount(ownerId: ownerId) > 0 {
            LaunchLog.sync("durable local mutations pending reason=\(PendingInspectionReason.syncRequest.rawValue)")
        }
        return await cycleCoordinator.enqueue(
            SyncCycleCoordinator.Request(logSince: nil, shouldPush: true)
        ).value
    }

    func inspectPendingOutbox(reason: PendingInspectionReason) {
        guard let session,
              session.kind == .authenticated,
              let ownerId = session.auth.userId,
              let store,
              store.pendingSyncMutationCount(ownerId: ownerId) > 0
        else { return }
        LaunchLog.sync("durable local mutations pending reason=\(reason.rawValue)")
        Task { [weak self] in
            _ = await self?.syncIfSignedIn()
        }
    }

    private func startNetworkMonitoringIfNeeded() {
        guard networkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                let recovered = satisfied && !self.networkWasSatisfied
                self.networkWasSatisfied = satisfied
                if recovered {
                    self.inspectPendingOutbox(reason: .networkRecovery)
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.checkmed.sync-reachability"))
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
        guard !deletionBlockedOwners.contains(ownerId) else { return false }
        if activeOwnerId != ownerId {
            activateSession(ownerId: ownerId)
        }
        let generation = sessionGeneration
        LaunchLog.sync("request push=\(shouldPush) owner=\(ownerId.uuidString.prefix(8))")

        do {
            let mode = try await protocolMode(client: client, ownerId: ownerId)
            switch mode {
            case .legacy:
                try await runLegacySync(
                    client: client,
                    store: store,
                    session: session,
                    ownerId: ownerId,
                    generation: generation,
                    logSince: logSince,
                    shouldPush: shouldPush
                )
            case .versioned:
                try await runVersionedSync(
                    client: client,
                    store: store,
                    session: session,
                    ownerId: ownerId,
                    generation: generation,
                    shouldConsume: shouldPush
                )
            }
            lastSyncSucceeded = true
            return true
        } catch {
            lastSyncSucceeded = false
            LaunchLog.error("sync failed: \(error.localizedDescription)")
            return false
        }
    }

    private func runLegacySync(
        client: SupabaseClient,
        store: CheckMedStore,
        session: SessionStore,
        ownerId: UUID,
        generation: UInt64,
        logSince: Date?,
        shouldPush: Bool
    ) async throws {
        try await SyncTransportCycle.run(pull: { () async throws -> ReplicaPushPayload? in
            let replica = try await NetworkDeadline.run(seconds: 20) {
                try await SyncEngine.fetchReplica(
                    client: client,
                    ownerId: ownerId,
                    logSince: logSince
                )
            }
            try self.requireCurrentSession(ownerId: ownerId, generation: generation)
            await store.applyRemoteReplica(
                treatments: replica.treatments,
                medicines: replica.medicines,
                schedules: replica.schedules,
                logs: replica.logs
            )
            if let phil = replica.phil {
                store.applyRemotePhilPlan(
                    status: phil.status,
                    ownerId: ownerId,
                    updatedAt: phil.updatedAt
                )
            } else if store.hasExistingTreatments, !store.philPlanStatus().planExists {
                store.setPhilPlanStatus(.active)
            }
            store.saveAfterSync()
            try await self.pullFamily(client: client, ownerId: ownerId)
            let profileId = try await self.resolvedProfileId(
                client: client,
                session: session,
                ownerId: ownerId
            )
            try self.requireCurrentSession(ownerId: ownerId, generation: generation)
            store.bindIdentity(ownerId: ownerId, profileId: profileId)
            store.adoptProfile(from: session.localPlanProfileId, to: profileId)
            guard shouldPush else { return nil }
            return ReplicaPushPayload(
                treatments: store.treatmentSnapshots().compactMap {
                    RemoteTreatment($0, ownerId: ownerId, profileId: profileId)
                },
                medicines: store.medicineSnapshots().compactMap {
                    RemoteMedicine(
                        $0,
                        ownerId: ownerId,
                        profileId: profileId,
                        includeCompleteFields: self.expandedReplicaOwners.contains(ownerId)
                    )
                },
                schedules: store.scheduleSnapshots().compactMap {
                    RemoteSchedule($0, ownerId: ownerId, profileId: profileId)
                },
                logs: store.logSnapshots().compactMap {
                    RemoteLog($0, ownerId: ownerId, profileId: profileId)
                }
            )
        }, push: { payload in
            guard let payload else { return }
            try self.requireCurrentSession(ownerId: ownerId, generation: generation)
            try await SyncEngine.pushReplica(
                client: client,
                treatments: payload.treatments,
                medicines: payload.medicines,
                schedules: payload.schedules,
                logs: payload.logs
            )
            try self.requireCurrentSession(ownerId: ownerId, generation: generation)
            try await self.pushFamily(client: client, ownerId: ownerId)
        })
    }

    private func runVersionedSync(
        client: SupabaseClient,
        store: CheckMedStore,
        session: SessionStore,
        ownerId: UUID,
        generation: UInt64,
        shouldConsume: Bool
    ) async throws {
        let replica = try await NetworkDeadline.run(seconds: 20) {
            try await SyncEngine.fetchReplica(
                client: client,
                ownerId: ownerId,
                // Versioned restoration is complete and paginated. Historical
                // DoseLog identity, rewards, reports, and streaks must survive.
                logSince: nil
            )
        }
        try requireCurrentSession(ownerId: ownerId, generation: generation)
        await store.applyRemoteReplica(
            treatments: replica.treatments,
            medicines: replica.medicines,
            schedules: replica.schedules,
            logs: replica.logs,
            preservingLocalMutations: true
        )
        guard store.saveAfterVersionedSync() else {
            throw SyncEngineError.localPersistenceFailed
        }
        try await pullFamily(client: client, ownerId: ownerId)
        let profileId = try await resolvedProfileId(
            client: client,
            session: session,
            ownerId: ownerId
        )
        try requireCurrentSession(ownerId: ownerId, generation: generation)
        store.bindIdentity(ownerId: ownerId, profileId: profileId)
        store.adoptProfile(from: session.localPlanProfileId, to: profileId)
        guard shouldConsume else { return }

        while true {
            try requireCurrentSession(ownerId: ownerId, generation: generation)
            guard let work = try store.prepareNextSyncMutation(ownerId: ownerId) else {
                if store.hasPendingSyncConflict(ownerId: ownerId) {
                    throw SyncEngineError.protocolConflict
                }
                break
            }
            let response = try await NetworkDeadline.run(seconds: 20) {
                try await SyncEngine.applyMutation(client: client, work: work)
            }
            try requireCurrentSession(ownerId: ownerId, generation: generation)
            if response.outcome.isAcknowledgement {
                guard SyncProtocolValidation.responseMatches(response, work: work) else {
                    throw SyncEngineError.invalidAcknowledgement
                }
                let canonical = try SyncEngine.canonicalSnapshot(
                    from: response,
                    entity: work.entityType
                )
                guard store.acknowledgeSyncMutation(
                    work,
                    response: response,
                    canonical: canonical
                ) else {
                    throw SyncEngineError.invalidAcknowledgement
                }
            } else {
                guard store.retainSyncConflict(work, response: response) else {
                    throw SyncEngineError.localPersistenceFailed
                }
                throw SyncEngineError.protocolConflict
            }
        }
        try requireCurrentSession(ownerId: ownerId, generation: generation)
        try await pushFamily(client: client, ownerId: ownerId)
    }

    private func resolvedProfileId(
        client: SupabaseClient,
        session: SessionStore,
        ownerId: UUID
    ) async throws -> UUID {
        if let existing = session.profileId { return existing }
        return try await fetchProfileId(client: client, ownerId: ownerId)
    }

    private func requireCurrentSession(ownerId: UUID, generation: UInt64) throws {
        guard sessionGeneration == generation,
              !deletionBlockedOwners.contains(ownerId),
              activeOwnerId == ownerId,
              session?.kind == .authenticated,
              session?.auth.userId == ownerId else {
            throw SyncEngineError.sessionChanged
        }
    }

    private func protocolMode(
        client: SupabaseClient,
        ownerId: UUID
    ) async throws -> SyncProtocolMode {
        let key = "checkmed.sync.protocol.v1.enforced.\(ownerId.uuidString)"
        let wasProtected = UserDefaults.standard.bool(forKey: key)
        do {
            let capabilities: SyncProtocolCapabilities = try await NetworkDeadline.run(seconds: 12) {
                try await client
                    .rpc("sync_protocol_capabilities_v1")
                    .execute()
                    .value
            }
            if capabilities.mode == .versioned {
                UserDefaults.standard.set(true, forKey: key)
                expandedReplicaOwners.insert(ownerId)
                return .versioned
            }
            if capabilities.protocolVersion >= 1, capabilities.mutationRPCAvailable {
                expandedReplicaOwners.insert(ownerId)
            }
            guard !wasProtected else {
                throw SyncEngineError.unsafeProtocolRollback
            }
            return .legacy
        } catch {
            guard !wasProtected else {
                throw SyncEngineError.unsafeProtocolRollback
            }
            return .legacy
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
        let pageSize = 500
        var offset = 0
        var result: [T] = []
        while true {
            var query = client.from(table).select().eq("owner_id", value: ownerId.uuidString)
            if let scheduledSince {
                query = query.gte("scheduled_at", value: RemoteLog.isoStamp(scheduledSince))
            }
            let page: [T] = try await query
                .order("id")
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            result.append(contentsOf: page)
            guard page.count == pageSize else { return result }
            offset += pageSize
        }
    }

    nonisolated private static func applyMutation(
        client: SupabaseClient,
        work: SyncMutationWorkItem
    ) async throws -> SyncMutationRPCResponse {
        try await client
            .rpc("apply_sync_mutation_v1", params: SyncMutationRPCRequest(work))
            .execute()
            .value
    }

    nonisolated private static func canonicalSnapshot(
        from response: SyncMutationRPCResponse,
        entity: SyncMutationEntity
    ) throws -> SyncCanonicalSnapshot? {
        guard let data = try SyncWireCodec.data(from: response.canonicalRow) else {
            return nil
        }
        let decoder = SyncWireCodec.decoder()
        switch entity {
        case .treatment:
            return .treatment(try decoder.decode(RemoteTreatment.self, from: data).snapshot)
        case .medicine:
            return .medicine(try decoder.decode(RemoteMedicine.self, from: data).snapshot)
        case .schedule:
            return .schedule(try decoder.decode(RemoteSchedule.self, from: data).snapshot)
        case .doseLog:
            return .doseLog(try decoder.decode(RemoteLog.self, from: data).snapshot)
        }
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
    var subjectProfileId: UUID?
    var title: String
    var status: String
    var startDate: String
    var endDate: String?
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case profileId = "profile_id"
        case subjectProfileId = "subject_profile_id"
        case title, status
        case startDate = "start_date"
        case endDate = "end_date"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }

    var snapshot: TreatmentSnapshot {
        TreatmentSnapshot(
            id: id,
            ownerId: ownerId,
            profileId: subjectProfileId ?? profileId,
            title: title,
            status: status,
            startDate: Self.date(from: startDate) ?? Date(),
            endDate: endDate.flatMap(Self.date(from:)),
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            syncVersion: syncVersion
        )
    }

    init?(_ snapshot: TreatmentSnapshot, ownerId: UUID, profileId: UUID) {
        guard snapshot.ownerId == nil || snapshot.ownerId == ownerId else { return nil }
        self.id = snapshot.id
        self.ownerId = ownerId
        self.profileId = profileId
        self.subjectProfileId = nil
        self.title = snapshot.title
        self.status = snapshot.status
        self.startDate = Self.stamp(snapshot.startDate)
        self.endDate = snapshot.endDate.map(Self.stamp)
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
        self.syncVersion = nil
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
    var subjectProfileId: UUID?
    var treatmentId: UUID
    var name: String
    var doseLabel: String
    var frequency: String
    var duration: String
    var reason: String?
    var form: String?
    var packageAmount: Double?
    var packageUnit: String?
    var stockPercent: Double?
    var quantityPerDose: Double?
    var doseUnit: String?
    var doctorName: String?
    var doctorId: String?
    var hospitalName: String?
    var doctorNotes: String?
    var lastRefillAt: Date?
    var refillRemindEnabled: Bool?
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case profileId = "profile_id"
        case subjectProfileId = "subject_profile_id"
        case treatmentId = "treatment_id"
        case name
        case doseLabel = "dose_label"
        case frequency, duration
        case reason, form
        case packageAmount = "package_amount"
        case packageUnit = "package_unit"
        case stockPercent = "stock_percent"
        case quantityPerDose = "quantity_per_dose"
        case doseUnit = "dose_unit"
        case doctorName = "doctor_name"
        case doctorId = "doctor_id"
        case hospitalName = "hospital_name"
        case doctorNotes = "doctor_notes"
        case lastRefillAt = "last_refill_at"
        case refillRemindEnabled = "refill_remind_enabled"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }

    var snapshot: MedicineSnapshot {
        MedicineSnapshot(
            id: id,
            treatmentId: treatmentId,
            ownerId: ownerId,
            profileId: subjectProfileId ?? profileId,
            name: name,
            doseLabel: doseLabel,
            frequency: frequency,
            duration: duration,
            reason: reason ?? "",
            form: form ?? MedicineForm.other.rawValue,
            packageAmount: packageAmount ?? 0,
            packageUnit: packageUnit ?? MedicineUnit.tablet.rawValue,
            stockPercent: stockPercent ?? 100,
            quantityPerDose: quantityPerDose ?? 1,
            doseUnit: doseUnit ?? MedicineUnit.tablet.rawValue,
            doctorName: doctorName ?? "",
            doctorId: doctorId ?? "",
            hospitalName: hospitalName ?? "",
            doctorNotes: doctorNotes ?? "",
            lastRefillAt: lastRefillAt,
            refillRemindEnabled: refillRemindEnabled ?? true,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            syncVersion: syncVersion,
            replicaIncludesCompleteFields: reason != nil
                && form != nil
                && packageAmount != nil
                && packageUnit != nil
                && stockPercent != nil
                && quantityPerDose != nil
                && doseUnit != nil
                && doctorName != nil
                && doctorId != nil
                && hospitalName != nil
                && doctorNotes != nil
                && refillRemindEnabled != nil
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(profileId, forKey: .profileId)
        try container.encode(treatmentId, forKey: .treatmentId)
        try container.encode(name, forKey: .name)
        try container.encode(doseLabel, forKey: .doseLabel)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(duration, forKey: .duration)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        guard refillRemindEnabled != nil else { return }
        try container.encode(reason, forKey: .reason)
        try container.encode(form, forKey: .form)
        try container.encode(packageAmount, forKey: .packageAmount)
        try container.encode(packageUnit, forKey: .packageUnit)
        try container.encode(stockPercent, forKey: .stockPercent)
        try container.encode(quantityPerDose, forKey: .quantityPerDose)
        try container.encode(doseUnit, forKey: .doseUnit)
        try container.encode(doctorName, forKey: .doctorName)
        try container.encode(doctorId, forKey: .doctorId)
        try container.encode(hospitalName, forKey: .hospitalName)
        try container.encode(doctorNotes, forKey: .doctorNotes)
        try container.encode(lastRefillAt, forKey: .lastRefillAt)
        try container.encode(refillRemindEnabled, forKey: .refillRemindEnabled)
    }

    init?(
        _ snapshot: MedicineSnapshot,
        ownerId: UUID,
        profileId: UUID,
        includeCompleteFields: Bool = false
    ) {
        guard snapshot.ownerId == nil || snapshot.ownerId == ownerId else { return nil }
        self.id = snapshot.id
        self.ownerId = ownerId
        self.profileId = profileId
        self.subjectProfileId = nil
        self.treatmentId = snapshot.treatmentId
        self.name = snapshot.name
        self.doseLabel = snapshot.doseLabel
        self.frequency = snapshot.frequency
        self.duration = snapshot.duration
        self.reason = includeCompleteFields ? snapshot.reason : nil
        self.form = includeCompleteFields ? snapshot.form : nil
        self.packageAmount = includeCompleteFields ? snapshot.packageAmount : nil
        self.packageUnit = includeCompleteFields ? snapshot.packageUnit : nil
        self.stockPercent = includeCompleteFields ? snapshot.stockPercent : nil
        self.quantityPerDose = includeCompleteFields ? snapshot.quantityPerDose : nil
        self.doseUnit = includeCompleteFields ? snapshot.doseUnit : nil
        self.doctorName = includeCompleteFields ? snapshot.doctorName : nil
        self.doctorId = includeCompleteFields ? snapshot.doctorId : nil
        self.hospitalName = includeCompleteFields ? snapshot.hospitalName : nil
        self.doctorNotes = includeCompleteFields ? snapshot.doctorNotes : nil
        self.lastRefillAt = includeCompleteFields ? snapshot.lastRefillAt : nil
        self.refillRemindEnabled = includeCompleteFields ? snapshot.refillRemindEnabled : nil
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
        self.syncVersion = nil
    }
}

nonisolated private struct RemoteSchedule: Codable, Sendable {
    var id: UUID
    var ownerId: UUID
    var profileId: UUID
    var subjectProfileId: UUID?
    var medicineId: UUID
    var timeOfDay: String
    var period: String
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case profileId = "profile_id"
        case subjectProfileId = "subject_profile_id"
        case medicineId = "medicine_id"
        case timeOfDay = "time_of_day"
        case period
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }

    var snapshot: DoseScheduleSnapshot {
        DoseScheduleSnapshot(
            id: id,
            medicineId: medicineId,
            ownerId: ownerId,
            profileId: subjectProfileId ?? profileId,
            timeOfDay: timeOfDay,
            period: period,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            syncVersion: syncVersion
        )
    }

    init?(_ snapshot: DoseScheduleSnapshot, ownerId: UUID, profileId: UUID) {
        guard snapshot.ownerId == nil || snapshot.ownerId == ownerId else { return nil }
        self.id = snapshot.id
        self.ownerId = ownerId
        self.profileId = profileId
        self.subjectProfileId = nil
        self.medicineId = snapshot.medicineId
        self.timeOfDay = snapshot.timeOfDay
        self.period = snapshot.period
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
        self.syncVersion = nil
    }
}

nonisolated private struct RemoteLog: Codable, Sendable {
    var id: UUID
    var ownerId: UUID
    var profileId: UUID
    var subjectProfileId: UUID?
    var scheduleId: UUID
    var scheduledAt: Date
    var status: String
    var loggedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?
    var syncVersion: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case profileId = "profile_id"
        case subjectProfileId = "subject_profile_id"
        case scheduleId = "schedule_id"
        case scheduledAt = "scheduled_at"
        case status
        case loggedAt = "logged_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case syncVersion = "sync_version"
    }

    var snapshot: DoseLogSnapshot {
        DoseLogSnapshot(
            id: id,
            scheduleId: scheduleId,
            ownerId: ownerId,
            profileId: subjectProfileId ?? profileId,
            scheduledAt: scheduledAt,
            status: status,
            loggedAt: loggedAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            syncVersion: syncVersion
        )
    }

    init?(_ snapshot: DoseLogSnapshot, ownerId: UUID, profileId: UUID) {
        guard snapshot.ownerId == nil || snapshot.ownerId == ownerId else { return nil }
        self.id = snapshot.id
        self.ownerId = ownerId
        self.profileId = profileId
        self.subjectProfileId = nil
        self.scheduleId = snapshot.scheduleId
        self.scheduledAt = snapshot.scheduledAt
        self.status = snapshot.status
        self.loggedAt = snapshot.loggedAt
        self.updatedAt = snapshot.updatedAt
        self.deletedAt = snapshot.deletedAt
        self.syncVersion = nil
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
