import Foundation
import SwiftData

struct TreatmentSnapshot: Sendable {
    var id: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var title: String
    var status: String
    var startDate: Date
    var endDate: Date?
    var updatedAt: Date
    var deletedAt: Date?
}

struct MedicineSnapshot: Sendable {
    var id: UUID
    var treatmentId: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var name: String
    var doseLabel: String
    var frequency: String
    var duration: String
    var updatedAt: Date
    var deletedAt: Date?
}

struct DoseScheduleSnapshot: Sendable {
    var id: UUID
    var medicineId: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var timeOfDay: String
    var period: String
    var updatedAt: Date
    var deletedAt: Date?
}

struct DoseLogSnapshot: Sendable {
    var id: UUID
    var scheduleId: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var scheduledAt: Date
    var status: String
    var loggedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?
}

@Model
final class TreatmentRecord {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var title: String
    var status: String
    var startDate: Date
    var endDate: Date?
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        ownerId: UUID? = nil,
        profileId: UUID? = nil,
        title: String,
        status: String = "active",
        startDate: Date = Date(),
        endDate: Date? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.profileId = profileId
        self.title = title
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    convenience init(snapshot: TreatmentSnapshot) {
        self.init(
            id: snapshot.id,
            ownerId: snapshot.ownerId,
            profileId: snapshot.profileId,
            title: snapshot.title,
            status: snapshot.status,
            startDate: snapshot.startDate,
            endDate: snapshot.endDate,
            updatedAt: snapshot.updatedAt,
            deletedAt: snapshot.deletedAt
        )
    }

