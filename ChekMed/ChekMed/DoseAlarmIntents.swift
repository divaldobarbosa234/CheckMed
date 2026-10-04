import AppIntents
import Foundation

/// Explicit confirm from a notification action. Never attached to AlarmKit Stop.
nonisolated struct DoseTakenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "I took it"
    static var description: IntentDescription = IntentDescription("Confirms this Conny Cooper dose was taken.")
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @Parameter(title: "Log")
    var logId: String

    init() {
        logId = ""
    }

    init(logId: String) {
        self.logId = logId
    }

    func perform() async throws -> some IntentResult {
        await ReminderScheduler.shared.applyIntent(logId: logId, action: .confirmTaken)
        return .result()
    }
}

/// AlarmKit / notification snooze: same dose event, still unconfirmed.
nonisolated struct DoseSnoozeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze"
    static var description: IntentDescription = IntentDescription("Snoozes this Conny Cooper dose without marking it taken.")
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @Parameter(title: "Log")
    var logId: String

    init() {
        logId = ""
    }

    init(logId: String) {
        self.logId = logId
    }

    func perform() async throws -> some IntentResult {
        await ReminderScheduler.shared.applyIntent(logId: logId, action: .snooze)
        return .result()
    }
}

/// AlarmKit Stop / dismiss: not taken. Follow-up confirmation is scheduled separately.
nonisolated struct DoseStoppedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"
    static var description: IntentDescription = IntentDescription("Stops this Conny Cooper alarm without marking the dose taken.")
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @Parameter(title: "Log")
    var logId: String

    init() {
        logId = ""
    }

    init(logId: String) {
        self.logId = logId
    }

    func perform() async throws -> some IntentResult {
        await ReminderScheduler.shared.applyIntent(logId: logId, action: .stop)
        return .result()
    }
}
