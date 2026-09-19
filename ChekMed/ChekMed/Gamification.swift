import Foundation

/// Read-only overlay on existing DoseLog / adherence data.
/// Never writes SwiftData. Never confirms, creates, or edits doses.
enum Gamification {
    static let milestoneDays = [1, 3, 7, 14, 21, 30, 60, 90]
    /// Phase 1 overlay reactions only.
    static let reactionMilestones = [1, 3, 7]

    /// Same past-day rule as `CheckMedStore.streakDays`:
    /// a past day counts when it has at least one confirmed-taken log and no open or missed-like logs.
    /// Today counts when at least one log is confirmed taken (existing streak, not a new medical rule).
    static func dayContributesToStreak(
        statuses: [DoseLogStatus],
        isToday: Bool
    ) -> Bool {
        if statuses.isEmpty { return false }
        if isToday {
            return statuses.contains { $0.isConfirmedTaken }
        }
        let broken = statuses.contains { $0.isOpen || $0.isMissedLike }
        if broken { return false }
        return statuses.contains { $0.isConfirmedTaken }
    }

    static func snapshot(
        nodes: [DoseNode],
        currentStreak: Int,
        longestStreak: Int,
        hasActiveTreatment: Bool,
        todayTaken: Int? = nil,
        todayScheduled: Int? = nil
    ) -> GamificationSnapshot {
        guard hasActiveTreatment else {
            return .inactive
        }
        let nodeTaken = nodes.filter { $0.status == .done }.count
        let nodeSkipped = nodes.filter { $0.status == .skipped }.count
        let remaining = nodes.filter { $0.status != .done && $0.status != .skipped }.count
        let taken = todayTaken ?? nodeTaken
        let required = max(todayScheduled ?? 0, nodes.count)
        let absentFromPath = max(0, required - nodes.count)
        let skipped = nodeSkipped + absentFromPath
        let complete = required > 0 && taken == required
        let needsAttention = skipped > 0 && !complete
        let lines: [ChallengeDoseLine] = nodes.map { node in
            ChallengeDoseLine(
                id: node.id,
                medicine: node.medicine,
                detail: node.detail,
                time: node.time,
                isTaken: node.status == .done,
                isMissed: node.status == .skipped
            )
        }
        let reached = milestoneDays.filter { currentStreak >= $0 }
        let next = milestoneDays.first { $0 > currentStreak }
        let coach = coachContext(
            required: required,
            taken: taken,
            remaining: remaining,
            complete: complete,
            needsAttention: needsAttention,
            currentStreak: currentStreak,
            longestStreak: longestStreak
        )
        return GamificationSnapshot(
            isActive: true,
            requiredCount: required,
            takenCount: taken,
            remainingCount: remaining,
            skippedCount: skipped,
            isComplete: complete,
            needsAttention: needsAttention,
            hasScheduledDoses: required > 0,
            currentStreak: max(0, currentStreak),
            longestStreak: max(currentStreak, longestStreak),
            lines: lines,
            coach: coach,
            reachedMilestones: reached,
            nextMilestone: next
        )
    }

    static func highestMilestone(atOrBelow streak: Int) -> Int {
        reactionMilestones.last { $0 <= streak } ?? 0
    }

    static func philDoseReaction(takenCount: Int) -> GameCelebrate {
        if takenCount <= 1 { return .tookFirst }
        if takenCount == 2 { return .tookOnTrack }
        return .tookKeepGoing
    }

    private static func coachContext(
        required: Int,
        taken: Int,
        remaining: Int,
        complete: Bool,
        needsAttention: Bool,
        currentStreak: Int,
        longestStreak: Int
    ) -> PhilCoachContext {
        if required == 0 {
            return .idle
        }
        if needsAttention {
            return .needsAttention
        }
        if complete {
            if reactionMilestones.contains(currentStreak) {
                return .milestone(currentStreak)
            }
            return .challengeComplete
        }
        if taken == 0, currentStreak <= 1 {
            return .firstDay
        }
        if taken > 0, currentStreak == 1, longestStreak > 1 {
            return .backOnTrack
        }
        if remaining > 0 {
            return .inProgress(remaining: remaining)
        }
        return .idle
    }
}

struct ChallengeDoseLine: Equatable, Identifiable, Sendable {
    var id: String
    var medicine: String
    var detail: String
    var time: String
    var isTaken: Bool
    var isMissed: Bool
}

enum PhilCoachContext: Equatable, Sendable {
    case idle
    case firstDay
    case inProgress(remaining: Int)
    case challengeComplete
    case needsAttention
    case backOnTrack
    case milestone(Int)
}

struct GamificationSnapshot: Equatable, Sendable {
    var isActive: Bool
    var requiredCount: Int
    var takenCount: Int
    var remainingCount: Int
    var skippedCount: Int
    var isComplete: Bool
    var needsAttention: Bool
    var hasScheduledDoses: Bool
    var currentStreak: Int
    var longestStreak: Int
    var lines: [ChallengeDoseLine]
    var coach: PhilCoachContext
    var reachedMilestones: [Int]
    var nextMilestone: Int?

    static let inactive = GamificationSnapshot(
        isActive: false,
        requiredCount: 0,
        takenCount: 0,
        remainingCount: 0,
        skippedCount: 0,
        isComplete: false,
        needsAttention: false,
        hasScheduledDoses: false,
        currentStreak: 0,
        longestStreak: 0,
        lines: [],
        coach: .idle,
        reachedMilestones: [],
        nextMilestone: 1
    )

    var progressFraction: Double {
        guard requiredCount > 0 else { return 0 }
        return Double(takenCount) / Double(requiredCount)
    }

    var doneSignature: String {
        lines.filter(\.isTaken).map(\.id).sorted().joined(separator: ",")
    }
}