    var snapshot: TreatmentSnapshot {
        TreatmentSnapshot(
            id: id,
            ownerId: ownerId,
            profileId: profileId,
            title: title,
            status: status,
            startDate: startDate,
            endDate: endDate,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    func apply(_ snapshot: TreatmentSnapshot) {
        ownerId = snapshot.ownerId
        profileId = snapshot.profileId
        title = snapshot.title
        status = snapshot.status
        startDate = snapshot.startDate
        endDate = snapshot.endDate
        updatedAt = snapshot.updatedAt
        deletedAt = snapshot.deletedAt
    }
}

@Model
final class MedicineRecord {
    @Attribute(.unique) var id: UUID
    var treatmentId: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var name: String
    var doseLabel: String
    var frequency: String
    var duration: String
    var reason: String = ""
    var form: String = MedicineForm.other.rawValue
    var packageAmount: Double = 0
    var packageUnit: String = MedicineUnit.tablet.rawValue
    var stockPercent: Double = 100
    var quantityPerDose: Double = 1
    var doseUnit: String = MedicineUnit.tablet.rawValue
    var doctorName: String = ""
    var doctorId: String = ""
    var hospitalName: String = ""
    var doctorNotes: String = ""
    var lastRefillAt: Date? = nil
    var refillRemindEnabled: Bool = true
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        treatmentId: UUID,
        ownerId: UUID? = nil,
        profileId: UUID? = nil,
        name: String,
        doseLabel: String,
        frequency: String,
        duration: String,
        reason: String = "",
        form: String = MedicineForm.other.rawValue,
        packageAmount: Double = 0,
        packageUnit: String = MedicineUnit.tablet.rawValue,
        stockPercent: Double = 100,
        quantityPerDose: Double = 1,
        doseUnit: String = MedicineUnit.tablet.rawValue,
        doctorName: String = "",
        doctorId: String = "",
        hospitalName: String = "",
        doctorNotes: String = "",
        lastRefillAt: Date? = nil,
        refillRemindEnabled: Bool = true,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treatmentId = treatmentId
        self.ownerId = ownerId
        self.profileId = profileId
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
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    convenience init(snapshot: MedicineSnapshot) {
        self.init(
            id: snapshot.id,
            treatmentId: snapshot.treatmentId,
            ownerId: snapshot.ownerId,
            profileId: snapshot.profileId,
            name: snapshot.name,
            doseLabel: snapshot.doseLabel,
            frequency: snapshot.frequency,
            duration: snapshot.duration,
            updatedAt: snapshot.updatedAt,
            deletedAt: snapshot.deletedAt
        )
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

    func apply(_ snapshot: MedicineSnapshot) {
        treatmentId = snapshot.treatmentId
        ownerId = snapshot.ownerId
        profileId = snapshot.profileId
        name = snapshot.name
        doseLabel = snapshot.doseLabel
        frequency = snapshot.frequency
        duration = snapshot.duration
        updatedAt = snapshot.updatedAt
        deletedAt = snapshot.deletedAt
    }

    var medicineForm: MedicineForm {
        MedicineForm(rawValue: form) ?? .other
    }

    var packageMedicineUnit: MedicineUnit {
        MedicineUnit(rawValue: packageUnit) ?? .tablet
    }

    var doseMedicineUnit: MedicineUnit {
        MedicineUnit(rawValue: doseUnit) ?? .tablet
    }

    func applyDoseDefaultsIfNeeded() {
        let parsed = MedicineUnits.parseDoseLabel(doseLabel)
        if quantityPerDose <= 0, quantityPerDose != parsed.quantity {
            FreezeDiag.log("SWIFTDATA WRITE START source=applyDoseDefaultsIfNeeded.quantityPerDose")
            FreezeDiag.log("SWIFTDATA WRITE object=\(id) kind=update medicine=\(id) oldStatus=- newStatus=- scheduledAt=- quantityPerDose \(quantityPerDose)->\(parsed.quantity)")
            quantityPerDose = parsed.quantity
            FreezeDiag.log("SWIFTDATA WRITE END source=applyDoseDefaultsIfNeeded.quantityPerDose")
        }
        if doseUnit.isEmpty || doseUnit == MedicineUnit.other.rawValue {
            let next = parsed.unit.rawValue
            if doseUnit != next {
                FreezeDiag.log("SWIFTDATA WRITE START source=applyDoseDefaultsIfNeeded.doseUnit")
                FreezeDiag.log("SWIFTDATA WRITE object=\(id) kind=update medicine=\(id) oldStatus=- newStatus=- scheduledAt=- doseUnit '\(doseUnit)'->'\(next)'")
                doseUnit = next
                FreezeDiag.log("SWIFTDATA WRITE END source=applyDoseDefaultsIfNeeded.doseUnit")
            }
        }
        if form.isEmpty || form == MedicineForm.other.rawValue {
            let inferred = MedicineForm.infer(from: doseLabel, medicineName: name).rawValue
            if form != inferred {
                FreezeDiag.log("SWIFTDATA WRITE START source=applyDoseDefaultsIfNeeded.form")
                FreezeDiag.log("SWIFTDATA WRITE object=\(id) kind=update medicine=\(id) oldStatus=- newStatus=- scheduledAt=- form '\(form)'->'\(inferred)'")
                form = inferred
                FreezeDiag.log("SWIFTDATA WRITE END source=applyDoseDefaultsIfNeeded.form")
            }
        }
        // Never invent package size — refill stays incomplete until the user or scan provides it.
    }
}

@Model
final class DoseScheduleRecord {
    @Attribute(.unique) var id: UUID
    var medicineId: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var timeOfDay: String
    var period: String
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        medicineId: UUID,
        ownerId: UUID? = nil,
        profileId: UUID? = nil,
        timeOfDay: String,
        period: String,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.medicineId = medicineId
        self.ownerId = ownerId
        self.profileId = profileId
        self.timeOfDay = timeOfDay
        self.period = period
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    convenience init(snapshot: DoseScheduleSnapshot) {
        self.init(
            id: snapshot.id,
            medicineId: snapshot.medicineId,
            ownerId: snapshot.ownerId,
            profileId: snapshot.profileId,
            timeOfDay: snapshot.timeOfDay,
            period: snapshot.period,
            updatedAt: snapshot.updatedAt,
            deletedAt: snapshot.deletedAt
        )
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

    func apply(_ snapshot: DoseScheduleSnapshot) {
        medicineId = snapshot.medicineId
        ownerId = snapshot.ownerId
        profileId = snapshot.profileId
        timeOfDay = snapshot.timeOfDay
        period = snapshot.period
        updatedAt = snapshot.updatedAt
        deletedAt = snapshot.deletedAt
    }
}

@Model
final class DoseLogRecord {
    @Attribute(.unique) var id: UUID
    var scheduleId: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var scheduledAt: Date
    var status: String
    var loggedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        scheduleId: UUID,
        ownerId: UUID? = nil,
        profileId: UUID? = nil,
        scheduledAt: Date,
        status: String = DoseLogStatus.pending.rawValue,
        loggedAt: Date? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.scheduleId = scheduleId
        self.ownerId = ownerId
        self.profileId = profileId
        self.scheduledAt = scheduledAt
        self.status = status
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    convenience init(snapshot: DoseLogSnapshot) {
        self.init(
            id: snapshot.id,
            scheduleId: snapshot.scheduleId,
            ownerId: snapshot.ownerId,
            profileId: snapshot.profileId,
            scheduledAt: snapshot.scheduledAt,
            status: snapshot.status,
            loggedAt: snapshot.loggedAt,
            updatedAt: snapshot.updatedAt,
            deletedAt: snapshot.deletedAt
        )
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

    func apply(_ snapshot: DoseLogSnapshot) {
        if scheduleId != snapshot.scheduleId { scheduleId = snapshot.scheduleId }
        if ownerId != snapshot.ownerId { ownerId = snapshot.ownerId }
        if profileId != snapshot.profileId { profileId = snapshot.profileId }
        if scheduledAt != snapshot.scheduledAt { scheduledAt = snapshot.scheduledAt }
        if status != snapshot.status { status = snapshot.status }
        if loggedAt != snapshot.loggedAt { loggedAt = snapshot.loggedAt }
        if updatedAt != snapshot.updatedAt { updatedAt = snapshot.updatedAt }
        if deletedAt != snapshot.deletedAt { deletedAt = snapshot.deletedAt }
    }
}

enum FeelingMood: String, CaseIterable, Identifiable, Codable, Sendable {
    case great
    case okay
    case low
    case sideEffect

    var id: String { rawValue }

    func title(_ session: SessionStore) -> String {
        switch self {
        case .great: session.t(.feelingGreat)
        case .okay: session.t(.feelingOkay)
        case .low: session.t(.feelingLow)
        case .sideEffect: session.t(.feelingSideEffect)
        }
    }
}

enum SyncMutationEntity: String, CaseIterable, Sendable {
    case treatment
    case medicine
    case schedule
    case doseLog
}

enum SyncMutationOperation: String, Sendable {
    case upsert
    case delete
}

enum SyncMutationState: String, Sendable {
    case pending
    case acknowledged
}

/// Durable local intent only. Batch 2B-2 never uploads or acknowledges these rows.
@Model
final class SyncMutationRecord {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID
    var subjectProfileId: UUID?
    var entityType: String
    var entityId: UUID
    var operation: String
    var baseVersion: Int64?
    var state: String
    var createdAt: Date
    var lastChangedAt: Date

    init(
        id: UUID = UUID(),
        ownerId: UUID,
        subjectProfileId: UUID?,
        entityType: SyncMutationEntity,
        entityId: UUID,
        operation: SyncMutationOperation,
        baseVersion: Int64? = nil,
        state: SyncMutationState = .pending,
        createdAt: Date = Date(),
        lastChangedAt: Date = Date()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.subjectProfileId = subjectProfileId
        self.entityType = entityType.rawValue
        self.entityId = entityId
        self.operation = operation.rawValue
        self.baseVersion = baseVersion
        self.state = state.rawValue
        self.createdAt = createdAt
        self.lastChangedAt = lastChangedAt
    }
}

protocol SyncOutboxCanonicalRecord: AnyObject {
    var id: UUID { get }
    var ownerId: UUID? { get }
    var profileId: UUID? { get }
    var deletedAt: Date? { get }
    var syncMutationEntity: SyncMutationEntity { get }
}

extension TreatmentRecord: SyncOutboxCanonicalRecord {
    var syncMutationEntity: SyncMutationEntity { .treatment }
}

extension MedicineRecord: SyncOutboxCanonicalRecord {
    var syncMutationEntity: SyncMutationEntity { .medicine }
}

extension DoseScheduleRecord: SyncOutboxCanonicalRecord {
    var syncMutationEntity: SyncMutationEntity { .schedule }
}

extension DoseLogRecord: SyncOutboxCanonicalRecord {
    var syncMutationEntity: SyncMutationEntity { .doseLog }
}

@MainActor
enum SyncMutationOutbox {
    static let legacyUploaderMayAcknowledge = false

    static func stage(
        _ records: [any SyncOutboxCanonicalRecord],
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        for record in records {
            guard let ownerId = record.ownerId else { continue }
            let pending = SyncMutationState.pending.rawValue
            let descriptor = FetchDescriptor<SyncMutationRecord>(
                predicate: #Predicate { row in
                    row.ownerId == ownerId && row.state == pending
                }
            )
            let existing = try context.fetch(descriptor).first {
                $0.entityType == record.syncMutationEntity.rawValue
                    && $0.entityId == record.id
            }
            let operation: SyncMutationOperation = record.deletedAt == nil ? .upsert : .delete
            if let existing {
                if existing.subjectProfileId != record.profileId {
                    existing.subjectProfileId = record.profileId
                }
                if existing.operation != operation.rawValue {
                    existing.operation = operation.rawValue
                }
                existing.lastChangedAt = now
            } else {
                let mutation = SyncMutationRecord(
                    ownerId: ownerId,
                    subjectProfileId: record.profileId,
                    entityType: record.syncMutationEntity,
                    entityId: record.id,
                    operation: operation,
                    createdAt: now,
                    lastChangedAt: now
                )
                context.insert(mutation)
            }
        }
    }

    static func pending(ownerId: UUID, in context: ModelContext) throws -> [SyncMutationRecord] {
        let pending = SyncMutationState.pending.rawValue
        let descriptor = FetchDescriptor<SyncMutationRecord>(
            predicate: #Predicate { row in
                row.ownerId == ownerId && row.state == pending
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    static func removeAll(ownerId: UUID, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<SyncMutationRecord>(
            predicate: #Predicate { row in row.ownerId == ownerId }
        )
        for row in try context.fetch(descriptor) {
            context.delete(row)
        }
    }

    static func reassignOwner(
        from previousOwnerId: UUID,
        to newOwnerId: UUID,
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        for row in try pending(ownerId: previousOwnerId, in: context) {
            row.ownerId = newOwnerId
            row.lastChangedAt = now
        }
    }
}

@Model
final class FeelingRecord {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID?
    var profileId: UUID?
    var logId: UUID?
    var medicineName: String
    var mood: String
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        ownerId: UUID? = nil,
        profileId: UUID? = nil,
        logId: UUID? = nil,
        medicineName: String,
        mood: String,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.profileId = profileId
        self.logId = logId
        self.medicineName = medicineName
        self.mood = mood
        self.note = note
        self.createdAt = createdAt
    }
}

@Model
final class RewardGrant {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID?
    var profileId: UUID?
    @Attribute(.unique) var eventKey: String
    var kind: String
    var xp: Int
    var achievementId: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        ownerId: UUID? = nil,
        profileId: UUID? = nil,
        eventKey: String,
        kind: String,
        xp: Int,
        achievementId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.profileId = profileId
        self.eventKey = eventKey
        self.kind = kind
        self.xp = xp
        self.achievementId = achievementId
        self.createdAt = createdAt
    }
}

@Model
final class CommunityCommentRecord {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID?
    var medicineKey: String
    var author: String
    var body: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        ownerId: UUID? = nil,
        medicineKey: String,
        author: String,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.medicineKey = medicineKey
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}

enum PhilPlanStatus: String, Codable, Sendable {
    case loading
    case creating
    case active
    case needsUpdate
    case error

    /// Creating UI is not a persisted plan.
    var planExists: Bool {
        self == .active || self == .needsUpdate
    }
}

@Model
final class PhilPlanRecord {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID
    var status: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerId: UUID,
        status: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.status = status
        self.updatedAt = updatedAt
    }
}
