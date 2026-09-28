import Foundation
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
import ActivityKit

@available(iOS 26.0, *)
nonisolated struct DoseAlarmMetadata: AlarmMetadata {}
#else
nonisolated struct DoseAlarmMetadata: Codable, Hashable, Sendable {}
#endif

/// Schedules AlarmKit alerts for upcoming doses on iOS 26+. Falls closed to `UNUserNotificationCenter` when unauthorized or scheduling fails.
/// AlarmKit exposes Stop plus one secondary button — not a reliable extra “I took it” action — so Stop is never Taken.
/// Entry points hop to `@MainActor`: `AlarmManager` requires the main thread.
nonisolated enum DoseAlarmKit {
    static var isSupported: Bool {
        if #available(iOS 26.0, *) {
            #if canImport(AlarmKit)
            return true
            #else
            return false
            #endif
        }
        return false
    }

    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        await requestAuthorizationOnMain()
    }

    /// Returns log IDs that were successfully scheduled with AlarmKit (skip UN dose notifications for these).
    /// Must run on the main actor/thread — call from `@MainActor` `ReminderScheduler.rebuild` via `await`.
    struct Copy: Sendable {
        var title: String
        var snooze: String
        var stop: String
        var soundFileName: String
        var red: Double
        var green: Double
        var blue: Double
    }

    static func syncDoseAlarms(drafts: [ReminderDraft], asOf now: Date = Date(), copy: Copy) async -> Set<UUID> {
        await syncDoseAlarmsOnMain(drafts: drafts, asOf: now, copy: copy)
    }

    @MainActor
    private static func requestAuthorizationOnMain() async -> Bool {
        await withTimeoutOnMain(seconds: 2.2) {
            await requestAuthorizationUnbound()
        } ?? false
    }

    @MainActor
    private static func syncDoseAlarmsOnMain(
        drafts: [ReminderDraft],
        asOf now: Date,
        copy: Copy
    ) async -> Set<UUID> {
        await withTimeoutOnMain(seconds: 2.8) {
            await syncDoseAlarmsUnbound(drafts: drafts, asOf: now, copy: copy)
        } ?? []
    }

    @MainActor
    private static func requestAuthorizationUnbound() async -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        #if canImport(AlarmKit)
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        @unknown default:
            return false
        }
        #else
        return false
        #endif
    }

    @MainActor
    private static func syncDoseAlarmsUnbound(
        drafts: [ReminderDraft],
        asOf now: Date,
        copy: Copy
    ) async -> Set<UUID> {
        guard #available(iOS 26.0, *) else { return [] }
        #if canImport(AlarmKit)
        let upcoming = Array(
            drafts.filter { $0.kind == .dose && $0.fireDate > now.addingTimeInterval(8) }.prefix(16)
        )
        let manager = AlarmManager.shared
        if let existing = try? manager.alarms {
            for alarm in existing {
                try? manager.cancel(id: alarm.id)
            }
        }
        guard !upcoming.isEmpty else { return [] }

        guard manager.authorizationState == .authorized else { return [] }

        var scheduled = Set<UUID>()
        for draft in upcoming {
            if Task.isCancelled { break }
            do {
                try await schedule(draft: draft, copy: copy)
                scheduled.insert(draft.id)
            } catch {
                continue
            }
        }
        let liveIds = Set(((try? manager.alarms) ?? []).map(\.id))
        return scheduled.intersection(liveIds)
        #else
        return []
        #endif
    }

    /// Timeout that keeps AlarmKit work on the main actor (unlike a bare `@Sendable` task-group child).
    @MainActor
    private static func withTimeoutOnMain<T: Sendable>(
        seconds: TimeInterval,
        _ work: @escaping @MainActor () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { @MainActor in
                await work()
            }
            group.addTask {
                let ns = UInt64(max(0.2, seconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            // Drain so a timed-out AlarmKit schedule cannot keep running after rebuild continues.
            for await _ in group {}
            return first
        }
    }

    #if canImport(AlarmKit)
    @MainActor
    @available(iOS 26.0, *)
    private static func schedule(draft: ReminderDraft, copy: Copy) async throws {
        let titleText = copy.title
        let body = "\(draft.medicine) · \(draft.doseLabel)"
        let snoozeLabel = copy.snooze
        let stopLabel = copy.stop

        let snoozeButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: snoozeLabel),
            textColor: .white,
            systemImageName: "clock.arrow.circlepath"
        )
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: "\(titleText) · \(body)"),
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .custom
            )
        } else {
            let stopButton = AlarmButton(
                text: LocalizedStringResource(stringLiteral: stopLabel),
                textColor: .white,
                systemImageName: "stop.circle"
            )
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: "\(titleText) · \(body)"),
                stopButton: stopButton,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .custom
            )
        }
        let attributes = AlarmAttributes<DoseAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: DoseAlarmMetadata(),
            tintColor: Color(red: copy.red, green: copy.green, blue: copy.blue)
        )
        let sound = ActivityKit.AlertConfiguration.AlertSound.named(copy.soundFileName)
        let configuration = AlarmManager.AlarmConfiguration<DoseAlarmMetadata>(
            schedule: .fixed(draft.fireDate),
            attributes: attributes,
            stopIntent: DoseStoppedIntent(logId: draft.id.uuidString),
            secondaryIntent: DoseSnoozeIntent(logId: draft.id.uuidString),
            sound: sound
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: draft.id, configuration: configuration)
        } catch {
            let fallback = AlarmManager.AlarmConfiguration<DoseAlarmMetadata>(
                schedule: .fixed(draft.fireDate),
                attributes: attributes,
                stopIntent: DoseStoppedIntent(logId: draft.id.uuidString),
                secondaryIntent: DoseSnoozeIntent(logId: draft.id.uuidString),
                sound: .default
            )
            _ = try await AlarmManager.shared.schedule(id: draft.id, configuration: fallback)
        }
    }
    #endif
}
