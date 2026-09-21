import Foundation

/// One scheduled dose event. Status lives on `DoseLogRecord` (same id through snooze / dismiss / confirm).
enum DoseLogStatus: String, Codable, Sendable {
    /// Scheduled, not yet confirmed.
    case pending
    case snoozed
    case pendingConfirmation
    case taken
    case takenLate
    /// User confirmed they did not take it, or grace elapsed without confirm.
    case missed
    /// Legacy skip — treated as missed.
    case skipped

    var isConfirmedTaken: Bool {
        self == .taken || self == .takenLate
    }

    var isMissedLike: Bool {
        self == .missed || self == .skipped
    }

    var isOpen: Bool {
        switch self {
        case .pending, .snoozed, .pendingConfirmation:
            return true
        case .taken, .takenLate, .missed, .skipped:
            return false
        }
    }

    var consumesStock: Bool {
        isConfirmedTaken
    }
}

enum DoseLoopAction: Sendable {
    case snooze
    case stop
    case confirmTaken
    case remindLater
    case didNotTake
}

enum DoseLoop {
    /// Stop/dismiss never maps to taken.
    static func apply(
        _ action: DoseLoopAction,
        current: DoseLogStatus,
        scheduledAt: Date,
        now: Date,
        grace: TimeInterval
    ) -> DoseLogStatus {
        if current.isConfirmedTaken { return current }
        switch action {
        case .snooze, .remindLater:
            return .snoozed
        case .stop:
            return .pendingConfirmation
        case .didNotTake:
            return .missed
        case .confirmTaken:
            return confirmedStatus(current: current, scheduledAt: scheduledAt, now: now, grace: grace)
        }
    }

    static func confirmedStatus(
        current: DoseLogStatus,
        scheduledAt: Date,
        now: Date,
        grace: TimeInterval
    ) -> DoseLogStatus {
        if current == .missed
            || current == .skipped
            || current == .pendingConfirmation
            || now > scheduledAt.addingTimeInterval(grace) {
            return .takenLate
        }
        return .taken
    }

    static func shouldConsumeStock(from previous: DoseLogStatus, to next: DoseLogStatus) -> Bool {
        !previous.consumesStock && next.consumesStock
    }

    static func snoozeFireDate(loggedAt: Date, snooze: TimeInterval, now: Date) -> Date {
        let fire = loggedAt.addingTimeInterval(snooze)
        if fire > now.addingTimeInterval(8) { return fire }
        return now.addingTimeInterval(15)
    }

    static func deadline(
        status: DoseLogStatus,
        scheduledAt: Date,
        loggedAt: Date?,
        grace: TimeInterval,
        snooze: TimeInterval
    ) -> Date {
        switch status {
        case .snoozed:
            return (loggedAt ?? scheduledAt).addingTimeInterval(snooze + grace)
        case .pendingConfirmation:
            return (loggedAt ?? scheduledAt).addingTimeInterval(grace)
        case .pending:
            return scheduledAt.addingTimeInterval(grace)
        case .taken, .takenLate, .missed, .skipped:
            return scheduledAt
        }
    }

    static func shouldMarkMissed(
        status: DoseLogStatus,
        scheduledAt: Date,
        loggedAt: Date?,
        now: Date,
        grace: TimeInterval,
        snooze: TimeInterval
    ) -> Bool {
        guard status.isOpen else { return false }
        return now >= deadline(
            status: status,
            scheduledAt: scheduledAt,
            loggedAt: loggedAt,
            grace: grace,
            snooze: snooze
        )
    }

    /// One obligation per medicine + clock minute. Schedule IDs change when
    /// times are rewritten; the canonical slot is the medicine window.
    static func obligationKey(medicineId: UUID, scheduledAt: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
        let minute = calendar.date(from: parts) ?? scheduledAt
        return "\(medicineId.uuidString)|\(minute.timeIntervalSince1970)"
    }

