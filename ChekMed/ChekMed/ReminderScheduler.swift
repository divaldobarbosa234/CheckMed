import Foundation
import UserNotifications

enum ReminderAction {
    static let category = "CHECKMED_DOSE"
    static let taken = "CHECKMED_TAKEN"
    static let skip = "CHECKMED_SKIP"
}

@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    @ObservationIgnored
    private weak var store: CheckMedStore?
    @ObservationIgnored
    private weak var session: SessionStore?
    @ObservationIgnored
    private weak var entitlements: EntitlementStore?
    @ObservationIgnored
    private var voice: PhilVoice?

    private var rescheduleTask: Task<Void, Never>?
    private var pendingAction: (id: UUID, status: DoseLogStatus)?

    func configure() {
        let taken = UNNotificationAction(
            identifier: ReminderAction.taken,
            title: L10n.string(.taken, locale: .english),
            options: []
        )
        let skip = UNNotificationAction(
            identifier: ReminderAction.skip,
            title: L10n.string(.skip, locale: .english),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: ReminderAction.category,
            actions: [taken, skip],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
    }

    func bind(store: CheckMedStore, session: SessionStore, entitlements: EntitlementStore, voice: PhilVoice) {
        self.store = store
        self.session = session
        self.entitlements = entitlements
        self.voice = voice
        flushPendingAction()
        reschedule()
    }

    func reschedule() {
        guard session?.hasCompletedOnboarding == true else { return }
        rescheduleTask?.cancel()
        rescheduleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await rebuild()
        }
    }

    func handleLogAction(id: UUID, status: DoseLogStatus) {
        if let store {
            store.markLog(id: id, status: status)
        } else {
            CheckMedStore.persistDoseStatus(id: id, status: status)
            pendingAction = (id, status)
        }
        reschedule()
    }

    func applyIntent(logId: String, status: DoseLogStatus) {
        guard let id = UUID(uuidString: logId) else { return }
        handleLogAction(id: id, status: status)
    }

    private func flushPendingAction() {
        guard let pendingAction, let store else { return }
        store.markLog(id: pendingAction.id, status: pendingAction.status)
        self.pendingAction = nil
    }

    private func rebuild() async {
        guard let store, let session else { return }

        let drafts = store.reminderDrafts().filter { draft in
            if draft.kind == .advance {
                return entitlements?.canUseAdvanceReminder == true && ReminderPreferences.advanceHourEnabled
            }
            if draft.kind == .refill { return false }
            return true
        } + (entitlements?.canUseRefillReminder == true ? store.refillDrafts() : [])
        let locale = session.locale
        let theme = entitlements?.canChooseAlarmTheme == true
            ? ReminderPreferences.alarmTheme
            : .philChime
        let alarmKitDoseIds = await DoseAlarmKit.syncDoseAlarms(drafts: drafts, locale: locale, theme: theme)

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let existing = await center.pendingNotificationRequests()
        let ours = existing.filter { $0.identifier.hasPrefix("checkmed.") }.map(\.identifier)
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let taken = UNNotificationAction(
            identifier: ReminderAction.taken,
            title: L10n.string(.taken, locale: locale),
            options: []
        )
        let skip = UNNotificationAction(
            identifier: ReminderAction.skip,
            title: L10n.string(.skip, locale: locale),
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: ReminderAction.category,
                actions: [taken, skip],
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
        let sound = UNNotificationSound(named: UNNotificationSoundName(theme.soundFileName))
        let calendar = session.foundationCalendar

        for draft in drafts.prefix(48) {
            if draft.kind == .missed, isInQuietHours(draft.fireDate, calendar: calendar) {
                continue
            }
            guard draft.fireDate > Date().addingTimeInterval(8) else { continue }
            if draft.kind == .dose, alarmKitDoseIds.contains(draft.id) { continue }
            let content = UNMutableNotificationContent()
            content.categoryIdentifier = ReminderAction.category
            content.sound = sound
            content.userInfo = ["logId": draft.id.uuidString, "kind": draft.kind.rawValue]
            content.interruptionLevel = .active
            switch draft.kind {
            case .dose:
                content.title = session.t(.notificationDoseTitle)
                content.body = session.t(.notificationDoseBody, draft.medicine, draft.doseLabel, draft.time)
            case .missed:
                content.title = session.t(.notificationMissedTitle)
                content.body = session.t(.notificationMissedBody, draft.medicine, draft.time)
            case .advance:
                guard entitlements?.canUseAdvanceReminder == true,
                      ReminderPreferences.advanceHourEnabled else { continue }
                content.title = session.t(.notificationAdvanceTitle)
                content.body = session.t(.notificationAdvanceBody, draft.medicine, draft.time)
                content.categoryIdentifier = ""
            case .refill:
                content.title = session.t(.notificationRefillTitle)
                content.body = session.t(.notificationRefillBody, draft.medicine)
                content.categoryIdentifier = ""
            }
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: draft.fireDate
            )
            components.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: draft.notificationId,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                continue
            }
        }

        center.removePendingNotificationRequests(withIdentifiers: [Engagement.winBackId])
        if ReminderPreferences.winBackEnabled, let winBack = Engagement.winBackDate() {
            let content = UNMutableNotificationContent()
            content.title = session.t(.notificationWinBackTitle)
            content.body = session.t(.notificationWinBackBody)
            content.sound = .default
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: winBack
            )
            components.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(
                UNNotificationRequest(identifier: Engagement.winBackId, content: content, trigger: trigger)
            )
        }
    }

    func nudgeUnfinishedSetup(locale: AppLocale) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            center.removePendingNotificationRequests(withIdentifiers: [Engagement.leaveSetupId])
            let content = UNMutableNotificationContent()
            content.title = L10n.string(.unfinishedPlanHeadline, locale: locale)
            content.body = L10n.string(.leaveHealthWarning, locale: locale)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            try? await center.add(
                UNNotificationRequest(identifier: Engagement.leaveSetupId, content: content, trigger: trigger)
            )
        }
    }

    private func isInQuietHours(_ date: Date, calendar: Calendar) -> Bool {
        guard ReminderPreferences.quietHoursEnabled else { return false }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let stamp = hour * 60 + minute
        return stamp >= 22 * 60 + 30 || stamp < 7 * 60
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await speakIfNeeded(notification)
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["logId"] as? String, let id = UUID(uuidString: raw) else { return }
        switch response.actionIdentifier {
        case ReminderAction.taken:
            await handleLogAction(id: id, status: .taken)
        case ReminderAction.skip:
            await handleLogAction(id: id, status: .skipped)
        default:
            break
        }
    }

    private func speakIfNeeded(_ notification: UNNotification) async {
        let body = notification.request.content.body
        await MainActor.run {
            guard let entitlements, entitlements.canUseVoiceReading else { return }
            guard ReminderPreferences.voiceRemindersEnabled else { return }
            guard let session, let voice else { return }
            voice.speak(body, locale: session.locale)
        }
    }
}
