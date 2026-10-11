import Foundation
import Supabase

enum SyncProtocolMode: Equatable, Sendable {
    case legacy
    case versioned
}

/// Separate from server write enforcement. This build must not consume the
/// outbox until isolated verification and an explicit cutover approval.
enum SyncProtocolActivation {
    static let outboxConsumptionAuthorized = false
}

struct SyncProtocolCapabilities: Decodable, Equatable, Sendable {
    var protocolVersion: Int
    var mutationRPCAvailable: Bool
    var directWritesEnforced: Bool
    var outboxConsumptionEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case mutationRPCAvailable = "mutation_rpc_available"
        case directWritesEnforced = "direct_writes_enforced"
        case outboxConsumptionEnabled = "outbox_consumption_enabled"
    }

    var serverAllowsVersioned: Bool {
        protocolVersion >= 1
            && mutationRPCAvailable
            && directWritesEnforced
            && outboxConsumptionEnabled
    }

    var mode: SyncProtocolMode {
        serverAllowsVersioned && SyncProtocolActivation.outboxConsumptionAuthorized
            ? .versioned
            : .legacy
    }
}

enum SyncProtocolDecision {
    enum Failure: Error, Equatable {
        case unsafeRollback
    }

    /// Once a client has consumed the versioned protocol, capability downgrade
    /// must fail closed. It must not silently reopen legacy snapshot writes.
    static func resolve(
        capabilities: SyncProtocolCapabilities,
        clientAuthorized: Bool,
        wasProtected: Bool
    ) throws -> SyncProtocolMode {
        if capabilities.serverAllowsVersioned && clientAuthorized {
            return .versioned
        }
        if wasProtected {
            throw Failure.unsafeRollback
        }
        return .legacy
    }
}

struct SyncMutationPayload: Codable, Equatable, Sendable {
    var title: String?
    var status: String?
    var startDate: String?
    var endDate: String?

    var treatmentId: UUID?
    var name: String?
    var doseLabel: String?
    var frequency: String?
    var duration: String?
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
    var lastRefillAt: String?
    var refillRemindEnabled: Bool?

    var medicineId: UUID?
    var timeOfDay: String?
    var period: String?

    var scheduleId: UUID?
    var scheduledAt: String?
    var loggedAt: String?

    enum CodingKeys: String, CodingKey {
        case title, status
        case startDate = "start_date"
        case endDate = "end_date"
        case treatmentId = "treatment_id"
        case name
        case doseLabel = "dose_label"
        case frequency, duration, reason, form
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
        case medicineId = "medicine_id"
        case timeOfDay = "time_of_day"
        case period
        case scheduleId = "schedule_id"
        case scheduledAt = "scheduled_at"
        case loggedAt = "logged_at"
    }

    init(
        title: String? = nil,
        status: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        treatmentId: UUID? = nil,
        name: String? = nil,
        doseLabel: String? = nil,
        frequency: String? = nil,
        duration: String? = nil,
        reason: String? = nil,
        form: String? = nil,
        packageAmount: Double? = nil,
        packageUnit: String? = nil,
        stockPercent: Double? = nil,
        quantityPerDose: Double? = nil,
        doseUnit: String? = nil,
        doctorName: String? = nil,
        doctorId: String? = nil,
        hospitalName: String? = nil,
        doctorNotes: String? = nil,
        lastRefillAt: String? = nil,
        refillRemindEnabled: Bool? = nil,
        medicineId: UUID? = nil,
        timeOfDay: String? = nil,
        period: String? = nil,
        scheduleId: UUID? = nil,
        scheduledAt: String? = nil,
        loggedAt: String? = nil
    ) {
        self.title = title
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
        self.treatmentId = treatmentId
        self.name = name
        self.doseLabel = doseLabel
        self.frequency = frequency
        self.duration = duration
        self.reason = reason
        self.form = form
        self.packageAmount = packageAmount
        self.packageUnit = packageUnit
        self.stockPercent = stockPercent
        self.quantityPerDose = quantityPerDose
        self.doseUnit = doseUnit
        self.doctorName = doctorName
        self.doctorId = doctorId
        self.hospitalName = hospitalName
        self.doctorNotes = doctorNotes
        self.lastRefillAt = lastRefillAt
        self.refillRemindEnabled = refillRemindEnabled
        self.medicineId = medicineId
        self.timeOfDay = timeOfDay
        self.period = period
        self.scheduleId = scheduleId
        self.scheduledAt = scheduledAt
        self.loggedAt = loggedAt
    }

    init(_ snapshot: TreatmentSnapshot) {
        self.init(
            title: snapshot.title,
            status: snapshot.status,
            startDate: SyncWireCodec.dayStamp(snapshot.startDate),
            endDate: snapshot.endDate.map(SyncWireCodec.dayStamp)
        )
    }

    init(_ snapshot: MedicineSnapshot) {
        self.init(
            treatmentId: snapshot.treatmentId,
            name: snapshot.name,
            doseLabel: snapshot.doseLabel,
            frequency: snapshot.frequency,
            duration: snapshot.duration,
            reason: snapshot.reason,
            form: snapshot.form,
            packageAmount: snapshot.packageAmount,
            packageUnit: snapshot.packageUnit,
            stockPercent: snapshot.stockPercent,
            quantityPerDose: snapshot.quantityPerDose,
            doseUnit: snapshot.doseUnit,
            doctorName: snapshot.doctorName,
            doctorId: snapshot.doctorId,
            hospitalName: snapshot.hospitalName,
            doctorNotes: snapshot.doctorNotes,
            lastRefillAt: snapshot.lastRefillAt.map(SyncWireCodec.timestamp),
            refillRemindEnabled: snapshot.refillRemindEnabled
        )
    }