    /// Canonical unresolved states for the missed-dose dialogue. Confirmed
    /// taken / takenLate never qualify, even if the row was missed earlier.
    static func qualifiesForMissedSummary(
        status: DoseLogStatus,
        scheduledAt: Date,
        now: Date
    ) -> Bool {
        if status.isConfirmedTaken { return false }
        switch status {
        case .pendingConfirmation, .missed:
            return true
        case .pending, .snoozed:
            return scheduledAt < now
        case .taken, .takenLate, .skipped:
            return false
        }
    }

    struct DoseSummaryProbe: Equatable, Sendable {
        var id: UUID
        var scheduleId: UUID
        var medicineId: UUID
        var scheduledAt: Date
        var status: DoseLogStatus
    }

    /// IDs that may appear as unresolved missed doses. A slot with any
    /// confirmed-taken log is fully resolved — duplicates are not listed.
    static func unresolvedIdsForMissedSummary(
        logs: [DoseSummaryProbe],
        now: Date,
        calendar: Calendar,
        window: TimeInterval = 36 * 60 * 60
    ) -> Set<UUID> {
        let horizon = now.addingTimeInterval(-window)
        let confirmedSlots = Set(
            logs.compactMap { log -> String? in
                guard log.status.isConfirmedTaken else { return nil }
                return obligationKey(medicineId: log.medicineId, scheduledAt: log.scheduledAt, calendar: calendar)
            }
        )
        var included = Set<UUID>()
        for log in logs {
            let key = obligationKey(medicineId: log.medicineId, scheduledAt: log.scheduledAt, calendar: calendar)
            if log.status.isConfirmedTaken {
                continue
            }
            if confirmedSlots.contains(key) {
                continue
            }
            guard log.scheduledAt >= horizon else { continue }
            guard qualifiesForMissedSummary(status: log.status, scheduledAt: log.scheduledAt, now: now) else {
                continue
            }
            included.insert(log.id)
        }
        return included
    }

    static func duplicateSlotGroups(
        logs: [DoseSummaryProbe],
        calendar: Calendar
    ) -> [[DoseSummaryProbe]] {
        var buckets: [String: [DoseSummaryProbe]] = [:]
        for log in logs {
            let key = obligationKey(medicineId: log.medicineId, scheduledAt: log.scheduledAt, calendar: calendar)
            buckets[key, default: []].append(log)
        }
        return buckets.values.filter { $0.count > 1 }
    }

    struct TodayChallengeCounts: Equatable, Sendable {
        var scheduledCount: Int
        var takenCount: Int
        var takenLateCount: Int
        var completedCount: Int
        var missedCount: Int
        var remainingCount: Int
        var unresolvedCount: Int
        var isComplete: Bool
    }

    /// One obligation per medicine + clock minute. Taken and takenLate both complete the slot.
    static func todayChallengeCounts(
        logs: [DoseSummaryProbe],
        now: Date,
        calendar: Calendar
    ) -> TodayChallengeCounts {
        var groups: [String: [DoseSummaryProbe]] = [:]
        for log in logs {
            let key = obligationKey(medicineId: log.medicineId, scheduledAt: log.scheduledAt, calendar: calendar)
            groups[key, default: []].append(log)
        }
        var taken = 0
        var takenLate = 0
        var missed = 0
        var remaining = 0
        var unresolved = 0
        for group in groups.values {
            if group.contains(where: { $0.status == .takenLate }) {
                takenLate += 1
                continue
            }
            if group.contains(where: { $0.status == .taken }) {
                taken += 1
                continue
            }
            if group.contains(where: { $0.status.isMissedLike }) {
                missed += 1
                unresolved += 1
                continue
            }
            remaining += 1
            if group.contains(where: {
                qualifiesForMissedSummary(status: $0.status, scheduledAt: $0.scheduledAt, now: now)
            }) {
                unresolved += 1
            }
        }
        let scheduled = groups.count
        let completed = taken + takenLate
        return TodayChallengeCounts(
            scheduledCount: scheduled,
            takenCount: taken,
            takenLateCount: takenLate,
            completedCount: completed,
            missedCount: missed,
            remainingCount: remaining,
            unresolvedCount: unresolved,
            isComplete: scheduled > 0 && completed == scheduled && unresolved == 0
        )
    }
    static func shouldPresentIdentitySetup(
        needsIdentityProfile: Bool,
        isReturningConfiguredUser: Bool
    ) -> Bool {
        needsIdentityProfile && !isReturningConfiguredUser
    }

