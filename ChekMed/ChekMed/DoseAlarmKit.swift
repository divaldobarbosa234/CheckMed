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
enum DoseAlarmKit {
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

    /// Returns log IDs that were successfully scheduled with AlarmKit (skip UN dose notifications for these).
    static func syncDoseAlarms(drafts: [ReminderDraft], locale: AppLocale, theme: AlarmTheme) async -> Set<UUID> {
        guard #available(iOS 26.0, *) else { return [] }
        #if canImport(AlarmKit)
        var scheduled = Set<UUID>()
        let manager = AlarmManager.shared
        if let existing = try? manager.alarms {
            for alarm in existing {
                try? manager.cancel(id: alarm.id)
            }
        }
        if manager.authorizationState == .notDetermined {
            _ = try? await manager.requestAuthorization()
        }
        guard manager.authorizationState == .authorized else { return [] }

        let upcoming = drafts.filter { $0.kind == .dose && $0.fireDate > Date().addingTimeInterval(8) }.prefix(16)
        for draft in upcoming {
            do {
                try await schedule(draft: draft, locale: locale, theme: theme)
                scheduled.insert(draft.id)
            } catch {
                continue
            }
        }
        return scheduled
        #else
        return []
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func schedule(draft: ReminderDraft, locale: AppLocale, theme: AlarmTheme) async throws {
        let titleText = L10n.string(.notificationDoseTitle, locale: locale)
        let body = L10n.string(
            .notificationDoseBody,
            locale: locale,
            args: [draft.medicine, draft.doseLabel, draft.time]
        )
        let takenLabel = L10n.string(.taken, locale: locale)
        let skipLabel = L10n.string(.skip, locale: locale)

        let skipButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: skipLabel),
            textColor: .white,
            systemImageName: "forward.end"
        )
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: "\(titleText) · \(body)"),
                secondaryButton: skipButton,
                secondaryButtonBehavior: .custom
            )
        } else {
            let stopButton = AlarmButton(
                text: LocalizedStringResource(stringLiteral: takenLabel),
                textColor: .white,
                systemImageName: "checkmark.circle"
            )
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: "\(titleText) · \(body)"),
                stopButton: stopButton,
                secondaryButton: skipButton,
                secondaryButtonBehavior: .custom
            )
        }
        let attributes = AlarmAttributes<DoseAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: DoseAlarmMetadata(),
            tintColor: theme.tint
        )
        let sound = ActivityKit.AlertConfiguration.AlertSound.named(theme.soundFileName)
        let configuration = AlarmManager.AlarmConfiguration<DoseAlarmMetadata>(
            schedule: .fixed(draft.fireDate),
            attributes: attributes,
            stopIntent: DoseTakenIntent(logId: draft.id.uuidString),
            secondaryIntent: DoseSkipIntent(logId: draft.id.uuidString),
            sound: sound
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: draft.id, configuration: configuration)
        } catch {
            let fallback = AlarmManager.AlarmConfiguration<DoseAlarmMetadata>(
                schedule: .fixed(draft.fireDate),
                attributes: attributes,
                stopIntent: DoseTakenIntent(logId: draft.id.uuidString),
                secondaryIntent: DoseSkipIntent(logId: draft.id.uuidString),
                sound: .default
            )
            _ = try await AlarmManager.shared.schedule(id: draft.id, configuration: fallback)
        }
    }
    #endif
}