    init(_ snapshot: DoseScheduleSnapshot) {
        self.init(
            medicineId: snapshot.medicineId,
            timeOfDay: snapshot.timeOfDay,
            period: snapshot.period
        )
    }

    init(_ snapshot: DoseLogSnapshot) {
        self.init(
            status: snapshot.status,
            scheduleId: snapshot.scheduleId,
            scheduledAt: SyncWireCodec.timestamp(snapshot.scheduledAt),
            loggedAt: snapshot.loggedAt.map(SyncWireCodec.timestamp)
        )
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SyncMutationPayload {
        try JSONDecoder().decode(SyncMutationPayload.self, from: data)
    }
}

struct SyncMutationWorkItem: Equatable, Sendable {
    var mutationId: UUID
    var ownerId: UUID
    var subjectProfileId: UUID?
    var entityType: SyncMutationEntity
    var localEntityId: UUID
    var transportEntityId: UUID
    var operation: SyncMutationOperation
    var expectedVersion: Int64
    var payload: SyncMutationPayload
}

enum SyncCanonicalSnapshot: Sendable {
    case treatment(TreatmentSnapshot)
    case medicine(MedicineSnapshot)
    case schedule(DoseScheduleSnapshot)
    case doseLog(DoseLogSnapshot)
}

struct SyncMutationRPCRequest: Encodable, Sendable {
    var mutationId: UUID
    var entityType: String
    var entityId: UUID
    var ownerId: UUID
    var subjectProfileId: UUID?
    var operation: String
    var expectedVersion: Int64
    var payload: SyncMutationPayload

    enum CodingKeys: String, CodingKey {
        case mutationId = "p_mutation_id"
        case entityType = "p_entity_type"
        case entityId = "p_entity_id"
        case ownerId = "p_owner_id"
        case subjectProfileId = "p_subject_profile_id"
        case operation = "p_operation"
        case expectedVersion = "p_expected_version"
        case payload = "p_payload"
    }

    init(_ work: SyncMutationWorkItem) {
        mutationId = work.mutationId
        entityType = work.entityType.rawValue
        entityId = work.transportEntityId
        ownerId = work.ownerId
        subjectProfileId = work.subjectProfileId
        operation = work.operation.rawValue
        expectedVersion = work.expectedVersion
        payload = work.payload
    }
}

enum SyncMutationOutcome: String, Decodable, Sendable {
    case applied
    case alreadyApplied = "already_applied"
    case alreadyDeleted = "already_deleted"
    case conflict
    case parentDeleted = "parent_deleted"
    case invalid

    var isAcknowledgement: Bool {
        self == .applied || self == .alreadyApplied || self == .alreadyDeleted
    }
}

struct SyncMutationRPCResponse: Decodable, Sendable {
    var protocolVersion: Int
    var mutationId: UUID
    var outcome: SyncMutationOutcome
    var entityType: String
    var requestedEntityId: UUID
    var canonicalEntityId: UUID?
    var ownerId: UUID
    var subjectProfileId: UUID?
    var committedVersion: Int64?
    var serverUpdatedAt: String?
    var canonicalRow: AnyJSON?
    var affectedDescendants: [SyncAffectedEntity]?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case mutationId = "mutation_id"
        case outcome
        case entityType = "entity_type"
        case requestedEntityId = "requested_entity_id"
        case canonicalEntityId = "canonical_entity_id"
        case ownerId = "owner_id"
        case subjectProfileId = "subject_profile_id"
        case committedVersion = "committed_version"
        case serverUpdatedAt = "server_updated_at"
        case canonicalRow = "canonical_row"
        case affectedDescendants = "affected_descendants"
        case reason
    }
}

struct SyncAffectedEntity: Codable, Equatable, Sendable {
    var entityType: String
    var entityId: UUID
    var committedVersion: Int64

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId = "entity_id"
        case committedVersion = "committed_version"
    }
}

enum SyncProtocolValidation {
    static func responseMatches(
        _ response: SyncMutationRPCResponse,
        work: SyncMutationWorkItem
    ) -> Bool {
        response.protocolVersion == 1
            && response.mutationId == work.mutationId
            && response.entityType == work.entityType.rawValue
            && response.requestedEntityId == work.transportEntityId
            && response.ownerId == work.ownerId
            && response.subjectProfileId == work.subjectProfileId
            && response.outcome.isAcknowledgement
            && (response.outcome == .alreadyDeleted || response.committedVersion != nil)
    }
}

enum SyncWireCodec {
    static func timestamp(_ date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    static func dayStamp(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        fractionalFormatter.date(from: value)
            ?? internetFormatter.date(from: value)
            ?? dayFormatter.date(from: String(value.prefix(10)))
    }

    static func data(from value: AnyJSON?) throws -> Data? {
        guard let value, !value.isNil else { return nil }
        return try JSONEncoder().encode(value)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = Self.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid server date"
                )
            }
            return date
        }
        return decoder
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetFormatter: ISO8601DateFormatter = {
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