    /// Prescribed duration is independent of confirmed usage. Missed does not change remaining stock.
    static func stockPercentAfterEvent(
        nextStatus: DoseLogStatus,
        previous: DoseLogStatus,
        packageAmount: Double,
        packageUnit: MedicineUnit,
        stockPercent: Double,
        quantityPerDose: Double,
        doseUnit: MedicineUnit
    ) -> Double? {
        guard shouldConsumeStock(from: previous, to: nextStatus) else { return stockPercent }
        return MedicineUnits.stockPercentAfterDose(
            packageAmount: packageAmount,
            packageUnit: packageUnit,
            stockPercent: stockPercent,
            quantityPerDose: quantityPerDose,
            doseUnit: doseUnit
        )
    }
}

#if DEBUG
enum DoseLoopContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let grace: TimeInterval = 45 * 60
        let snooze: TimeInterval = 10 * 60

        expect(
            DoseLoop.apply(.stop, current: .pending, scheduledAt: t0, now: t0, grace: grace) == .pendingConfirmation,
            "Stop must become pending_confirmation, not taken"
        )
        expect(
            DoseLoop.apply(.snooze, current: .pending, scheduledAt: t0, now: t0, grace: grace) == .snoozed,
            "Snooze must stay unconfirmed"
        )
        expect(
            DoseLoop.apply(.confirmTaken, current: .pending, scheduledAt: t0, now: t0, grace: grace) == .taken,
            "Confirm on time is taken"
        )
        expect(
            DoseLoop.apply(.confirmTaken, current: .snoozed, scheduledAt: t0, now: t0.addingTimeInterval(60), grace: grace) == .taken,
            "Snooze then confirm updates the same event to taken"
        )
        expect(
            DoseLoop.apply(.confirmTaken, current: .pendingConfirmation, scheduledAt: t0, now: t0.addingTimeInterval(grace + 60), grace: grace) == .takenLate,
            "Confirm after stop/grace is taken_late"
        )
        expect(
            DoseLoop.apply(.didNotTake, current: .pendingConfirmation, scheduledAt: t0, now: t0, grace: grace) == .missed,
            "Didn't take is missed"
        )
        expect(
            DoseLoop.apply(.confirmTaken, current: .missed, scheduledAt: t0, now: t0.addingTimeInterval(3600), grace: grace) == .takenLate,
            "Took later after miss is taken_late"
        )
        expect(
            DoseLoop.apply(.stop, current: .taken, scheduledAt: t0, now: t0, grace: grace) == .taken,
            "Taken must not revert"
        )
        expect(
            DoseLoop.shouldMarkMissed(
                status: .pendingConfirmation,
                scheduledAt: t0,
                loggedAt: t0,
                now: t0.addingTimeInterval(grace),
                grace: grace,
                snooze: snooze
            ),
            "Grace without confirm marks missed"
        )
        expect(
            !DoseLoop.shouldMarkMissed(
                status: .snoozed,
                scheduledAt: t0,
                loggedAt: t0,
                now: t0.addingTimeInterval(grace / 2),
                grace: grace,
                snooze: snooze
            ),
            "Snooze must not miss before snooze+grace"
        )

        let tabletStock = DoseLoop.stockPercentAfterEvent(
            nextStatus: .taken,
            previous: .pending,
            packageAmount: 20,
            packageUnit: .tablet,
            stockPercent: 100,
            quantityPerDose: 1,
            doseUnit: .tablet
        )
        expect(tabletStock == 95, "Confirmed tablet dose reduces remaining (got \(tabletStock ?? -1))")

        let missedStock = DoseLoop.stockPercentAfterEvent(
            nextStatus: .missed,
            previous: .pendingConfirmation,
            packageAmount: 20,
            packageUnit: .tablet,
            stockPercent: 100,
            quantityPerDose: 1,
            doseUnit: .tablet
        )
        expect(missedStock == 100, "Missed must not reduce stock or extend duration")

        let liquidStock = DoseLoop.stockPercentAfterEvent(
            nextStatus: .takenLate,
            previous: .missed,
            packageAmount: 100,
            packageUnit: .ml,
            stockPercent: 100,
            quantityPerDose: 20,
            doseUnit: .drop
        )
        // 20 drops = 1 mL → 99% of 100 mL
        expect(liquidStock.map { abs($0 - 99) < 0.01 } ?? false, "Liquid taken_late reduces remaining via drop conversion (got \(liquidStock ?? -1))")

        expect(
            MedicineUnits.hasCompleteRefillData(packageAmount: 0, quantityPerDose: 1, packageUnit: .tablet, doseUnit: .tablet) == false,
            "Incomplete refill must not invent numbers"
        )

        expect(
            DoseLoop.apply(.confirmTaken, current: .taken, scheduledAt: t0, now: t0.addingTimeInterval(8 * 3600), grace: grace) == .taken,
            "CASE 9: second confirm on the same log stays taken"
        )
        expect(
            DoseLoop.qualifiesForMissedSummary(status: .taken, scheduledAt: t0, now: t0.addingTimeInterval(8 * 3600)) == false,
            "CASE 4/7: taken is not unresolved missed"
        )
        expect(
            DoseLoop.qualifiesForMissedSummary(status: .takenLate, scheduledAt: t0, now: t0.addingTimeInterval(8 * 3600)) == false,
            "CASE 4/8: takenLate is not unresolved missed"
        )
        expect(
            DoseLoop.qualifiesForMissedSummary(status: .missed, scheduledAt: t0, now: t0.addingTimeInterval(8 * 3600)),
            "CASE 5/6: genuine missed can appear"
        )
        expect(
            DoseLoop.qualifiesForMissedSummary(status: .pending, scheduledAt: t0.addingTimeInterval(3600), now: t0) == false,
            "future pending is not unresolved missed"
        )

        let schedule = UUID()
        let medicine = UUID()
        let otherMedicine = UUID()
        let takenId = UUID()
        let staleMissedId = UUID()
        let genuineMissedId = UUID()
        let calendar = Calendar(identifier: .gregorian)
        let later = t0.addingTimeInterval(8 * 3600)
        func probe(_ id: UUID, scheduleId: UUID, medicineId: UUID, status: DoseLogStatus) -> DoseLoop.DoseSummaryProbe {
            DoseLoop.DoseSummaryProbe(
                id: id,
                scheduleId: scheduleId,
                medicineId: medicineId,
                scheduledAt: t0,
                status: status
            )
        }
        let unresolved = DoseLoop.unresolvedIdsForMissedSummary(
            logs: [
                probe(takenId, scheduleId: schedule, medicineId: medicine, status: .taken),
                probe(staleMissedId, scheduleId: schedule, medicineId: medicine, status: .missed),
                probe(genuineMissedId, scheduleId: UUID(), medicineId: otherMedicine, status: .missed),
            ],
            now: later,
            calendar: calendar
        )
        expect(!unresolved.contains(takenId), "CASE 4: confirmed log is excluded")
        expect(!unresolved.contains(staleMissedId), "CASE 3: duplicate missed sibling of a taken slot is excluded")
        expect(unresolved.contains(genuineMissedId), "CASE 5/6: a different unresolved missed log remains")

        let replacedScheduleMissed = UUID()
        let replaced = DoseLoop.unresolvedIdsForMissedSummary(
            logs: [
                probe(takenId, scheduleId: schedule, medicineId: medicine, status: .takenLate),
                probe(replacedScheduleMissed, scheduleId: UUID(), medicineId: medicine, status: .missed),
            ],
            now: later,
            calendar: calendar
        )
        expect(
            !replaced.contains(replacedScheduleMissed),
            "CASE 8: missed sibling of takenLate on a replaced schedule ID is excluded"
        )
        let dupes = DoseLoop.duplicateSlotGroups(
            logs: [
                probe(takenId, scheduleId: schedule, medicineId: medicine, status: .taken),
                probe(replacedScheduleMissed, scheduleId: UUID(), medicineId: medicine, status: .pending),
            ],
            calendar: calendar
        )
        expect(dupes.count == 1 && dupes[0].count == 2, "CASE 8: duplicate slot is detected, not deleted")
        expect(
            DoseLoop.apply(.confirmTaken, current: .missed, scheduledAt: t0, now: later, grace: grace) == .takenLate,
            "CASE 2/3: explicit late confirm is takenLate on the same event"
        )
        expect(
            DoseLoop.shouldPresentIdentitySetup(needsIdentityProfile: true, isReturningConfiguredUser: true) == false,
            "CASE 9/12: returning configured user never opens name/birth"
        )
        expect(
            DoseLoop.shouldPresentIdentitySetup(needsIdentityProfile: true, isReturningConfiguredUser: false),
            "CASE 10: new user can still open identity setup"
        )
        expect(
            DoseLoop.shouldPresentIdentitySetup(needsIdentityProfile: false, isReturningConfiguredUser: false) == false,
            "CASE 11: loading/empty identity is not first-time when profile already complete"
        )

        let challengeCal = Calendar(identifier: .gregorian)
        func slot(_ id: UUID, medicine: UUID, status: DoseLogStatus, at: Date = t0) -> DoseLoop.DoseSummaryProbe {
            DoseLoop.DoseSummaryProbe(id: id, scheduleId: UUID(), medicineId: medicine, scheduledAt: at, status: status)
        }
        let meds = (0..<8).map { _ in UUID() }
        let sevenPlusRemaining = DoseLoop.todayChallengeCounts(
            logs: (0..<7).map { slot(UUID(), medicine: meds[$0], status: .taken) }
                + [slot(UUID(), medicine: meds[7], status: .pending, at: t0.addingTimeInterval(3600))],
            now: t0,
            calendar: challengeCal
        )
        expect(
            sevenPlusRemaining.completedCount == 7 && sevenPlusRemaining.remainingCount == 1 && !sevenPlusRemaining.isComplete,
            "CHALLENGE CASE 1: 7/8 with remaining is not complete"
        )
        let sevenPlusMissed = DoseLoop.todayChallengeCounts(
            logs: (0..<7).map { slot(UUID(), medicine: meds[$0], status: .taken) }
                + [slot(UUID(), medicine: meds[7], status: .missed)],
            now: later,
            calendar: challengeCal
        )
        expect(
            sevenPlusMissed.completedCount == 7 && sevenPlusMissed.missedCount == 1 && !sevenPlusMissed.isComplete,
            "CHALLENGE CASE 2/7: 7/8 + missed is not complete"
        )
        let recovered = DoseLoop.todayChallengeCounts(
            logs: (0..<7).map { slot(UUID(), medicine: meds[$0], status: .taken) }
                + [slot(takenId, medicine: meds[7], status: .takenLate)],
            now: later,
            calendar: challengeCal
        )
        expect(
            recovered.takenCount == 7 && recovered.takenLateCount == 1 && recovered.completedCount == 8
                && recovered.missedCount == 0 && recovered.isComplete,
            "CHALLENGE CASE 3/6: 7 taken + 1 takenLate is 8/8 complete"
        )
        let eightTaken = DoseLoop.todayChallengeCounts(
            logs: meds.map { slot(UUID(), medicine: $0, status: .taken) },
            now: later,
            calendar: challengeCal
        )
        expect(eightTaken.isComplete && eightTaken.scheduledCount == 8, "CHALLENGE CASE 5: 8/8 is complete")
        let duplicatePending = DoseLoop.todayChallengeCounts(
            logs: meds.map { slot(UUID(), medicine: $0, status: .taken) }
                + [slot(UUID(), medicine: meds[0], status: .pending)],
            now: later,
            calendar: challengeCal
        )
        expect(
            duplicatePending.scheduledCount == 8 && duplicatePending.isComplete,
            "CHALLENGE CASE 8: duplicate pending sibling does not start a new same-day challenge"
        )
        return failures
    }
}
#endif
