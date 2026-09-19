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
        return failures
    }
}
#endif
