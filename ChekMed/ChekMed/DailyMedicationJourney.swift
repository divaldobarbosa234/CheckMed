import Foundation

/// Dashboard-only UX state for the current medication day.
/// Derived from existing Challenge / adherence / path data. Never persisted.
enum DailyMedicationJourneyState: Equatable, Sendable {
    case noTreatment
    case startingDay
    case upcoming
    case inProgress
    case missed
    case almostComplete
    case complete
}

/// Read-only view of today. Counts are copied from `GamificationSnapshot`
/// (`adherence().todayTaken` / `todayTotal` via Challenge). No SwiftData writes.
struct DailyMedicationJourneySnapshot: Equatable, Sendable {
    var state: DailyMedicationJourneyState
    var todayTaken: Int
    var todayTotal: Int
    var remaining: Int
    var missedCount: Int
    var nextDose: ChallengeDoseLine?
}

/// Sits above existing medication data. Does not confirm doses, create logs, or
/// own the Phil take-reaction overlay.
enum DailyMedicationJourney {
    /// - Returns: `nil` while plan restoration is still pending so loading is
    ///   not treated as `.noTreatment`.
    ///
    /// Upcoming vs inProgress (CASE 3): after complete/missed/almostComplete,
    /// **upcoming** when remaining > 1 and the next open path node is `.locked`
    /// (still in the future per existing path status). **inProgress** when
    /// taken ≥ 1, remaining > 1, and the next open node is `.current`.
    /// **almostComplete** only when remaining == 1 and at least one dose is
    /// already taken (0/1 is startingDay, not “just one more”).
    /// **startingDay** when taken == 0, remaining > 0, not missed, and the next
    /// open node is not locked-only.
    static func snapshot(
        from game: GamificationSnapshot,
        nodes: [DoseNode],
        planSurfaceReady: Bool
    ) -> DailyMedicationJourneySnapshot? {
        guard planSurfaceReady else { return nil }

        let taken = game.takenCount
        let total = game.requiredCount
        let remaining = game.remainingCount
        let missed = game.skippedCount
        let nextOpen = nodes.first { $0.status == .current || $0.status == .locked }
        let nextDose = nextOpen.flatMap { node in
            game.lines.first { $0.id == node.id }
        }

        let state: DailyMedicationJourneyState
        if !game.isActive || total == 0 {
            state = .noTreatment
        } else if game.isComplete {
            state = .complete
        } else if game.needsAttention {
            state = .missed
        } else if remaining == 1, taken >= 1 {
            state = .almostComplete
        } else if remaining > 1, nextOpen?.status == .locked {
            state = .upcoming
        } else if taken >= 1, remaining > 1 {
            state = .inProgress
        } else {
            state = .startingDay
        }

        return DailyMedicationJourneySnapshot(
            state: state,
            todayTaken: taken,
            todayTotal: total,
            remaining: remaining,
            missedCount: missed,
            nextDose: nextDose
        )
    }
}

