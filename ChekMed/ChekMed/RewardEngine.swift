import Foundation
import SwiftData

/// Persistence-only rewards. Does not write DoseLogs or decide medical validity.
enum RewardEngine {
    struct DoseFacts: Equatable, Sendable {
        var logId: UUID
        var ownerId: UUID
        var profileId: UUID
        var previous: DoseLogStatus
        var next: DoseLogStatus
        var dayIsComplete: Bool
        var currentStreak: Int
        var now: Date
    }

    /// Inserts one `RewardGrant` when `eventKey` is absent. Saves on insert.
    @discardableResult
    static func grantIfNeeded(
        context: ModelContext,
        ownerId: UUID?,
        profileId: UUID?,
        eventKey: String,
        kind: String,
        xp: Int,
        achievementId: String?,
        now: Date = Date()
    ) -> Bool {
        let key = eventKey
        let descriptor = FetchDescriptor<RewardGrant>(
            predicate: #Predicate { row in row.eventKey == key }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return false
        }
        let row = RewardGrant(
            ownerId: ownerId,
            profileId: profileId,
            eventKey: eventKey,
            kind: kind,
            xp: xp,
            achievementId: achievementId,
            createdAt: now
        )
        context.insert(row)
        try? context.save()
        #if DEBUG
        print("[REWARD] grant eventKey=\(eventKey) kind=\(kind) xp=\(xp)")
        #endif
        return true
    }

    static func applyDoseRewards(context: ModelContext, facts: DoseFacts, calendar: Calendar) {
        guard facts.next.isConfirmedTaken, !facts.previous.isConfirmedTaken else { return }
        let lateOrRecovery = facts.next == .takenLate || facts.previous.isMissedLike
        let event: RewardCatalog.XPEvent = lateOrRecovery ? .doseTakenLate : .doseTaken
        _ = grantIfNeeded(
            context: context,
            ownerId: facts.ownerId,
            profileId: facts.profileId,
            eventKey: RewardCatalog.doseEventKey(logId: facts.logId),
            kind: event.rawValue,
            xp: RewardCatalog.xp(for: event),
            achievementId: nil,
            now: facts.now
        )
        _ = grantIfNeeded(
            context: context,
            ownerId: facts.ownerId,
            profileId: facts.profileId,
            eventKey: RewardCatalog.achievementEventKey(
                ownerId: facts.ownerId,
                profileId: facts.profileId,
                achievement: .firstDose
            ),
            kind: RewardCatalog.Achievement.firstDose.rawValue,
            xp: 0,
            achievementId: RewardCatalog.Achievement.firstDose.rawValue,
            now: facts.now
        )
        if facts.previous.isMissedLike {
            _ = grantIfNeeded(
                context: context,
                ownerId: facts.ownerId,
                profileId: facts.profileId,
                eventKey: RewardCatalog.achievementEventKey(
                    ownerId: facts.ownerId,
                    profileId: facts.profileId,
                    achievement: .firstRecovery
                ),
                kind: RewardCatalog.Achievement.firstRecovery.rawValue,
                xp: 0,
                achievementId: RewardCatalog.Achievement.firstRecovery.rawValue,
                now: facts.now
            )
        }
        if facts.dayIsComplete {
            let stamp = RewardCatalog.dayStamp(now: facts.now, calendar: calendar)
            _ = grantIfNeeded(
                context: context,
                ownerId: facts.ownerId,
                profileId: facts.profileId,
                eventKey: RewardCatalog.dayEventKey(
                    ownerId: facts.ownerId,
                    profileId: facts.profileId,
                    dayStamp: stamp
                ),
                kind: RewardCatalog.XPEvent.dayComplete.rawValue,
                xp: RewardCatalog.xp(for: .dayComplete),
                achievementId: nil,
                now: facts.now
            )
            _ = grantIfNeeded(
                context: context,
                ownerId: facts.ownerId,
                profileId: facts.profileId,
                eventKey: RewardCatalog.achievementEventKey(
                    ownerId: facts.ownerId,
                    profileId: facts.profileId,
                    achievement: .firstDay
                ),
                kind: RewardCatalog.Achievement.firstDay.rawValue,
                xp: 0,
                achievementId: RewardCatalog.Achievement.firstDay.rawValue,
                now: facts.now
            )
        }
        for n in RewardCatalog.streakThresholds where facts.currentStreak >= n {
            guard let streakEvent = RewardCatalog.streakEvent(n),
                  let streakAchievement = RewardCatalog.streakAchievement(n) else { continue }
            _ = grantIfNeeded(
                context: context,
                ownerId: facts.ownerId,
                profileId: facts.profileId,
                eventKey: RewardCatalog.streakEventKey(
                    ownerId: facts.ownerId,
                    profileId: facts.profileId,
                    n: n
                ),
                kind: streakEvent.rawValue,
                xp: RewardCatalog.xp(for: streakEvent),
                achievementId: streakAchievement.rawValue,
                now: facts.now
            )
        }
    }

