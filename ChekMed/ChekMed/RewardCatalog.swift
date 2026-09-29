import Foundation

/// Code-defined reward table. Definitions are not SwiftData rows.
enum RewardCatalog {
    enum XPEvent: String, Equatable, Sendable {
        case doseTaken = "dose_taken"
        case doseTakenLate = "dose_taken_late"
        case dayComplete = "day_complete"
        case streak1 = "streak_1"
        case streak3 = "streak_3"
        case streak7 = "streak_7"
        case streak14 = "streak_14"
        case streak30 = "streak_30"
        case streak90 = "streak_90"
        case treatmentComplete = "treatment_complete"
    }

    enum Achievement: String, Equatable, Sendable {
        case firstDose = "first_dose"
        case firstDay = "first_day"
        case firstRecovery = "first_recovery"
        case firstTreatmentComplete = "first_treatment_complete"
        case streak1 = "streak_1"
        case streak3 = "streak_3"
        case streak7 = "streak_7"
        case streak14 = "streak_14"
        case streak30 = "streak_30"
        case streak90 = "streak_90"
    }

    static let streakThresholds: [Int] = [1, 3, 7, 14, 30, 90]

    static func xp(for event: XPEvent) -> Int {
        switch event {
        case .doseTaken: 10
        case .doseTakenLate: 5
        case .dayComplete: 20
        case .streak1: 15
        case .streak3: 25
        case .streak7: 40
        case .streak14: 50
        case .streak30: 80
        case .streak90: 120
        case .treatmentComplete: 50
        }
    }

    static func streakEvent(_ n: Int) -> XPEvent? {
        switch n {
        case 1: .streak1
        case 3: .streak3
        case 7: .streak7
        case 14: .streak14
        case 30: .streak30
        case 90: .streak90
        default: nil
        }
    }

    static func streakAchievement(_ n: Int) -> Achievement? {
        switch n {
        case 1: .streak1
        case 3: .streak3
        case 7: .streak7
        case 14: .streak14
        case 30: .streak30
        case 90: .streak90
        default: nil
        }
    }

    static func doseEventKey(logId: UUID) -> String {
        "xp.dose.\(logId.uuidString)"
    }

    static func dayEventKey(ownerId: UUID, profileId: UUID, dayStamp: String) -> String {
        "xp.day.\(ownerId.uuidString).\(profileId.uuidString).\(dayStamp)"
    }

    static func streakEventKey(ownerId: UUID, profileId: UUID, n: Int) -> String {
        "xp.streak.\(ownerId.uuidString).\(profileId.uuidString).\(n)"
    }

    static func treatmentEventKey(treatmentId: UUID) -> String {
        "xp.treatment.\(treatmentId.uuidString)"
    }

    static func achievementEventKey(ownerId: UUID, profileId: UUID, achievement: Achievement) -> String {
        "ach.\(ownerId.uuidString).\(profileId.uuidString).\(achievement.rawValue)"
    }

    static func dayStamp(now: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}