#if DEBUG
enum DailyMedicationJourneyContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        func game(
            nodes: [DoseNode],
            taken: Int,
            scheduled: Int,
            active: Bool = true
        ) -> GamificationSnapshot {
            Gamification.snapshot(
                nodes: nodes,
                currentStreak: 1,
                longestStreak: 1,
                hasActiveTreatment: active,
                todayTaken: taken,
                todayScheduled: scheduled
            )
        }

        func line(_ id: String, time: String, status: PathStatus) -> DoseNode {
            DoseNode(id: id, time: time, medicine: "M\(id)", detail: "1 tab", status: status)
        }

        // CASE 1 — no active treatment
        let none = DailyMedicationJourney.snapshot(
            from: game(nodes: [], taken: 0, scheduled: 0, active: false),
            nodes: [],
            planSurfaceReady: true
        )
        expect(none?.state == .noTreatment, "CASE 1: noTreatment when inactive")

        // Loading is not noTreatment
        let loading = DailyMedicationJourney.snapshot(
            from: game(nodes: [], taken: 0, scheduled: 0, active: false),
            nodes: [],
            planSurfaceReady: false
        )
        expect(loading == nil, "loading/restoration is not noTreatment")

        // CASE 2 — 6 scheduled, 0 taken, 0 missed, first window current
        let sixPending: [DoseNode] = (1...6).map { i in
            line("p\(i)", time: "0\(i):00", status: i == 1 ? .current : .locked)
        }
        let start = DailyMedicationJourney.snapshot(
            from: game(nodes: sixPending, taken: 0, scheduled: 6),
            nodes: sixPending,
            planSurfaceReady: true
        )
        expect(start?.state == .startingDay, "CASE 2: startingDay for 0/6 with current dose")
        expect(start?.todayTaken == 0 && start?.todayTotal == 6, "CASE 2: progress 0/6")

        // CASE 3 — 2/6, next locked in the future → upcoming (not inProgress)
        let twoTaken: [DoseNode] = [
            line("a", time: "08:00", status: .done),
            line("b", time: "10:00", status: .done),
            line("c", time: "16:00", status: .locked),
            line("d", time: "18:00", status: .locked),
            line("e", time: "20:00", status: .locked),
            line("f", time: "22:00", status: .locked),
        ]
        let upcoming = DailyMedicationJourney.snapshot(
            from: game(nodes: twoTaken, taken: 2, scheduled: 6),
            nodes: twoTaken,
            planSurfaceReady: true
        )
        expect(upcoming?.state == .upcoming, "CASE 3: 2/6 with locked next is upcoming")
        expect(upcoming?.nextDose?.id == "c", "CASE 3: next dose is first locked/current")

        // CASE 4 — 3/6, next is current → inProgress
        let threeTaken: [DoseNode] = [
            line("a", time: "08:00", status: .done),
            line("b", time: "10:00", status: .done),
            line("c", time: "12:00", status: .done),
            line("d", time: "18:00", status: .current),
            line("e", time: "20:00", status: .locked),
            line("f", time: "22:00", status: .locked),
        ]
        let inProgress = DailyMedicationJourney.snapshot(
            from: game(nodes: threeTaken, taken: 3, scheduled: 6),
            nodes: threeTaken,
            planSurfaceReady: true
        )
        expect(inProgress?.state == .inProgress, "CASE 4: 3/6 with current next is inProgress")
        expect(inProgress?.todayTaken == 3 && inProgress?.todayTotal == 6, "CASE 4: progress 3/6")

        // CASE 5 — 5/6, 1 remaining, no missed → almostComplete
        let fiveTaken = (1...5).map { line("t\($0)", time: "08:00", status: .done) }
            + [line("r", time: "21:00", status: .locked)]
        let almost = DailyMedicationJourney.snapshot(
            from: game(nodes: fiveTaken, taken: 5, scheduled: 6),
            nodes: fiveTaken,
            planSurfaceReady: true
        )
        expect(almost?.state == .almostComplete, "CASE 5: remaining == 1 is almostComplete")

        // CASE 6 — 5/6 with 1 missed → missed, not almostComplete
        let fivePlusMissed = (1...5).map { line("t\($0)", time: "08:00", status: .done) }
            + [line("m", time: "21:00", status: .skipped)]
        let missedSix = DailyMedicationJourney.snapshot(
            from: game(nodes: fivePlusMissed, taken: 5, scheduled: 6),
            nodes: fivePlusMissed,
            planSurfaceReady: true
        )
        expect(missedSix?.state == .missed, "CASE 6: 5/6 with missed is missed")
        expect(missedSix?.todayTotal == 6, "CASE 6: missed stays in denominator")

        // CASE 7 — 7/8 with 1 missed → missed, not complete
        let sevenTaken = (1...7).map { line("t\($0)", time: "08:00", status: .done) }
        let sevenMissed = DailyMedicationJourney.snapshot(
            from: game(nodes: sevenTaken + [line("m", time: "21:00", status: .skipped)], taken: 7, scheduled: 8),
            nodes: sevenTaken + [line("m", time: "21:00", status: .skipped)],
            planSurfaceReady: true
        )
        expect(sevenMissed?.state == .missed, "CASE 7: 7/8 missed is missed")
        expect(sevenMissed?.todayTaken == 7 && sevenMissed?.todayTotal == 8, "CASE 7: progress 7/8")
        expect(sevenMissed?.state != .complete, "CASE 7: 7/8 is not complete")

        // CASE 8 — 8/8 complete
        let eightTaken = (1...8).map { line("d\($0)", time: "08:00", status: .done) }
        let complete = DailyMedicationJourney.snapshot(
            from: game(nodes: eightTaken, taken: 8, scheduled: 8),
            nodes: eightTaken,
            planSurfaceReady: true
        )
        expect(complete?.state == .complete, "CASE 8: 8/8 is complete")

        // CASE 9 — 0 scheduled is not complete
        let zero = DailyMedicationJourney.snapshot(
            from: game(nodes: [], taken: 0, scheduled: 0),
            nodes: [],
            planSurfaceReady: true
        )
        expect(zero?.state == .noTreatment, "CASE 9: 0/0 is noTreatment, not complete")

        // CASE 10 — future locked remaining is not missed
        let future = DailyMedicationJourney.snapshot(
            from: game(nodes: sevenTaken + [line("f", time: "21:00", status: .locked)], taken: 7, scheduled: 8),
            nodes: sevenTaken + [line("f", time: "21:00", status: .locked)],
            planSurfaceReady: true
        )
        expect(future?.state != .missed, "CASE 10: future remaining is not missed")
        expect(future?.state == .almostComplete, "CASE 10: 7/8 future remaining is almostComplete")

        // CASE 11 — journey never invents historical missed from extra document dates
        expect(future?.missedCount == 0, "CASE 11: skippedCount comes from existing snapshot only")

        // CASE 12 — new treatment line IDs are independent of an old signature
        let oldPlan = DailyMedicationJourney.snapshot(
            from: game(nodes: eightTaken, taken: 8, scheduled: 8),
            nodes: eightTaken,
            planSurfaceReady: true
        )
        let newNodes = [line("new-1", time: "08:00", status: .current)]
        let newPlan = DailyMedicationJourney.snapshot(
            from: game(nodes: newNodes, taken: 0, scheduled: 1),
            nodes: newNodes,
            planSurfaceReady: true
        )
        expect(oldPlan?.state == .complete, "CASE 12: old active plan can be complete")
        expect(
            newPlan?.state == .startingDay,
            "CASE 12: new plan uses new nodes only (got \(String(describing: newPlan?.state)) taken=\(newPlan?.todayTaken ?? -1)/\(newPlan?.todayTotal ?? -1) remaining=\(newPlan?.remaining ?? -1))"
        )
        expect(newPlan?.nextDose?.id == "new-1", "CASE 12: next dose is the new id")

        // CASE 13/14 — derivation is pure; same inputs → same outputs (no confirm/Phil side effects)
        let again = DailyMedicationJourney.snapshot(
            from: game(nodes: threeTaken, taken: 3, scheduled: 6),
            nodes: threeTaken,
            planSurfaceReady: true
        )
        expect(again == inProgress, "CASE 13/14: snapshot is idempotent and does not mutate")

        return failures
    }
}
#endif
