import AppIntents
import Foundation

/// AlarmKit stop action: mark the dose taken (stays free) and let reminders rebuild.
nonisolated struct DoseTakenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Taken"
    static var description: IntentDescription = IntentDescription("Marks this CheckMed dose as taken.")
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
        await ReminderScheduler.shared.applyIntent(logId: logId, status: .taken)
        return .result()
    }
}

/// AlarmKit secondary action: skip this dose without inventing a catch-up dose.
nonisolated struct DoseSkipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip"
    static var description: IntentDescription = IntentDescription("Skips this CheckMed dose.")
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
        await ReminderScheduler.shared.applyIntent(logId: logId, status: .skipped)
        return .result()
    }
}
