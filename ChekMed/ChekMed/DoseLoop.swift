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

    /// First calendar day CheckMed is tracking this medicine: do not insert
    /// already-passed clocks. Logs from a previous day mean the treatment was
    /// already active — today's overdue slots must still be created (real misses).
    static func shouldSkipAlreadyPassedClockOnFirstTrackingDay(
        scheduledAt: Date,
        now: Date,
        dayStart: Date,
        hasLogsBeforeDay: Bool,
        calendar: Calendar
    ) -> Bool {
        guard calendar.isDate(scheduledAt, inSameDayAs: dayStart) else { return false }
        guard scheduledAt < now else { return false }
        return !hasLogsBeforeDay
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

    enum WeeklyDayStatus: Equatable, Sendable {
        case notApplicable
        case future
        case noScheduledDoses
        case incomplete
        case complete
    }

    struct TreatmentWindow: Equatable, Sendable {
        var start: Date
        var end: Date?
    }

    struct WeeklyDaySnapshot: Equatable, Sendable {
        var date: Date
        var weekdayIndex: Int
        var status: WeeklyDayStatus
        var scheduledCount: Int
        var takenCount: Int
        var takenLateCount: Int
        var missedCount: Int
        var completedCount: Int
        var isToday: Bool
    }

    struct WeeklyMedicationProgressSnapshot: Equatable, Sendable {
        var weekStart: Date
        var weekEnd: Date
        var days: [WeeklyDaySnapshot]
        var completedDays: Int
        var applicableDays: Int
        var adherencePercentage: Int?

        static let empty = WeeklyMedicationProgressSnapshot(
            weekStart: .distantPast,
            weekEnd: .distantPast,
            days: [],
            completedDays: 0,
            applicableDays: 0,
            adherencePercentage: nil
        )
    }

    /// Monday 00:00 → next Monday 00:00 using Calendar week-of-year, not hardcoded offsets.
    static func mondayWeekInterval(containing date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        var cal = calendar
        cal.firstWeekday = 2
        let day = cal.startOfDay(for: date)
        let start = cal.dateInterval(of: .weekOfYear, for: day).map { cal.startOfDay(for: $0.start) } ?? day
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    static func treatmentCovers(day: Date, windows: [TreatmentWindow], calendar: Calendar) -> Bool {
        let d = calendar.startOfDay(for: day)
        return windows.contains { window in
            let start = calendar.startOfDay(for: window.start)
            guard d >= start else { return false }
            if let end = window.end {
                return d <= calendar.startOfDay(for: end)
            }
            return true
        }
    }

    /// Read-only Mon–Sun day statuses. Today uses the same `TodayChallengeCounts` as Today's Challenge.
    static func weeklyMedicationProgress(
        logs: [DoseSummaryProbe],
        treatmentWindows: [TreatmentWindow],
        now: Date,
        calendar: Calendar,
        todayCounts: TodayChallengeCounts
    ) -> WeeklyMedicationProgressSnapshot {
        let interval = mondayWeekInterval(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var byDay: [TimeInterval: [DoseSummaryProbe]] = [:]
        for log in logs {
            let day = calendar.startOfDay(for: log.scheduledAt)
            byDay[day.timeIntervalSince1970, default: []].append(log)
        }
        var days: [WeeklyDaySnapshot] = []
        days.reserveCapacity(7)
        for index in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: index, to: interval.start) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let isToday = calendar.isDate(dayStart, inSameDayAs: today)
            let isFuture = dayStart > today
            let inTreatment = treatmentCovers(day: dayStart, windows: treatmentWindows, calendar: calendar)
            let counts: TodayChallengeCounts
            if isToday {
                counts = todayCounts
            } else {
                counts = todayChallengeCounts(
                    logs: byDay[dayStart.timeIntervalSince1970] ?? [],
                    now: now,
                    calendar: calendar
                )
            }
            days.append(
                WeeklyDaySnapshot(
                    date: dayStart,
                    weekdayIndex: index,
                    status: dayMedicationStatus(
                        inTreatment: inTreatment,
                        isFuture: isFuture,
                        counts: counts
                    ),
                    scheduledCount: counts.scheduledCount,
                    takenCount: counts.takenCount,
                    takenLateCount: counts.takenLateCount,
                    missedCount: counts.missedCount,
                    completedCount: counts.completedCount,
                    isToday: isToday
                )
            )
        }
        let completedDays = days.filter { $0.status == .complete }.count
        let applicableDays = days.filter { $0.status == .complete || $0.status == .incomplete }.count
        let percent: Int? = applicableDays == 0
            ? nil
            : Int((Double(completedDays) / Double(applicableDays) * 100).rounded())
        return WeeklyMedicationProgressSnapshot(
            weekStart: interval.start,
            weekEnd: interval.end,
            days: days,
            completedDays: completedDays,
            applicableDays: applicableDays,
            adherencePercentage: percent
        )
    }

    /// Same completion rule as weekly progress and Today's Challenge.
    static func dayMedicationStatus(
        inTreatment: Bool,
        isFuture: Bool,
        counts: TodayChallengeCounts
    ) -> WeeklyDayStatus {
        if !inTreatment { return .notApplicable }
        if isFuture { return .future }
        if counts.scheduledCount == 0 { return .noScheduledDoses }
        if counts.isComplete { return .complete }
        return .incomplete
    }

    struct AdherenceStreakSnapshot: Equatable, Sendable {
        var currentDays: Int
        var longestDays: Int

        static let zero = AdherenceStreakSnapshot(currentDays: 0, longestDays: 0)
    }

    /// Consecutive complete treatment days. Read-only. Today counts only when `todayCounts.isComplete`.
    static func adherenceStreak(
        logs: [DoseSummaryProbe],
        treatmentWindows: [TreatmentWindow],
        now: Date,
        calendar: Calendar,
        todayCounts: TodayChallengeCounts,
        lookbackDays: Int = 400
    ) -> AdherenceStreakSnapshot {
        guard lookbackDays > 0, !treatmentWindows.isEmpty else { return .zero }
        let today = calendar.startOfDay(for: now)
        let floor = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today) ?? today
        var byDay: [TimeInterval: [DoseSummaryProbe]] = [:]
        for log in logs {
            let day = calendar.startOfDay(for: log.scheduledAt)
            guard day >= floor, day <= today else { continue }
            byDay[day.timeIntervalSince1970, default: []].append(log)
        }

        func status(on dayStart: Date) -> WeeklyDayStatus {
            let isToday = calendar.isDate(dayStart, inSameDayAs: today)
            let counts = isToday
                ? todayCounts
                : todayChallengeCounts(
                    logs: byDay[dayStart.timeIntervalSince1970] ?? [],
                    now: now,
                    calendar: calendar
                )
            return dayMedicationStatus(
                inTreatment: treatmentCovers(day: dayStart, windows: treatmentWindows, calendar: calendar),
                isFuture: dayStart > today,
                counts: counts
            )
        }

        var current = 0
        var cursor = today
        for _ in 0..<lookbackDays {
            let kind = status(on: cursor)
            let isToday = calendar.isDate(cursor, inSameDayAs: today)
            switch kind {
            case .complete:
                current += 1
            case .incomplete:
                if !isToday { break }
            case .notApplicable, .noScheduledDoses, .future:
                break
            }
            if kind == .incomplete, !isToday { break }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var run = 0
        var best = 0
        var day = floor
        while day <= today {
            let kind = status(on: day)
            switch kind {
            case .complete:
                run += 1
                if run > best { best = run }
            case .incomplete:
                run = 0
            case .notApplicable, .noScheduledDoses, .future:
                break
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return AdherenceStreakSnapshot(currentDays: current, longestDays: max(current, best))
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

        var gmtCalendar = Calendar(identifier: .gregorian)
        gmtCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day = gmtCalendar.date(from: DateComponents(year: 2026, month: 9, day: 26))!
        let now1630 = gmtCalendar.date(byAdding: .minute, value: 16 * 60 + 30, to: day)!
        let clock0800 = gmtCalendar.date(byAdding: .hour, value: 8, to: day)!
        let clock1400 = gmtCalendar.date(byAdding: .hour, value: 14, to: day)!
        let clock2000 = gmtCalendar.date(byAdding: .hour, value: 20, to: day)!
        expect(
            DoseLoop.shouldSkipAlreadyPassedClockOnFirstTrackingDay(
                scheduledAt: clock0800, now: now1630, dayStart: day, hasLogsBeforeDay: false, calendar: gmtCalendar
            ),
            "new medicine at 16:30 must not create 08:00"
        )
        expect(
            DoseLoop.shouldSkipAlreadyPassedClockOnFirstTrackingDay(
                scheduledAt: clock1400, now: now1630, dayStart: day, hasLogsBeforeDay: false, calendar: gmtCalendar
            ),
            "new medicine at 16:30 must not create 14:00"
        )
        expect(
            !DoseLoop.shouldSkipAlreadyPassedClockOnFirstTrackingDay(
                scheduledAt: clock2000, now: now1630, dayStart: day, hasLogsBeforeDay: false, calendar: gmtCalendar
            ),
            "new medicine at 16:30 must still create 20:00"
        )
        expect(
            !DoseLoop.shouldSkipAlreadyPassedClockOnFirstTrackingDay(
                scheduledAt: clock0800, now: now1630, dayStart: day, hasLogsBeforeDay: true, calendar: gmtCalendar
            ),
            "existing medicine must still seed today's overdue 08:00"
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

enum WeeklyMedicationProgressContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ ok: Bool, _ name: String) {
            if !ok { failures.append(name) }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        func day(_ offset: Int, hour: Int = 8) -> Date {
            var comps = DateComponents()
            comps.year = 2026
            comps.month = 9
            comps.day = 14 + offset
            comps.hour = hour
            return cal.date(from: comps) ?? Date()
        }
        let monday = day(0)
        let wednesday = day(2)
        let friday = day(4)
        let sunday = day(6)
        let interval = DoseLoop.mondayWeekInterval(containing: wednesday, calendar: cal)
        expect(cal.isDate(interval.start, inSameDayAs: monday), "week starts Monday")
        expect(cal.isDate(interval.end, inSameDayAs: day(7)), "week ends next Monday")

        func probe(_ date: Date, medicine: UUID, status: DoseLogStatus, minuteOffset: Int = 0) -> DoseLoop.DoseSummaryProbe {
            DoseLoop.DoseSummaryProbe(
                id: UUID(),
                scheduleId: UUID(),
                medicineId: medicine,
                scheduledAt: date.addingTimeInterval(TimeInterval(minuteOffset * 60)),
                status: status
            )
        }
        func counts(_ logs: [DoseLoop.DoseSummaryProbe], now: Date) -> DoseLoop.TodayChallengeCounts {
            DoseLoop.todayChallengeCounts(logs: logs, now: now, calendar: cal)
        }
        let med = UUID()
        let fullWindow = [DoseLoop.TreatmentWindow(start: monday, end: sunday)]
        let nowSunday = day(6, hour: 20)

        var fullLogs: [DoseLoop.DoseSummaryProbe] = []
        for offset in 0..<7 {
            fullLogs.append(probe(day(offset), medicine: med, status: .taken))
        }
        let case1 = DoseLoop.weeklyMedicationProgress(
            logs: fullLogs,
            treatmentWindows: fullWindow,
            now: nowSunday,
            calendar: cal,
            todayCounts: counts(fullLogs.filter { cal.isDate($0.scheduledAt, inSameDayAs: sunday) }, now: nowSunday)
        )
        expect(case1.days.count == 7, "CASE 1: seven day cells")
        expect(case1.days.allSatisfy { $0.status == .complete }, "CASE 1: all complete")
        expect(case1.completedDays == 7 && case1.applicableDays == 7 && case1.adherencePercentage == 100, "CASE 1: 7/7 100%")

        var missedLogs = fullLogs
        missedLogs[3] = probe(day(3), medicine: med, status: .missed)
        let case2 = DoseLoop.weeklyMedicationProgress(
            logs: missedLogs,
            treatmentWindows: fullWindow,
            now: nowSunday,
            calendar: cal,
            todayCounts: counts(missedLogs.filter { cal.isDate($0.scheduledAt, inSameDayAs: sunday) }, now: nowSunday)
        )
        expect(case2.days[3].status == .incomplete, "CASE 2: missed day is incomplete")
        expect(case2.completedDays == 6 && case2.applicableDays == 7, "CASE 2: 6/7 complete, not 7/7")
        expect(case2.adherencePercentage != 100, "CASE 2: not 100%")

        missedLogs[3] = probe(day(3), medicine: med, status: .takenLate)
        let case3 = DoseLoop.weeklyMedicationProgress(
            logs: missedLogs,
            treatmentWindows: fullWindow,
            now: nowSunday,
            calendar: cal,
            todayCounts: counts(missedLogs.filter { cal.isDate($0.scheduledAt, inSameDayAs: sunday) }, now: nowSunday)
        )
        expect(case3.days[3].status == .complete, "CASE 3: takenLate recovers the day to complete")
        expect(case3.completedDays == 7 && case3.applicableDays == 7, "CASE 3: weekly summary updates")

        let startWed = [DoseLoop.TreatmentWindow(start: wednesday, end: nil)]
        let wedLogs = (2...4).map { probe(day($0), medicine: med, status: .taken) }
        let nowFri = day(4, hour: 18)
        let case4 = DoseLoop.weeklyMedicationProgress(
            logs: wedLogs,
            treatmentWindows: startWed,
            now: nowFri,
            calendar: cal,
            todayCounts: counts([wedLogs.last!], now: nowFri)
        )
        expect(case4.days[0].status == .notApplicable && case4.days[1].status == .notApplicable, "CASE 4: Mon/Tue not applicable")
        expect(case4.days[2].status == .complete && case4.days[3].status == .complete && case4.days[4].status == .complete, "CASE 4: Wed onward actual")
        expect(!case4.days.contains(where: { $0.status == .incomplete }), "CASE 4: no false missed")
        expect(case4.completedDays == 3 && case4.applicableDays == 3, "CASE 4: denominator is treatment days only")

        let nowWed = day(2, hour: 12)
        let case5Logs = (0...2).map { probe(day($0), medicine: med, status: .taken) }
        let case5 = DoseLoop.weeklyMedicationProgress(
            logs: case5Logs,
            treatmentWindows: fullWindow,
            now: nowWed,
            calendar: cal,
            todayCounts: counts([case5Logs[2]], now: nowWed)
        )
        expect(case5.days[2].isToday && case5.days[2].status == .complete, "CASE 5: today complete")
        expect(case5.days[3...6].allSatisfy { $0.status == .future }, "CASE 5: Thu–Sun future")
        expect(!case5.days[3...6].contains(where: { $0.status == .incomplete }), "CASE 5: future is not missed")
        expect(case5.completedDays == 3 && case5.applicableDays == 3, "CASE 5: Mon–Wed elapsed only")

        let endFri = [DoseLoop.TreatmentWindow(start: monday, end: friday)]
        let case6 = DoseLoop.weeklyMedicationProgress(
            logs: (0...4).map { probe(day($0), medicine: med, status: .taken) },
            treatmentWindows: endFri,
            now: nowSunday,
            calendar: cal,
            todayCounts: counts([], now: nowSunday)
        )
        expect(case6.days[5].status == .notApplicable && case6.days[6].status == .notApplicable, "CASE 6: Sat/Sun not applicable")
        expect(case6.days[5].status != .incomplete && case6.days[6].status != .incomplete, "CASE 6: not missed after end")

        let case7 = DoseLoop.weeklyMedicationProgress(
            logs: [],
            treatmentWindows: [],
            now: nowSunday,
            calendar: cal,
            todayCounts: .init(
                scheduledCount: 0,
                takenCount: 0,
                takenLateCount: 0,
                completedCount: 0,
                missedCount: 0,
                remainingCount: 0,
                unresolvedCount: 0,
                isComplete: false
            )
        )
        expect(case7.days.allSatisfy { $0.status == .notApplicable }, "CASE 7: no treatment is not applicable")
        expect(case7.applicableDays == 0 && case7.adherencePercentage == nil, "CASE 7: no fake adherence")

        let eightMeds = (0..<8).map { _ in UUID() }
        func eight(_ statuses: [DoseLogStatus], at: Date) -> [DoseLoop.DoseSummaryProbe] {
            zip(eightMeds, statuses).enumerated().map { index, pair in
                probe(at, medicine: pair.0, status: pair.1, minuteOffset: index)
            }
        }
        let sevenMissed = Array(repeating: DoseLogStatus.taken, count: 7) + [.missed]
        let eightNow = day(2, hour: 21)
        let eightMissedLogs = eight(sevenMissed, at: wednesday)
        let case8 = DoseLoop.weeklyMedicationProgress(
            logs: eightMissedLogs,
            treatmentWindows: startWed,
            now: eightNow,
            calendar: cal,
            todayCounts: counts(eightMissedLogs, now: eightNow)
        )
        expect(case8.days[2].status == .incomplete, "CASE 8: 7 taken + 1 missed is incomplete")
        expect(case8.days[2].scheduledCount == 8 && case8.days[2].completedCount == 7, "CASE 8: counts from DoseLogs not medicines")

        let sevenLate = Array(repeating: DoseLogStatus.taken, count: 7) + [.takenLate]
        let eightLateLogs = eight(sevenLate, at: wednesday)
        let case9 = DoseLoop.weeklyMedicationProgress(
            logs: eightLateLogs,
            treatmentWindows: startWed,
            now: eightNow,
            calendar: cal,
            todayCounts: counts(eightLateLogs, now: eightNow)
        )
        expect(case9.days[2].status == .complete, "CASE 9: 7 taken + 1 takenLate is complete")
        expect(case9.days[2].completedCount == 8, "CASE 9: completedCount includes takenLate")

        let case10Missed = case8
        expect(case10Missed.days[2].isToday && case10Missed.days[2].status == .incomplete, "CASE 10: today matches 7/8 missed")
        expect(case9.days[2].isToday && case9.days[2].status == .complete, "CASE 10: after takenLate today is complete")
        return failures
    }
}

enum AdherenceStreakContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ ok: Bool, _ name: String) {
            if !ok { failures.append(name) }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        func day(_ offset: Int, hour: Int = 8) -> Date {
            var comps = DateComponents()
            comps.year = 2026
            comps.month = 9
            comps.day = 14 + offset
            comps.hour = hour
            return cal.date(from: comps) ?? Date()
        }
        let monday = day(0)
        let nowSun = day(6, hour: 20)
        let emptyCounts = DoseLoop.TodayChallengeCounts(
            scheduledCount: 0,
            takenCount: 0,
            takenLateCount: 0,
            completedCount: 0,
            missedCount: 0,
            remainingCount: 0,
            unresolvedCount: 0,
            isComplete: false
        )
        func probe(_ date: Date, medicine: UUID, status: DoseLogStatus, minuteOffset: Int = 0) -> DoseLoop.DoseSummaryProbe {
            DoseLoop.DoseSummaryProbe(
                id: UUID(),
                scheduleId: UUID(),
                medicineId: medicine,
                scheduledAt: date.addingTimeInterval(TimeInterval(minuteOffset * 60)),
                status: status
            )
        }
        func counts(_ logs: [DoseLoop.DoseSummaryProbe], now: Date) -> DoseLoop.TodayChallengeCounts {
            DoseLoop.todayChallengeCounts(logs: logs, now: now, calendar: cal)
        }
        let med = UUID()
        let eightMeds = (0..<8).map { _ in UUID() }
        func eight(_ statuses: [DoseLogStatus], at: Date) -> [DoseLoop.DoseSummaryProbe] {
            zip(eightMeds, statuses).enumerated().map { index, pair in
                probe(at, medicine: pair.0, status: pair.1, minuteOffset: index)
            }
        }
        let startToday = [DoseLoop.TreatmentWindow(start: nowSun, end: nil)]
        let fullWindow = [DoseLoop.TreatmentWindow(start: monday, end: day(6))]

        let case1 = DoseLoop.adherenceStreak(
            logs: [],
            treatmentWindows: [],
            now: nowSun,
            calendar: cal,
            todayCounts: emptyCounts
        )
        expect(case1.currentDays == 0 && case1.longestDays == 0, "CASE 1: no treatment is streak 0")

        let oneTaken = eight(Array(repeating: DoseLogStatus.pending, count: 7) + [.taken], at: nowSun)
        let case2 = DoseLoop.adherenceStreak(
            logs: oneTaken,
            treatmentWindows: startToday,
            now: nowSun,
            calendar: cal,
            todayCounts: counts(oneTaken, now: nowSun)
        )
        expect(case2.currentDays == 0, "CASE 2/12: 1/8 taken today does not increase streak")

        let fourTaken = (0..<4).map { probe(nowSun, medicine: eightMeds[$0], status: .taken, minuteOffset: $0) }
        let case3 = DoseLoop.adherenceStreak(
            logs: fourTaken,
            treatmentWindows: startToday,
            now: nowSun,
            calendar: cal,
            todayCounts: counts(fourTaken, now: nowSun)
        )
        expect(case3.currentDays == 1, "CASE 3/15: fully taken day is streak 1")

        let sevenLate = Array(repeating: DoseLogStatus.taken, count: 7) + [.takenLate]
        let lateLogs = eight(sevenLate, at: nowSun)
        let case4 = DoseLoop.adherenceStreak(
            logs: lateLogs,
            treatmentWindows: startToday,
            now: nowSun,
            calendar: cal,
            todayCounts: counts(lateLogs, now: nowSun)
        )
        expect(case4.currentDays == 1, "CASE 4/9: 7 taken + 1 takenLate contributes")

        let wed = day(2)
        let threeDays = (0...2).map { probe(day($0), medicine: med, status: .taken) }
        let case5 = DoseLoop.adherenceStreak(
            logs: threeDays,
            treatmentWindows: fullWindow,
            now: day(2, hour: 20),
            calendar: cal,
            todayCounts: counts([threeDays[2]], now: day(2, hour: 20))
        )
        expect(case5.currentDays == 3 && case5.longestDays == 3, "CASE 5: three consecutive complete days")

        let broken = [
            probe(monday, medicine: med, status: .taken),
            probe(day(1), medicine: med, status: .taken),
            probe(day(2), medicine: med, status: .missed),
            probe(day(3), medicine: med, status: .taken),
        ]
        let case6 = DoseLoop.adherenceStreak(
            logs: broken,
            treatmentWindows: fullWindow,
            now: day(3, hour: 20),
            calendar: cal,
            todayCounts: counts([broken[3]], now: day(3, hour: 20))
        )
        expect(case6.currentDays == 1 && case6.longestDays == 2, "CASE 6: incomplete day resets current, preserves longest")

        let thuWindow = [DoseLoop.TreatmentWindow(start: day(3), end: nil)]
        let thuSun = (3...6).map { probe(day($0), medicine: med, status: .taken) }
        let case7 = DoseLoop.adherenceStreak(
            logs: thuSun,
            treatmentWindows: thuWindow,
            now: nowSun,
            calendar: cal,
            todayCounts: counts([thuSun[3]], now: nowSun)
        )
        expect(case7.currentDays == 4, "CASE 7/12: mid-week start does not invent Mon–Wed misses")

        let endFri = [DoseLoop.TreatmentWindow(start: monday, end: day(4))]
        let monFri = (0...4).map { probe(day($0), medicine: med, status: .taken) }
        let case8 = DoseLoop.adherenceStreak(
            logs: monFri,
            treatmentWindows: endFri,
            now: nowSun,
            calendar: cal,
            todayCounts: emptyCounts
        )
        expect(case8.currentDays == 5, "CASE 8: days after treatment end do not break the streak")

        let restTuesday = [
            probe(monday, medicine: med, status: .taken),
            probe(wed, medicine: med, status: .taken),
        ]
        let case9 = DoseLoop.adherenceStreak(
            logs: restTuesday,
            treatmentWindows: fullWindow,
            now: day(2, hour: 20),
            calendar: cal,
            todayCounts: counts([restTuesday[1]], now: day(2, hour: 20))
        )
        expect(case9.currentDays == 2, "CASE 9: no-scheduled day does not break streak")

        let taken = probe(nowSun, medicine: med, status: .taken)
        let duplicatePending = probe(nowSun, medicine: med, status: .pending)
        let case10 = DoseLoop.adherenceStreak(
            logs: [taken, duplicatePending],
            treatmentWindows: startToday,
            now: nowSun,
            calendar: cal,
            todayCounts: counts([taken, duplicatePending], now: nowSun)
        )
        expect(case10.currentDays == 1, "CASE 10: duplicate pending sibling does not block completion")

        let oldLog = probe(day(0), medicine: med, status: .missed)
        let todayStartWindow = [DoseLoop.TreatmentWindow(start: nowSun, end: nil)]
        let sunTaken = probe(nowSun, medicine: med, status: .taken)
        let case11 = DoseLoop.adherenceStreak(
            logs: [oldLog, sunTaken],
            treatmentWindows: todayStartWindow,
            now: nowSun,
            calendar: cal,
            todayCounts: counts([sunTaken], now: nowSun)
        )
        expect(case11.currentDays == 1 && case11.longestDays == 1, "CASE 11: logs before treatment start do not count or break")

        let remaining = probe(nowSun, medicine: med, status: .pending, minuteOffset: 60)
        let satTaken = probe(day(5), medicine: med, status: .taken)
        let case12 = DoseLoop.adherenceStreak(
            logs: [satTaken, remaining],
            treatmentWindows: fullWindow,
            now: nowSun,
            calendar: cal,
            todayCounts: counts([remaining], now: nowSun)
        )
        expect(case12.currentDays == 1, "CASE 12/14: unfinished today is not a streak day")

        let recovered = eight(sevenLate, at: nowSun)
        let case13 = DoseLoop.adherenceStreak(
            logs: recovered,
            treatmentWindows: startToday,
            now: nowSun,
            calendar: cal,
            todayCounts: counts(recovered, now: nowSun)
        )
        expect(case13.currentDays == 1, "CASE 13: late recovery makes the same day complete")

        let futureLog = probe(day(7), medicine: med, status: .pending)
        let case14 = DoseLoop.adherenceStreak(
            logs: [sunTaken, futureLog],
            treatmentWindows: [DoseLoop.TreatmentWindow(start: monday, end: nil)],
            now: nowSun,
            calendar: cal,
            todayCounts: counts([sunTaken], now: nowSun)
        )
        expect(case14.currentDays == 1, "CASE 14: future day is ignored")

        let again = DoseLoop.adherenceStreak(
            logs: fourTaken,
            treatmentWindows: startToday,
            now: nowSun,
            calendar: cal,
            todayCounts: counts(fourTaken, now: nowSun)
        )
        expect(again == case3, "CASE 16: same persisted inputs yield the same streak")
        return failures
    }
}
#endif
