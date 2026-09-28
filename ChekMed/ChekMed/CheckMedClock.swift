import Foundation

/// DEBUG TestClock v1. Release always returns wall-clock `Date()`.
/// Not observable. Does not tick. Does not publish. Does not schedule.
enum CheckMedClock {
    #if DEBUG
    nonisolated(unsafe) private static var frozenDate: Date?
    nonisolated(unsafe) private static var commandBridgeInstalled = false
    nonisolated(unsafe) private static var timeZoneProvider: (() -> TimeZone)?
    nonisolated(unsafe) private static var onApplied: (() -> Void)?
    private static let commandFileName = "checkmed-clock-command.txt"
    static let darwinName = "com.checkmed.debug.clock"
    #endif

    static var now: Date {
        #if DEBUG
        frozenDate ?? Date()
        #else
        Date()
        #endif
    }

    #if DEBUG
    static var isFrozen: Bool { frozenDate != nil }

    static func set(_ date: Date) {
        frozenDate = date
    }

    static func advance(_ interval: TimeInterval) {
        frozenDate = now.addingTimeInterval(interval)
    }

    static func reset() {
        frozenDate = nil
    }

    enum Command: Equatable {
        case reset
        case set(Date)
        case advance(TimeInterval)
    }

    static func parseCommand(_ line: String, timeZone: TimeZone) -> Command? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "reset" {
            return .reset
        }
        if trimmed.hasPrefix("set ") {
            let rest = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            guard let date = formatter.date(from: rest) else { return nil }
            return .set(date)
        }
        if trimmed.hasPrefix("advance ") {
            let rest = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("+"), rest.hasSuffix("m") else { return nil }
            let digits = rest.dropFirst().dropLast()
            guard let minutes = Int(digits), minutes >= 0 else { return nil }
            return .advance(TimeInterval(minutes * 60))
        }
        return nil
    }

    static func apply(_ command: Command) {
        switch command {
        case .reset:
            reset()
        case .set(let date):
            set(date)
        case .advance(let interval):
            advance(interval)
        }
    }

    static func commandFileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(commandFileName)
    }

    static func applyPendingFileCommand(timeZone: TimeZone) -> Bool {
        guard let url = commandFileURL(),
              let raw = try? String(contentsOf: url, encoding: .utf8),
              let command = parseCommand(raw, timeZone: timeZone) else {
            return false
        }
        apply(command)
        return true
    }

    static func installCommandBridge(
        timeZone: @escaping () -> TimeZone,
        onApplied: @escaping () -> Void
    ) {
        timeZoneProvider = timeZone
        self.onApplied = onApplied
        guard !commandBridgeInstalled else { return }
        commandBridgeInstalled = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    CheckMedClock.handleDarwinCommand()
                }
            },
            darwinName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private static func handleDarwinCommand() {
        let zone = timeZoneProvider?() ?? .current
        guard applyPendingFileCommand(timeZone: zone) else { return }
        print("[TESTCLOCK] applied file command frozen=\(isFrozen) now=\(now)")
        onApplied?()
    }
    #endif
}

#if DEBUG
enum CheckMedClockContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        CheckMedClock.reset()
        defer { CheckMedClock.reset() }

        expect(!CheckMedClock.isFrozen, "reset must leave clock unfrozen")
        let wallBefore = Date()
        let live = CheckMedClock.now
        expect(abs(live.timeIntervalSince(wallBefore)) < 2, "unfrozen now must track device time")

        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        CheckMedClock.set(frozen)
        expect(CheckMedClock.isFrozen, "set must freeze")
        expect(CheckMedClock.now == frozen, "set must return the frozen instant")
        expect(CheckMedClock.now == frozen, "frozen now must be stable")

        CheckMedClock.advance(5 * 60)
        expect(CheckMedClock.now == frozen.addingTimeInterval(5 * 60), "advance +5m from freeze")
        CheckMedClock.advance(30 * 60)
        expect(CheckMedClock.now == frozen.addingTimeInterval(35 * 60), "advance is cumulative")
        CheckMedClock.advance(45 * 60)
        expect(CheckMedClock.now == frozen.addingTimeInterval(80 * 60), "advance +45m")

        CheckMedClock.reset()
        expect(!CheckMedClock.isFrozen, "reset after freeze must unfreeze")
        let afterReset = CheckMedClock.now
        expect(abs(afterReset.timeIntervalSince(Date())) < 2, "reset must return to device time")

        CheckMedClock.reset()
        CheckMedClock.advance(10 * 60)
        expect(CheckMedClock.isFrozen, "advance from live time must freeze")
        expect(CheckMedClock.now.timeIntervalSince(Date()) > 9 * 60, "advance from live adds interval")

        let chicago = TimeZone(identifier: "America/Chicago")!
        let newYork = TimeZone(identifier: "America/New_York")!
        expect(CheckMedClock.parseCommand("reset", timeZone: chicago) == .reset, "parse reset")
        expect(CheckMedClock.parseCommand("advance +5m", timeZone: chicago) == .advance(5 * 60), "parse +5m")
        expect(CheckMedClock.parseCommand("advance +30m", timeZone: chicago) == .advance(30 * 60), "parse +30m")
        expect(CheckMedClock.parseCommand("advance +45m", timeZone: chicago) == .advance(45 * 60), "parse +45m")
        expect(CheckMedClock.parseCommand("advance 5m", timeZone: chicago) == nil, "advance requires +")
        expect(CheckMedClock.parseCommand("set not-a-date", timeZone: chicago) == nil, "invalid set")

        guard case .set(let chicagoInstant)? = CheckMedClock.parseCommand("set 2026-09-27 08:00", timeZone: chicago) else {
            failures.append("parse set Chicago")
            return failures
        }
        guard case .set(let yorkInstant)? = CheckMedClock.parseCommand("set 2026-09-27 08:00", timeZone: newYork) else {
            failures.append("parse set New York")
            return failures
        }
        expect(chicagoInstant != yorkInstant, "same wall time must differ by timezone")
        var chicagoCalendar = Calendar(identifier: .gregorian)
        chicagoCalendar.timeZone = chicago
        let chicagoParts = chicagoCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: chicagoInstant)
        expect(chicagoParts.year == 2026 && chicagoParts.month == 9 && chicagoParts.day == 27, "Chicago calendar day")
        expect(chicagoParts.hour == 8 && chicagoParts.minute == 0, "Chicago wall 08:00")
        var yorkCalendar = Calendar(identifier: .gregorian)
        yorkCalendar.timeZone = newYork
        let yorkParts = yorkCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: yorkInstant)
        expect(yorkParts.hour == 8 && yorkParts.minute == 0, "New York wall 08:00")

        return failures
    }
}
#endif
