import Foundation

/// Derived Journey Tree placement. Not persisted. Never writes SwiftData.
enum TreatmentJourneyKind: Equatable, Sendable {
    case current
    case future
    case past
}

enum TreatmentJourneyClassification {
    /// Calendar-day classification from canonical `TreatmentRecord` fields.
    /// Deleted treatments return `nil` (no Journey section).
    /// Past wins over future when `endDate` is already before today.
    static func classify(
        deletedAt: Date?,
        status: String,
        startDate: Date,
        endDate: Date?,
        now: Date,
        calendar: Calendar
    ) -> TreatmentJourneyKind? {
        guard deletedAt == nil else { return nil }
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: startDate)
        if status == "completed" { return .past }
        if let end = endDate, calendar.startOfDay(for: end) < today { return .past }
        guard status == "active" else { return nil }
        if start > today { return .future }
        return .current
    }
}

#if DEBUG
enum TreatmentJourneyClassificationContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day: (Int, Int, Int) -> Date = { y, m, d in
            calendar.date(from: DateComponents(year: y, month: m, day: d))!
        }
        let today = day(2026, 9, 26)

        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: today, status: "active", startDate: today, endDate: nil, now: today, calendar: calendar
            ) == nil,
            "deleted treatment is not on the Journey Tree"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil, status: "active", startDate: today, endDate: nil, now: today, calendar: calendar
            ) == .current,
            "start today, no end is current"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil, status: "active", startDate: day(2026, 9, 5), endDate: nil, now: today, calendar: calendar
            ) == .current,
            "past start, no end is current"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil, status: "active", startDate: day(2026, 9, 1), endDate: today, now: today, calendar: calendar
            ) == .current,
            "end today is current"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil, status: "active", startDate: day(2026, 9, 1), endDate: day(2026, 9, 25), now: today, calendar: calendar
            ) == .past,
            "end yesterday is past even if status is active"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil, status: "completed", startDate: day(2026, 9, 1), endDate: today, now: today, calendar: calendar
            ) == .past,
            "completed is past"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil, status: "active", startDate: day(2026, 10, 1), endDate: day(2026, 10, 20), now: today, calendar: calendar
            ) == .future,
            "start tomorrow is future"
        )
        expect(
            TreatmentJourneyClassification.classify(
                deletedAt: nil, status: "active", startDate: day(2026, 10, 1), endDate: day(2026, 9, 20), now: today, calendar: calendar
            ) == .past,
            "ended endDate wins over future start"
        )
        return failures
    }
}
#endif
