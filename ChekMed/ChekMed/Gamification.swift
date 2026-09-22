import Foundation

/// Read-only overlay on existing DoseLog / adherence data.
/// Never writes SwiftData. Never confirms, creates, or edits doses.
enum Gamification {
    static let milestoneDays = [1, 3, 7, 14, 21, 30, 60, 90]
    /// Phase 1 overlay reactions only.
    static let reactionMilestones = [1, 3, 7]

    /// A day contributes only when every unique scheduled slot is taken or takenLate.
    /// Partial today (any remaining or missed) does not count.
    static func dayContributesToStreak(
        statuses: [DoseLogStatus],
        isToday: Bool
    ) -> Bool {
        _ = isToday
        if statuses.isEmpty { return false }
        if statuses.contains(where: { $0.isOpen || $0.isMissedLike }) { return false }
        return statuses.contains { $0.isConfirmedTaken }
    }

    static func snapshot(
        nodes: [DoseNode],
        currentStreak: Int,
        longestStreak: Int,
        hasActiveTreatment: Bool,
        todayTaken: Int? = nil,
        todayScheduled: Int? = nil,
        todayMissed: Int? = nil
    ) -> GamificationSnapshot {
        guard hasActiveTreatment else {
            return .inactive
        }
        let nodeTaken = nodes.filter { $0.status == .done }.count
        let nodeSkipped = nodes.filter { $0.status == .skipped }.count
        let remainingNodes = nodes.filter { $0.status != .done && $0.status != .skipped }.count
        let taken = todayTaken ?? nodeTaken
        let required = todayScheduled ?? nodes.count
        let absentFromPath = max(0, required - nodes.count)
        let skipped = todayMissed ?? (nodeSkipped + absentFromPath)
        let remaining = todayMissed != nil
            ? max(required - taken - skipped, 0)
            : remainingNodes
        let complete = required > 0 && taken == required && skipped == 0
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
            needsAttention: needsAttention
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

    /// Persistent Dashboard coach. Transient take/milestone toasts stay in Home.
    /// Priority: complete → missed → remaining → upcoming → idle.
    private static func coachContext(
        required: Int,
        taken: Int,
        remaining: Int,
        complete: Bool,
        needsAttention: Bool
    ) -> PhilCoachContext {
        if required == 0 {
            return .idle
        }
        if complete {
            return .challengeComplete
        }
        if needsAttention {
            return .needsAttention
        }
        if remaining > 0 {
            if taken == 0 {
                return .upcoming
            }
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
    case upcoming
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
    case firstDay
    case tookFirst
    case tookOnTrack
    case tookKeepGoing
    case dayComplete
    case milestone(Int)
    case needsAttention
    case backOnTrack
}

enum PhilEvent: Equatable, Sendable {
    case doseConfirmed(id: String, wasMissedLike: Bool)
    case missedAcknowledged
    case dashboardAppeared
}

/// Presentation-only coach memory. Does not store medication truth.
struct PhilCoachMemoryState: Equatable, Sendable {
    var doneSignature: String
    var lastMilestone: Int
    var completeDayStamp: String
    var currentDayStamp: String

    var doneIDs: Set<String> {
        Set(doneSignature.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }
}

/// Presentation/coaching layer. Never writes DoseLogs, streaks, or schedules.
enum PhilCoach {
    static func decision(
        snapshot: GamificationSnapshot,
        event: PhilEvent,
        memory: PhilCoachMemoryState,
        missedSummaryVisible: Bool = false
    ) -> GameCelebrate? {
        switch event {
        case .dashboardAppeared:
            return nil
        case .missedAcknowledged:
            guard !missedSummaryVisible, snapshot.needsAttention else { return nil }
            return .needsAttention
        case .doseConfirmed(let id, let wasMissedLike):
            return doseConfirmedReaction(
                id: id,
                wasMissedLike: wasMissedLike,
                snapshot: snapshot,
                memory: memory
            )
        }
    }

    /// Same lookup as `TodayPathStore.take`: path nodes, then store `todayNodes()`.
    /// Uses pre-confirm `PathStatus` only. Never infers recovery from post-confirm `.takenLate`.
    static func wasMissedLikeBeforeConfirm(
        id: String,
        pathNodes: [DoseNode],
        storeNodes: [DoseNode]
    ) -> Bool {
        let node = pathNodes.first(where: { $0.id == id })
            ?? storeNodes.first(where: { $0.id == id })
        return node?.status == .skipped
    }

    private static func doseConfirmedReaction(
        id: String,
        wasMissedLike: Bool,
        snapshot: GamificationSnapshot,
        memory: PhilCoachMemoryState
    ) -> GameCelebrate? {
        guard snapshot.requiredCount > 0 else { return nil }
        let currentIds = Set(snapshot.lines.filter(\.isTaken).map(\.id))
        var recorded = memory.doneIDs
        if !recorded.isEmpty, recorded.isDisjoint(with: currentIds) {
            recorded = []
        }
        if recorded.contains(id) { return nil }

        // One overlay: recovery that completes the day is completion, not a second toast.
        if wasMissedLike, snapshot.isComplete, memory.completeDayStamp != memory.currentDayStamp {
            return .dayComplete
        }
        if wasMissedLike {
            return .backOnTrack
        }
        if snapshot.isComplete, memory.completeDayStamp != memory.currentDayStamp {
            return .dayComplete
        }
        if Gamification.reactionMilestones.contains(snapshot.currentStreak),
           snapshot.currentStreak > memory.lastMilestone {
            return .milestone(snapshot.currentStreak)
        }
        if snapshot.takenCount == 1, snapshot.currentStreak <= 1 {
            return .firstDay
        }
        return Gamification.philDoseReaction(takenCount: snapshot.takenCount)
    }
}

/// UserDefaults only — celebration idempotency, never a second source of dose truth.
enum GamificationMemory {
    static func seedIfNeeded(ownerId: UUID, profileId: UUID, streak: Int, dayStamp: String, doneSignature: String) {
        _ = dayStamp
        let defaults = UserDefaults.standard
        let seedKey = key("seeded", ownerId, profileId)
        if defaults.bool(forKey: seedKey) { return }
        defaults.set(true, forKey: seedKey)
        defaults.set(Gamification.highestMilestone(atOrBelow: streak), forKey: key("milestone", ownerId, profileId))
        defaults.set(doneSignature, forKey: key("doneSig", ownerId, profileId))
        defaults.set(streak, forKey: key("streak", ownerId, profileId))
        // completeDay is overlay-shown memory only — never stamp it from seed.
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

    static func doneIds(_ signature: String) -> Set<String> {
        Set(signature.split(separator: ",").map(String.init).filter { !$0.isEmpty })
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
        expect(withFuture.coach == .inProgress(remaining: 1), "remaining doses use in-progress coach")
        expect(incomplete.coach == .needsAttention, "missed day uses supportive coach")
        expect(completeDay.coach == .challengeComplete, "8/8 uses day-complete coach")
        let waiting = Gamification.snapshot(
            nodes: [DoseNode(id: "n", time: "21:00", medicine: "Later", status: .locked)],
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: true,
            todayTaken: 0,
            todayScheduled: 1
        )
        expect(waiting.coach == .upcoming, "no taken yet with upcoming dose is waiting coach")
        expect(Gamification.snapshot(nodes: [], currentStreak: 0, longestStreak: 0, hasActiveTreatment: false).coach == .idle, "no treatment is idle")
        expect(Gamification.snapshot(nodes: [], currentStreak: 0, longestStreak: 0, hasActiveTreatment: false).isActive == false, "no fake challenge without treatment")
        expect(Gamification.dayContributesToStreak(statuses: [.taken], isToday: true), "a fully taken day counts")
        expect(!Gamification.dayContributesToStreak(statuses: [.taken, .pending], isToday: true), "incomplete today does not count")
        expect(!Gamification.dayContributesToStreak(statuses: [.taken, .missed], isToday: false), "past missed day does not count")
        expect(Gamification.dayContributesToStreak(statuses: [.taken, .takenLate], isToday: false), "takenLate counts as complete")
        let recoveredLate = Gamification.snapshot(
            nodes: eightTaken,
            currentStreak: 1,
            longestStreak: 1,
            hasActiveTreatment: true,
            todayTaken: 8,
            todayScheduled: 8,
            todayMissed: 0
        )
        expect(recoveredLate.isComplete && recoveredLate.skippedCount == 0, "CHALLENGE CASE 6: takenLate counts as complete, no missed Phil")
        let extraSameDay = eightTaken + [DoseNode(id: "dup", time: "08:00", medicine: "M1", status: .locked)]
        let noReplacement = Gamification.snapshot(
            nodes: extraSameDay,
            currentStreak: 1,
            longestStreak: 1,
            hasActiveTreatment: true,
            todayTaken: 8,
            todayScheduled: 8,
            todayMissed: 0
        )
        expect(
            noReplacement.isComplete && noReplacement.requiredCount == 8 && noReplacement.remainingCount == 0,
            "CHALLENGE CASE 5/8: 8/8 does not open another same-day challenge"
        )
        return failures
    }
}

enum PhilCoachContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let emptyMemory = PhilCoachMemoryState(
            doneSignature: "",
            lastMilestone: 0,
            completeDayStamp: "",
            currentDayStamp: "2026-09-21"
        )

        let none = Gamification.snapshot(
            nodes: [],
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: false
        )
        expect(none.requiredCount == 0, "1. no treatment has no scheduled challenge")
        expect(
            PhilCoach.decision(snapshot: none, event: .doseConfirmed(id: "x", wasMissedLike: false), memory: emptyMemory) == nil,
            "1. no treatment produces no overlay"
        )
        expect(
            PhilCoach.decision(snapshot: none, event: .dashboardAppeared, memory: emptyMemory) == nil,
            "1. dashboard appear produces no overlay"
        )

        let startingNodes = [
            DoseNode(id: "a", time: "08:00", medicine: "A", status: .current),
            DoseNode(id: "b", time: "20:00", medicine: "B", status: .locked),
        ]
        let starting = Gamification.snapshot(
            nodes: startingNodes,
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: true,
            todayTaken: 0,
            todayScheduled: 2
        )
        expect(starting.coach == .upcoming || starting.takenCount == 0, "2. starting day has no taken doses")
        expect(
            PhilCoach.decision(snapshot: starting, event: .dashboardAppeared, memory: emptyMemory) == nil,
            "2. starting day does not overlay from dashboard appear"
        )

        let upcoming = Gamification.snapshot(
            nodes: [DoseNode(id: "n", time: "21:00", medicine: "Later", status: .locked)],
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: true,
            todayTaken: 0,
            todayScheduled: 1
        )
        expect(upcoming.coach == .upcoming, "3. upcoming coach")
        expect(
            PhilCoach.decision(snapshot: upcoming, event: .dashboardAppeared, memory: emptyMemory) == nil,
            "3. upcoming does not overlay from render"
        )

        let firstTaken = Gamification.snapshot(
            nodes: [
                DoseNode(id: "a", time: "08:00", medicine: "A", status: .done),
                DoseNode(id: "b", time: "20:00", medicine: "B", status: .locked),
            ],
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: true,
            todayTaken: 1,
            todayScheduled: 2
        )
        expect(
            PhilCoach.decision(snapshot: firstTaken, event: .doseConfirmed(id: "a", wasMissedLike: false), memory: emptyMemory) == .firstDay,
            "4. first confirmed dose acknowledges first day"
        )

        let secondTaken = Gamification.snapshot(
            nodes: [
                DoseNode(id: "a", time: "08:00", medicine: "A", status: .done),
                DoseNode(id: "b", time: "14:00", medicine: "B", status: .done),
                DoseNode(id: "c", time: "20:00", medicine: "C", status: .locked),
            ],
            currentStreak: 2,
            longestStreak: 2,
            hasActiveTreatment: true,
            todayTaken: 2,
            todayScheduled: 3
        )
        let afterFirst = PhilCoachMemoryState(
            doneSignature: "a",
            lastMilestone: 1,
            completeDayStamp: "",
            currentDayStamp: "2026-09-21"
        )
        expect(
            PhilCoach.decision(snapshot: secondTaken, event: .doseConfirmed(id: "b", wasMissedLike: false), memory: afterFirst) == .tookOnTrack
                || PhilCoach.decision(snapshot: secondTaken, event: .doseConfirmed(id: "b", wasMissedLike: false), memory: afterFirst) == .tookKeepGoing,
            "5. normal confirmed dose produces a small dose reaction"
        )

        expect(secondTaken.takenCount == 2 && secondTaken.remainingCount == 1 && !secondTaken.isComplete, "6. partial progress is not complete")
        expect(
            PhilCoach.decision(snapshot: secondTaken, event: .dashboardAppeared, memory: afterFirst) == nil,
            "6. partial progress does not overlay from dashboard"
        )

        expect(secondTaken.remainingCount == 1, "7. almost complete has one remaining")

        let oneMissed = Gamification.snapshot(
            nodes: [
                DoseNode(id: "a", time: "08:00", medicine: "A", status: .skipped),
                DoseNode(id: "b", time: "20:00", medicine: "B", status: .locked),
            ],
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: true,
            todayTaken: 0,
            todayScheduled: 2,
            todayMissed: 1
        )
        expect(oneMissed.needsAttention, "8. one missed dose needs attention")
        expect(
            PhilCoach.decision(snapshot: oneMissed, event: .missedAcknowledged, memory: emptyMemory) == .needsAttention,
            "8. missed acknowledged may produce missed reaction"
        )
        expect(
            PhilCoach.decision(
                snapshot: oneMissed,
                event: .missedAcknowledged,
                memory: emptyMemory,
                missedSummaryVisible: true
            ) == nil,
            "8. missed sheet visible suppresses competing overlay"
        )

        let recovered = Gamification.snapshot(
            nodes: [
                DoseNode(id: "a", time: "08:00", medicine: "A", status: .done),
                DoseNode(id: "b", time: "20:00", medicine: "B", status: .locked),
            ],
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: true,
            todayTaken: 1,
            todayScheduled: 2,
            todayMissed: 0
        )
        expect(
            PhilCoach.decision(snapshot: recovered, event: .doseConfirmed(id: "a", wasMissedLike: true), memory: emptyMemory) == .backOnTrack,
            "9. missed → takenLate produces recovery reaction"
        )
        expect(
            PhilCoach.decision(snapshot: recovered, event: .doseConfirmed(id: "a", wasMissedLike: false), memory: emptyMemory) != .backOnTrack,
            "9. a normal take is not a recovery reaction"
        )
        expect(
            PhilCoach.decision(snapshot: recovered, event: .doseConfirmed(id: "a", wasMissedLike: false), memory: emptyMemory) != .backOnTrack
                && (PhilCoach.decision(snapshot: recovered, event: .doseConfirmed(id: "a", wasMissedLike: false), memory: emptyMemory) == .firstDay
                    || PhilCoach.decision(snapshot: recovered, event: .doseConfirmed(id: "a", wasMissedLike: false), memory: emptyMemory) == .tookFirst
                    || PhilCoach.decision(snapshot: recovered, event: .doseConfirmed(id: "a", wasMissedLike: false), memory: emptyMemory) == .tookOnTrack
                    || PhilCoach.decision(snapshot: recovered, event: .doseConfirmed(id: "a", wasMissedLike: false), memory: emptyMemory) == .tookKeepGoing),
            "9. pending/late never-missed confirm is not recovery"
        )

        let emptyPathMissed = DoseNode(id: "miss-1", time: "08:00", medicine: "A", status: .skipped)
        expect(
            PhilCoach.wasMissedLikeBeforeConfirm(id: "miss-1", pathNodes: [], storeNodes: [emptyPathMissed]),
            "empty path.nodes uses store todayNodes skipped as pre-confirm recovery"
        )
        expect(
            !PhilCoach.wasMissedLikeBeforeConfirm(
                id: "late-1",
                pathNodes: [],
                storeNodes: [DoseNode(id: "late-1", time: "08:00", medicine: "A", status: .current)]
            ),
            "empty path pending/current is not recovery"
        )

        let recoveredComplete = Gamification.snapshot(
            nodes: [
                DoseNode(id: "r1", time: "08:00", medicine: "A", status: .done),
                DoseNode(id: "r2", time: "20:00", medicine: "B", status: .done),
            ],
            currentStreak: 2,
            longestStreak: 2,
            hasActiveTreatment: true,
            todayTaken: 2,
            todayScheduled: 2,
            todayMissed: 0
        )
        expect(recoveredComplete.isComplete, "recovery that finishes the day is canonically complete")
        expect(
            PhilCoach.decision(
                snapshot: recoveredComplete,
                event: .doseConfirmed(id: "r2", wasMissedLike: true),
                memory: emptyMemory
            ) == .dayComplete,
            "missed → confirm → complete produces one dayComplete overlay"
        )
        expect(
            PhilCoach.decision(
                snapshot: recoveredComplete,
                event: .doseConfirmed(id: "r2", wasMissedLike: true),
                memory: emptyMemory
            ) != .backOnTrack,
            "completing recovery does not emit a separate backOnTrack overlay"
        )

        let completeNodes = (1...3).map { DoseNode(id: "c\($0)", time: "0\($0):00", medicine: "M", status: .done) }
        let complete = Gamification.snapshot(
            nodes: completeNodes,
            currentStreak: 4,
            longestStreak: 4,
            hasActiveTreatment: true,
            todayTaken: 3,
            todayScheduled: 3
        )
        expect(complete.isComplete, "10. full completion uses canonical isComplete")
        expect(
            PhilCoach.decision(snapshot: complete, event: .doseConfirmed(id: "c3", wasMissedLike: false), memory: afterFirst) == .dayComplete,
            "10. completing the day produces completion reaction"
        )
        let alreadyCompleteMemory = PhilCoachMemoryState(
            doneSignature: "c1,c2,c3",
            lastMilestone: 3,
            completeDayStamp: "2026-09-21",
            currentDayStamp: "2026-09-21"
        )
        expect(
            PhilCoach.decision(snapshot: complete, event: .dashboardAppeared, memory: alreadyCompleteMemory) == nil,
            "10. already-complete day does not replay overlay"
        )

        let day1Complete = Gamification.snapshot(
            nodes: [DoseNode(id: "d1", time: "08:00", medicine: "A", status: .done)],
            currentStreak: 1,
            longestStreak: 1,
            hasActiveTreatment: true,
            todayTaken: 1,
            todayScheduled: 1
        )
        expect(
            PhilCoach.decision(snapshot: day1Complete, event: .doseConfirmed(id: "d1", wasMissedLike: false), memory: emptyMemory) == .dayComplete,
            "11. day 1 completion is not replaced by milestone"
        )
        let day1Partial = Gamification.snapshot(
            nodes: [
                DoseNode(id: "d1", time: "08:00", medicine: "A", status: .done),
                DoseNode(id: "d2", time: "20:00", medicine: "B", status: .locked),
            ],
            currentStreak: 1,
            longestStreak: 1,
            hasActiveTreatment: true,
            todayTaken: 1,
            todayScheduled: 2
        )
        expect(
            PhilCoach.decision(snapshot: day1Partial, event: .doseConfirmed(id: "d1", wasMissedLike: false), memory: emptyMemory) == .milestone(1),
            "11. day 1 milestone only when completion is not also happening"
        )

        let day3 = Gamification.snapshot(
            nodes: [
                DoseNode(id: "x", time: "08:00", medicine: "A", status: .done),
                DoseNode(id: "y", time: "20:00", medicine: "B", status: .locked),
            ],
            currentStreak: 3,
            longestStreak: 3,
            hasActiveTreatment: true,
            todayTaken: 1,
            todayScheduled: 2
        )
        let afterDay1 = PhilCoachMemoryState(
            doneSignature: "",
            lastMilestone: 1,
            completeDayStamp: "",
            currentDayStamp: "2026-09-21"
        )
        expect(
            PhilCoach.decision(snapshot: day3, event: .doseConfirmed(id: "x", wasMissedLike: false), memory: afterDay1) == .milestone(3),
            "12. day 3 milestone overlay"
        )

        let day7 = Gamification.snapshot(
            nodes: [
                DoseNode(id: "x", time: "08:00", medicine: "A", status: .done),
                DoseNode(id: "y", time: "20:00", medicine: "B", status: .locked),
            ],
            currentStreak: 7,
            longestStreak: 7,
            hasActiveTreatment: true,
            todayTaken: 1,
            todayScheduled: 2
        )
        let afterDay3 = PhilCoachMemoryState(
            doneSignature: "",
            lastMilestone: 3,
            completeDayStamp: "",
            currentDayStamp: "2026-09-21"
        )
        expect(
            PhilCoach.decision(snapshot: day7, event: .doseConfirmed(id: "x", wasMissedLike: false), memory: afterDay3) == .milestone(7),
            "13. day 7 milestone overlay"
        )

        let day4Complete = Gamification.snapshot(
            nodes: completeNodes,
            currentStreak: 4,
            longestStreak: 4,
            hasActiveTreatment: true,
            todayTaken: 3,
            todayScheduled: 3
        )
        let afterDay3CompleteMem = PhilCoachMemoryState(
            doneSignature: "c1,c2",
            lastMilestone: 3,
            completeDayStamp: "",
            currentDayStamp: "2026-09-21"
        )
        expect(
            PhilCoach.decision(snapshot: day4Complete, event: .doseConfirmed(id: "c3", wasMissedLike: false), memory: afterDay3CompleteMem) == .dayComplete,
            "14. non-milestone completed day still celebrates completion"
        )

        let firstReaction = PhilCoach.decision(
            snapshot: firstTaken,
            event: .doseConfirmed(id: "a", wasMissedLike: false),
            memory: emptyMemory
        )
        let replayMemory = PhilCoachMemoryState(
            doneSignature: "a",
            lastMilestone: 0,
            completeDayStamp: "",
            currentDayStamp: "2026-09-21"
        )
        expect(firstReaction != nil, "15. first event produces a reaction")
        expect(
            PhilCoach.decision(snapshot: firstTaken, event: .doseConfirmed(id: "a", wasMissedLike: false), memory: replayMemory) == nil,
            "15. same event twice does not produce a second reaction"
        )

        expect(
            PhilCoach.decision(snapshot: secondTaken, event: .doseConfirmed(id: "b", wasMissedLike: false), memory: replayMemory) != nil,
            "16. a different dose ID is a new event"
        )

        let newTreatment = Gamification.snapshot(
            nodes: [
                DoseNode(id: "new-1", time: "08:00", medicine: "New", status: .done),
                DoseNode(id: "new-2", time: "20:00", medicine: "New", status: .locked),
            ],
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: true,
            todayTaken: 1,
            todayScheduled: 2
        )
        let staleTreatmentMemory = PhilCoachMemoryState(
            doneSignature: "old-a,old-b",
            lastMilestone: 7,
            completeDayStamp: "2026-09-01",
            currentDayStamp: "2026-09-21"
        )
        expect(
            PhilCoach.decision(snapshot: newTreatment, event: .doseConfirmed(id: "new-1", wasMissedLike: false), memory: staleTreatmentMemory) == .firstDay,
            "17. new treatment does not inherit stale dose reaction IDs"
        )

        expect(complete.isComplete && complete.requiredCount == 3, "18. completed day keeps the same challenge size")
        expect(
            PhilCoach.decision(snapshot: complete, event: .dashboardAppeared, memory: alreadyCompleteMemory) == nil,
            "18. completion does not generate another Phil challenge overlay"
        )

        let resolvedMissed = Gamification.snapshot(
            nodes: [
                DoseNode(id: "a", time: "08:00", medicine: "A", status: .done),
                DoseNode(id: "b", time: "20:00", medicine: "B", status: .locked),
            ],
            currentStreak: 0,
            longestStreak: 0,
            hasActiveTreatment: true,
            todayTaken: 1,
            todayScheduled: 2,
            todayMissed: 0
        )
        expect(!resolvedMissed.needsAttention, "19. resolved missed dose is not needsAttention")
        expect(
            PhilCoach.decision(snapshot: resolvedMissed, event: .missedAcknowledged, memory: emptyMemory) == nil,
            "19. resolved missed dose does not produce missed reaction"
        )

        let before = recovered
        _ = PhilCoach.decision(snapshot: recovered, event: .doseConfirmed(id: "a", wasMissedLike: true), memory: emptyMemory)
        expect(before == recovered, "20. Phil decision never writes medication snapshot state")
        expect(recovered.skippedCount == 0 && recovered.takenCount == 1, "20. recovered snapshot remains takenLate/taken presentation only")

        return failures
    }
}
#endif