enum GameCelebrate: Equatable {
    case tookFirst
    case tookOnTrack
    case tookKeepGoing
    case dayComplete
    case milestone(Int)
    case needsAttention
    case backOnTrack
}

/// UserDefaults only — celebration idempotency, never a second source of dose truth.
enum GamificationMemory {
    static func seedIfNeeded(ownerId: UUID, profileId: UUID, streak: Int, dayStamp: String, doneSignature: String) {
        let defaults = UserDefaults.standard
        let seedKey = key("seeded", ownerId, profileId)
        if defaults.bool(forKey: seedKey) { return }
        defaults.set(true, forKey: seedKey)
        defaults.set(Gamification.highestMilestone(atOrBelow: streak), forKey: key("milestone", ownerId, profileId))
        defaults.set(dayStamp, forKey: key("completeDay", ownerId, profileId))
        defaults.set(doneSignature, forKey: key("doneSig", ownerId, profileId))
        defaults.set(streak, forKey: key("streak", ownerId, profileId))
    }

    static func lastMilestone(ownerId: UUID, profileId: UUID) -> Int {
        UserDefaults.standard.integer(forKey: key("milestone", ownerId, profileId))
    }

    static func markMilestone(ownerId: UUID, profileId: UUID, day: Int) {
        let current = lastMilestone(ownerId: ownerId, profileId: profileId)
        if day > current {
            UserDefaults.standard.set(day, forKey: key("milestone", ownerId, profileId))
        }
    }

    static func didCelebrateComplete(ownerId: UUID, profileId: UUID, dayStamp: String) -> Bool {
        UserDefaults.standard.string(forKey: key("completeDay", ownerId, profileId)) == dayStamp
    }

    static func markComplete(ownerId: UUID, profileId: UUID, dayStamp: String) {
        if didCelebrateComplete(ownerId: ownerId, profileId: profileId, dayStamp: dayStamp) { return }
        UserDefaults.standard.set(dayStamp, forKey: key("completeDay", ownerId, profileId))
    }

    static func lastDoneSignature(ownerId: UUID, profileId: UUID) -> String {
        UserDefaults.standard.string(forKey: key("doneSig", ownerId, profileId)) ?? ""
    }

    static func markDoneSignature(ownerId: UUID, profileId: UUID, signature: String) {
        if lastDoneSignature(ownerId: ownerId, profileId: profileId) == signature { return }
        UserDefaults.standard.set(signature, forKey: key("doneSig", ownerId, profileId))
    }

    private static func key(_ name: String, _ ownerId: UUID, _ profileId: UUID) -> String {
        "checkmed.game.\(name).\(ownerId.uuidString).\(profileId.uuidString)"
    }
}

#if DEBUG
enum GamificationContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        let a = DoseNode(id: "1", time: "08:00", medicine: "A", detail: "1 tab", status: .done)
        let b = DoseNode(id: "2", time: "14:00", medicine: "B", detail: "1 tab", status: .current)
        let snap = Gamification.snapshot(
            nodes: [a, b],
            currentStreak: 2,
            longestStreak: 5,
            hasActiveTreatment: true
        )
        expect(snap.takenCount == 1 && snap.requiredCount == 2, "challenge counts dose events not medicines")
        expect(!snap.isComplete, "incomplete until every scheduled dose is taken")
        let missed = DoseNode(id: "3", time: "20:00", medicine: "C", detail: "1 tab", status: .skipped)
        let sevenTaken = (1...7).map { DoseNode(id: "t\($0)", time: "08:00", medicine: "M\($0)", status: .done) }
        let incomplete = Gamification.snapshot(
            nodes: sevenTaken + [missed],
            currentStreak: 1,
            longestStreak: 1,
            hasActiveTreatment: true,
            todayTaken: 7,
            todayScheduled: 8
        )
        expect(incomplete.requiredCount == 8 && incomplete.takenCount == 7, "missed stays in denominator")
        expect(!incomplete.isComplete && incomplete.needsAttention, "7/8 is not challenge complete")
        let absentMissed = Gamification.snapshot(
            nodes: sevenTaken,
            currentStreak: 1,
            longestStreak: 1,
            hasActiveTreatment: true,
            todayTaken: 7,
            todayScheduled: 8
        )
        expect(absentMissed.requiredCount == 8 && !absentMissed.isComplete && absentMissed.needsAttention, "missed logs missing from path still keep denominator")
        let eightTaken = (1...8).map { DoseNode(id: "d\($0)", time: "08:00", medicine: "M\($0)", status: .done) }
        let completeDay = Gamification.snapshot(
            nodes: eightTaken,
            currentStreak: 1,
            longestStreak: 1,
            hasActiveTreatment: true,
            todayTaken: 8,
            todayScheduled: 8
        )
        expect(completeDay.isComplete && !completeDay.needsAttention, "8/8 is challenge complete")
        let withFuture = Gamification.snapshot(
            nodes: sevenTaken + [DoseNode(id: "f", time: "21:00", medicine: "Later", status: .locked)],
            currentStreak: 1,
            longestStreak: 1,
            hasActiveTreatment: true,
            todayTaken: 7,
            todayScheduled: 8
        )
        expect(!withFuture.isComplete && !withFuture.needsAttention && withFuture.remainingCount == 1, "future remaining is not missed")
        expect(Gamification.snapshot(nodes: [], currentStreak: 0, longestStreak: 0, hasActiveTreatment: false).isActive == false, "no fake challenge without treatment")
        expect(Gamification.dayContributesToStreak(statuses: [.taken], isToday: true), "today counts on first taken")
        expect(!Gamification.dayContributesToStreak(statuses: [.taken, .missed], isToday: false), "past missed day does not count")
        return failures
    }
}
#endif
