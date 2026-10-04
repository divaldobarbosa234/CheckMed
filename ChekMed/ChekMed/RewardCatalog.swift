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

    enum Achievement: String, Equatable, Sendable, CaseIterable {
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

    /// Read-only gallery row. Unlock comes from existing RewardGrant rows only.
    struct AchievementGalleryItem: Equatable, Identifiable, Sendable {
        var achievement: Achievement
        var unlockedAt: Date?
        var id: String { achievement.rawValue }
        var isUnlocked: Bool { unlockedAt != nil }
    }

    /// Catalog order for Your Progress. Does not award grants.
    static func galleryItems(
        fromGrantFacts facts: [(achievementId: String?, createdAt: Date)]
    ) -> [AchievementGalleryItem] {
        var unlocked: [Achievement: Date] = [:]
        for fact in facts {
            guard let raw = fact.achievementId,
                  let achievement = Achievement(rawValue: raw) else { continue }
            if let existing = unlocked[achievement] {
                if fact.createdAt < existing {
                    unlocked[achievement] = fact.createdAt
                }
            } else {
                unlocked[achievement] = fact.createdAt
            }
        }
        return Achievement.allCases.map { achievement in
            AchievementGalleryItem(achievement: achievement, unlockedAt: unlocked[achievement])
        }
    }

    static func gallerySymbolName(for achievement: Achievement) -> String {
        switch achievement {
        case .firstDose: "pills.fill"
        case .firstDay: "sun.max.fill"
        case .firstRecovery: "arrow.uturn.forward.circle.fill"
        case .firstTreatmentComplete: "flag.checkered"
        case .streak1: "flame"
        case .streak3: "flame.fill"
        case .streak7: "calendar"
        case .streak14: "calendar.badge.checkmark"
        case .streak30: "star.fill"
        case .streak90: "trophy.fill"
        }
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

    /// Cumulative XP required to *enter* each level. Index 0 is Level 1.
    /// Append later rungs; do not reorder released thresholds.
    static let levelThresholds: [Int] = [0, 50, 150, 300, 500, 800, 1200, 1800, 2500, 3500]

    static func totalXP(fromGrantAmounts amounts: [Int]) -> Int {
        amounts.reduce(0) { $0 + max(0, $1) }
    }

    static func progress(totalXP: Int) -> RewardProgress {
        RewardProgress.from(totalXP: totalXP, thresholds: levelThresholds)
    }
}

/// Derived from the RewardGrant XP sum. Not persisted.
struct RewardProgress: Equatable, Sendable {
    var totalXP: Int
    var currentLevel: Int
    var xpAtCurrentLevelStart: Int
    var xpAtNextLevel: Int?
    var xpIntoLevel: Int
    var xpNeededForNext: Int
    var progressFraction: Double
    var isMaxDefinedLevel: Bool

    static func from(totalXP: Int, thresholds: [Int]) -> RewardProgress {
        let xp = max(0, totalXP)
        let rungs = thresholds.isEmpty ? [0] : thresholds
        var index = 0
        for i in rungs.indices where xp >= rungs[i] {
            index = i
        }
        let start = rungs[index]
        let level = index + 1
        let atMax = index == rungs.count - 1
        if atMax {
            return RewardProgress(
                totalXP: xp,
                currentLevel: level,
                xpAtCurrentLevelStart: start,
                xpAtNextLevel: nil,
                xpIntoLevel: xp - start,
                xpNeededForNext: 0,
                progressFraction: 1.0,
                isMaxDefinedLevel: true
            )
        }
        let next = rungs[index + 1]
        let span = next - start
        let into = xp - start
        let fraction: Double
        if span <= 0 {
            fraction = 1.0
        } else {
            fraction = min(1.0, max(0.0, Double(into) / Double(span)))
        }
        return RewardProgress(
            totalXP: xp,
            currentLevel: level,
            xpAtCurrentLevelStart: start,
            xpAtNextLevel: next,
            xpIntoLevel: into,
            xpNeededForNext: max(0, next - xp),
            progressFraction: fraction,
            isMaxDefinedLevel: false
        )
    }
}
