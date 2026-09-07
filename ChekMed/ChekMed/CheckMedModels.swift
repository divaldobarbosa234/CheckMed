import Foundation
import SwiftData

enum DoseLogStatus: String, Codable, Sendable {
    case pending
    case taken
    case skipped
}

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
        scheduleId = snapshot.scheduleId
        ownerId = snapshot.ownerId
        profileId = snapshot.profileId
        scheduledAt = snapshot.scheduledAt
        status = snapshot.status
        loggedAt = snapshot.loggedAt
        updatedAt = snapshot.updatedAt
        deletedAt = snapshot.deletedAt
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