    static func applyTreatmentComplete(
        context: ModelContext,
        ownerId: UUID?,
        profileId: UUID?,
        treatmentId: UUID,
        now: Date = Date()
    ) {
        guard let ownerId, let profileId else { return }
        _ = grantIfNeeded(
            context: context,
            ownerId: ownerId,
            profileId: profileId,
            eventKey: RewardCatalog.treatmentEventKey(treatmentId: treatmentId),
            kind: RewardCatalog.XPEvent.treatmentComplete.rawValue,
            xp: RewardCatalog.xp(for: .treatmentComplete),
            achievementId: nil,
            now: now
        )
        _ = grantIfNeeded(
            context: context,
            ownerId: ownerId,
            profileId: profileId,
            eventKey: RewardCatalog.achievementEventKey(
                ownerId: ownerId,
                profileId: profileId,
                achievement: .firstTreatmentComplete
            ),
            kind: RewardCatalog.Achievement.firstTreatmentComplete.rawValue,
            xp: 0,
            achievementId: RewardCatalog.Achievement.firstTreatmentComplete.rawValue,
            now: now
        )
    }
}

#if DEBUG
enum RewardEngineContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let schema = Schema([RewardGrant.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            return [
                "A: RewardEngine in-memory container failed",
                "B: RewardEngine in-memory container failed",
                "C: RewardEngine in-memory container failed",
                "D: RewardEngine in-memory container failed",
                "E: RewardEngine in-memory container failed",
                "F: RewardEngine in-memory container failed",
                "G: RewardEngine in-memory container failed",
            ]
        }
        let context = ModelContext(container)
        let owner = UUID()
        let profile = UUID()
        let logId = UUID()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!

        func count(prefix: String? = nil) -> Int {
            let rows = (try? context.fetch(FetchDescriptor<RewardGrant>())) ?? []
            if let prefix {
                return rows.filter { $0.eventKey.hasPrefix(prefix) }.count
            }
            return rows.count
        }

        func xpTotal() -> Int {
            ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? []).reduce(0) { $0 + $1.xp }
        }

        let takenFacts = RewardEngine.DoseFacts(
            logId: logId,
            ownerId: owner,
            profileId: profile,
            previous: .pending,
            next: .taken,
            dayIsComplete: false,
            currentStreak: 0,
            now: now
        )
        RewardEngine.applyDoseRewards(context: context, facts: takenFacts, calendar: calendar)
        RewardEngine.applyDoseRewards(context: context, facts: takenFacts, calendar: calendar)
        let doseKey = RewardCatalog.doseEventKey(logId: logId)
        let doseRows = ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == doseKey }
        expect(doseRows.count == 1, "A: one DoseLog confirmed twice → one dose grant")
        expect(doseRows.first?.xp == 10, "A: on-time dose is 10 XP")

        let lateLog = UUID()
        let lateFacts = RewardEngine.DoseFacts(
            logId: lateLog,
            ownerId: owner,
            profileId: profile,
            previous: .pending,
            next: .takenLate,
            dayIsComplete: false,
            currentStreak: 0,
            now: now
        )
        RewardEngine.applyDoseRewards(context: context, facts: lateFacts, calendar: calendar)
        let lateKey = RewardCatalog.doseEventKey(logId: lateLog)
        let lateRows = ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == lateKey }
        expect(lateRows.count == 1 && lateRows.first?.xp == 5, "B: late dose is 5 XP, not 10+5")

        let recoveryLog = UUID()
        let recoveryFacts = RewardEngine.DoseFacts(
            logId: recoveryLog,
            ownerId: owner,
            profileId: profile,
            previous: .missed,
            next: .takenLate,
            dayIsComplete: false,
            currentStreak: 0,
            now: now
        )
        RewardEngine.applyDoseRewards(context: context, facts: recoveryFacts, calendar: calendar)
        let recoveryKey = RewardCatalog.doseEventKey(logId: recoveryLog)
        let recoveryRows = ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == recoveryKey }
        expect(recoveryRows.count == 1 && recoveryRows.first?.xp == 5, "B/recovery: missed→takenLate is one 5 XP dose grant")

        let notifyLog = UUID()
        let notifyFacts = RewardEngine.DoseFacts(
            logId: notifyLog,
            ownerId: owner,
            profileId: profile,
            previous: .pending,
            next: .taken,
            dayIsComplete: false,
            currentStreak: 0,
            now: now
        )
        RewardEngine.applyDoseRewards(context: context, facts: notifyFacts, calendar: calendar)
        RewardEngine.applyDoseRewards(context: context, facts: notifyFacts, calendar: calendar)
        let notifyKey = RewardCatalog.doseEventKey(logId: notifyLog)
        let notifyRows = ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == notifyKey }
        expect(notifyRows.count == 1, "C: Home + notification same DoseLog → one dose grant")

        let dayLog = UUID()
        let dayFacts = RewardEngine.DoseFacts(
            logId: dayLog,
            ownerId: owner,
            profileId: profile,
            previous: .pending,
            next: .taken,
            dayIsComplete: true,
            currentStreak: 0,
            now: now
        )
        RewardEngine.applyDoseRewards(context: context, facts: dayFacts, calendar: calendar)
        RewardEngine.applyDoseRewards(context: context, facts: dayFacts, calendar: calendar)
        let dayKey = RewardCatalog.dayEventKey(
            ownerId: owner,
            profileId: profile,
            dayStamp: RewardCatalog.dayStamp(now: now, calendar: calendar)
        )
        let dayRows = ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == dayKey }
        expect(dayRows.count == 1 && dayRows.first?.xp == 20, "D: day complete once; recalculation stays one")

        let streakLog = UUID()
        let streakFacts = RewardEngine.DoseFacts(
            logId: streakLog,
            ownerId: owner,
            profileId: profile,
            previous: .pending,
            next: .taken,
            dayIsComplete: true,
            currentStreak: 3,
            now: now
        )
        RewardEngine.applyDoseRewards(context: context, facts: streakFacts, calendar: calendar)
        RewardEngine.applyDoseRewards(context: context, facts: streakFacts, calendar: calendar)
        let streak3Key = RewardCatalog.streakEventKey(ownerId: owner, profileId: profile, n: 3)
        let streak1Key = RewardCatalog.streakEventKey(ownerId: owner, profileId: profile, n: 1)
        let streakRows3 = ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == streak3Key }
        let streakRows1 = ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == streak1Key }
        expect(streakRows3.count == 1 && streakRows3.first?.xp == 25, "E: streak 3 once")
        expect(streakRows1.count == 1, "E: crossing 3 also grants missing streak 1 once")

        let treatmentId = UUID()
        RewardEngine.applyTreatmentComplete(
            context: context,
            ownerId: owner,
            profileId: profile,
            treatmentId: treatmentId,
            now: now
        )
        RewardEngine.applyTreatmentComplete(
            context: context,
            ownerId: owner,
            profileId: profile,
            treatmentId: treatmentId,
            now: now
        )
        let treatmentKey = RewardCatalog.treatmentEventKey(treatmentId: treatmentId)
        let treatmentRows = ((try? context.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == treatmentKey }
        expect(treatmentRows.count == 1 && treatmentRows.first?.xp == 50, "F: complete same treatment twice → one grant")

        let relaunchContext = ModelContext(container)
        let relaunchRows = ((try? relaunchContext.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey == doseKey }
        expect(relaunchRows.count == 1, "G: grant still visible on a new ModelContext (same container)")

        let progressSchema = Schema([RewardGrant.self])
        let progressConfig = ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true)
        guard let progressContainer = try? ModelContainer(for: progressSchema, configurations: [progressConfig]) else {
            expect(false, "H: RewardProgress in-memory container failed")
            expect(false, "I: RewardProgress in-memory container failed")
            return failures
        }
        let progressContext = ModelContext(progressContainer)
        let hOwner = UUID()
        let hProfile = UUID()
        for amount in [10, 20, 15] {
            progressContext.insert(
                RewardGrant(
                    ownerId: hOwner,
                    profileId: hProfile,
                    eventKey: "test.h.\(amount).\(UUID().uuidString)",
                    kind: "test",
                    xp: amount,
                    achievementId: nil,
                    createdAt: now
                )
            )
        }
        try? progressContext.save()
        let hRows = (try? progressContext.fetch(FetchDescriptor<RewardGrant>())) ?? []
        let hSum = RewardCatalog.totalXP(fromGrantAmounts: hRows.map(\.xp))
        expect(hSum == 45, "H: 10+20+15 → 45 XP")

        let iContext = ModelContext(progressContainer)
        iContext.insert(
            RewardGrant(
                ownerId: hOwner,
                profileId: hProfile,
                eventKey: "test.i.xp.\(UUID().uuidString)",
                kind: "dose_taken",
                xp: 10,
                achievementId: nil,
                createdAt: now
            )
        )
        iContext.insert(
            RewardGrant(
                ownerId: hOwner,
                profileId: hProfile,
                eventKey: "test.i.ach.\(UUID().uuidString)",
                kind: "first_dose",
                xp: 0,
                achievementId: "first_dose",
                createdAt: now
            )
        )
        try? iContext.save()
        let iRows = ((try? iContext.fetch(FetchDescriptor<RewardGrant>())) ?? [])
            .filter { $0.eventKey.hasPrefix("test.i.") }
        expect(RewardCatalog.totalXP(fromGrantAmounts: iRows.map(\.xp)) == 10, "I: 10 XP + 0 XP achievement → 10 XP")

        let zero = RewardCatalog.progress(totalXP: 0)
        expect(zero.currentLevel == 1 && zero.progressFraction == 0, "J: 0 XP → Level 1, progress 0")
        let fortyNine = RewardCatalog.progress(totalXP: 49)
        expect(fortyNine.currentLevel == 1 && fortyNine.xpAtNextLevel == 50, "J: 49 XP → Level 1")
        let fifty = RewardCatalog.progress(totalXP: 50)
        expect(fifty.currentLevel == 2 && fifty.xpIntoLevel == 0 && fifty.xpAtCurrentLevelStart == 50, "J: 50 XP → Level 2")
        let oneFortyNine = RewardCatalog.progress(totalXP: 149)
        expect(oneFortyNine.currentLevel == 2, "J: 149 XP → Level 2")
        let oneFifty = RewardCatalog.progress(totalXP: 150)
        expect(oneFifty.currentLevel == 3 && oneFifty.xpIntoLevel == 0, "J: 150 XP → Level 3")

        let mid = RewardCatalog.progress(totalXP: 100)
        expect(mid.currentLevel == 2, "K: 100 XP → Level 2")
        expect(mid.xpIntoLevel == 50, "K: 100 XP is 50 into Level 2")
        expect(mid.xpNeededForNext == 50 && mid.xpAtNextLevel == 150, "K: 50 XP needed for Level 3 threshold")
        expect(mid.progressFraction > 0 && mid.progressFraction < 1, "K: progress fraction between 0 and 1")
        expect(!mid.isMaxDefinedLevel, "K: 100 XP is not max level")

        let maxed = RewardCatalog.progress(totalXP: 3500)
        expect(maxed.currentLevel == RewardCatalog.levelThresholds.count, "L: 3500 XP is the highest defined level")
        expect(maxed.isMaxDefinedLevel && maxed.progressFraction == 1.0, "L: max level progressFraction is 1.0")
        expect(maxed.xpNeededForNext == 0 && maxed.xpAtNextLevel == nil, "L: no next-level XP at max")
        let over = RewardCatalog.progress(totalXP: 9_999)
        expect(over.currentLevel == maxed.currentLevel && over.progressFraction == 1.0 && over.xpNeededForNext >= 0, "L: overshoot stays at max without negative next XP")

        _ = count()
        _ = xpTotal()
        return failures
    }

    static func runtimeReport() -> String {
        let failures = failures()
        func line(_ code: String) -> String {
            let related = failures.filter { $0.hasPrefix("\(code):") || $0.hasPrefix("\(code)/") }
            if related.isEmpty { return "\(code): PASS" }
            return "\(code): FAIL — \(related.joined(separator: "; "))"
        }
        return [
            line("A"),
            line("B"),
            line("C"),
            line("D"),
            line("E"),
            line("F"),
            line("G"),
            line("H"),
            line("I"),
            line("J"),
            line("K"),
            line("L"),
            "allPass: \(failures.isEmpty)",
        ].joined(separator: "\n")
    }
}
#endif
