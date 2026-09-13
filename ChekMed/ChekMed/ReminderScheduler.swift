import Foundation
import UserNotifications

enum ReminderAction {
    static let doseCategory = "CHECKMED_DOSE"
    static let confirmCategory = "CHECKMED_CONFIRM"
    static let taken = "CHECKMED_TAKEN"
    static let snooze = "CHECKMED_SNOOZE"
    static let remindLater = "CHECKMED_REMIND_LATER"
    static let didNotTake = "CHECKMED_DID_NOT_TAKE"
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
    private var rescheduleGeneration = 0
    private var lastRebuildAt: Date?
    private var pendingAction: (id: UUID, action: DoseLoopAction)?

    func configure() {
        UNUserNotificationCenter.current().setNotificationCategories(Self.categories(locale: .english))
        UNUserNotificationCenter.current().delegate = self
    }

    private static func categories(locale: AppLocale) -> Set<UNNotificationCategory> {
        let took = UNNotificationAction(
            identifier: ReminderAction.taken,
            title: L10n.string(.notificationActionTookIt, locale: locale),
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: ReminderAction.snooze,
            title: L10n.string(.notificationActionSnooze, locale: locale),
            options: []
        )
        let later = UNNotificationAction(
            identifier: ReminderAction.remindLater,
            title: L10n.string(.notificationActionRemindLater, locale: locale),
            options: []
        )
        let didNot = UNNotificationAction(
            identifier: ReminderAction.didNotTake,
            title: L10n.string(.missedDidNotTake, locale: locale),
            options: []
        )
        return [
            UNNotificationCategory(
                identifier: ReminderAction.doseCategory,
                actions: [took, snooze],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: ReminderAction.confirmCategory,
                actions: [took, later, didNot],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
        ]
    }

    func bind(store: CheckMedStore, session: SessionStore, entitlements: EntitlementStore, voice: PhilVoice) {
        self.store = store
        self.session = session
        self.entitlements = entitlements
        self.voice = voice
        flushPendingAction()
        reschedule(force: true)
        FreezeDiag.log("ReminderScheduler.bind done")
    }

    func reschedule(force: Bool = true) {
        guard session?.restorationComplete == true else { return }
        guard session?.hasCompletedOnboarding == true else { return }
        if !force, let lastRebuildAt, Date().timeIntervalSince(lastRebuildAt) < 20 {
            return
        }
        if !force, rescheduleTask != nil {
            return
        }
        LaunchLog.alarm("reschedule force=\(force)")
        if force {
            rescheduleTask?.cancel()
        }
        rescheduleGeneration += 1
        let generation = rescheduleGeneration
        rescheduleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: force ? 200_000_000 : 450_000_000)
            guard !Task.isCancelled, generation == rescheduleGeneration else { return }
            lastRebuildAt = Date()
            await rebuild()
            if generation == rescheduleGeneration {
                rescheduleTask = nil
            }
        }
    }

    func handleLogAction(id: UUID, action: DoseLoopAction) {
        if action == .confirmTaken || action == .didNotTake {
            MissedDoseAcknowledgement.acknowledge(id)
        }
        if let store {
            store.applyDoseAction(id: id, action: action)
            if action == .confirmTaken {
                scheduleStockDaysLeftIfNeeded(logId: id)
            }
        } else {
            CheckMedStore.persistDoseAction(id: id, action: action)
            pendingAction = (id, action)
        }
        reschedule()
    }

    func handleTakenSideEffects(logId: UUID) {
        scheduleStockDaysLeftIfNeeded(logId: logId)
        reschedule()
    }

    private func scheduleStockDaysLeftIfNeeded(logId: UUID) {
        guard let store, let session,
              let medicineId = store.medicineId(forLogId: logId),
              let draft = store.stockDaysLeftDraft(for: medicineId)
        else { return }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let remaining = remainingPhrase(for: medicineId)
            let content = UNMutableNotificationContent()
            content.title = session.t(.refillRunningLow)
            content.body = remaining ?? session.t(.notificationStockDaysBody, draft.medicine, draft.doseLabel)
            content.sound = .default
            content.userInfo = ["kind": draft.kind.rawValue]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            try? await center.add(
                UNNotificationRequest(
                    identifier: draft.notificationId,
                    content: CheckMedNotificationIcon.decorate(content),
                    trigger: trigger
                )
            )
        }
    }

    private func remainingPhrase(for medicineId: UUID) -> String? {
        guard let session, let summary = store?.medicineSummaries().first(where: { $0.id == medicineId }),
              summary.refillDataComplete,
              let remaining = MedicineUnits.remainingDisplayAmount(
                packageAmount: summary.packageAmount,
                packageUnit: summary.packageUnit,
                stockPercent: summary.stockPercent
              )
        else { return nil }
        let amount = remaining.amount == remaining.amount.rounded()
            ? String(Int(remaining.amount.rounded()))
            : String(format: "%.1f", remaining.amount)
        return session.t(.refillApproxRemaining, "\(amount) \(remaining.unit.rawValue)")
    }

    func applyIntent(logId: String, action: DoseLoopAction) {
        guard let id = UUID(uuidString: logId) else { return }
        handleLogAction(id: id, action: action)
    }

    private func flushPendingAction() {
        guard let pendingAction, let store else { return }
        store.applyDoseAction(id: pendingAction.id, action: pendingAction.action)
        self.pendingAction = nil
    }

    private static func alarmKitCopy(locale: AppLocale, theme: AlarmTheme) -> DoseAlarmKit.Copy {
        DoseAlarmKit.Copy(
            title: L10n.string(.alarmDoseTitle, locale: locale),
            snooze: L10n.string(.notificationActionSnooze, locale: locale),
            stop: L10n.string(.cancel, locale: locale),
            soundFileName: theme.soundFileName,
            red: 0.18,
            green: 0.72,
            blue: 0.35
        )
    }

    nonisolated private static func syncAlarmsOffMain(
        drafts: [ReminderDraft],
        copy: DoseAlarmKit.Copy
    ) async -> Set<UUID> {
        await Task.detached(priority: .utility) {
            await DoseAlarmKit.syncDoseAlarms(drafts: drafts, copy: copy)
        }.value
    }

    private func rebuild() async {
        guard let store, let session else { return }
        LaunchLog.alarm("rebuild start")
        FreezeDiag.context("ReminderScheduler.rebuild START", hasChanges: store.freezeDiagHasChanges())
        defer {
            FreezeDiag.context("ReminderScheduler.rebuild END", hasChanges: store.freezeDiagHasChanges())
        }

        guard session.hasConfirmedMedicationPlan, store.surfacesPlan else {
            await Self.syncAlarmsOffMain(drafts: [], copy: Self.alarmKitCopy(locale: session.locale, theme: .philChime))
            let center = UNUserNotificationCenter.current()
            let existing = await center.pendingNotificationRequests()
            let ours = existing.filter { $0.identifier.hasPrefix("checkmed.") }.map(\.identifier)
            if !ours.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ours)
            }
            return
        }

        let drafts = store.reminderDrafts().filter { draft in
            if draft.kind == .advance {
                return entitlements?.canUseAdvanceReminder == true && ReminderPreferences.advanceHourEnabled
            }
            return true
        }
            + store.stockRefillDrafts()
            + store.refillDrafts()
        let locale = session.locale
        let theme = entitlements?.canChooseAlarmTheme == true
            ? ReminderPreferences.alarmTheme
            : .philChime
        let alarmKitDoseIds = await Self.syncAlarmsOffMain(
            drafts: drafts,
            copy: Self.alarmKitCopy(locale: locale, theme: theme)
        )

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let existing = await center.pendingNotificationRequests()
        let ours = existing.filter { $0.identifier.hasPrefix("checkmed.") }.map(\.identifier)
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        let delivered = await center.deliveredNotifications()
        let deliveredOurs = delivered
            .map(\.request.identifier)
            .filter { $0.hasPrefix("checkmed.") }
        if !deliveredOurs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredOurs)
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        center.setNotificationCategories(Self.categories(locale: locale))
        let sound = UNNotificationSound(named: UNNotificationSoundName(theme.soundFileName))
        let calendar = session.foundationCalendar

        for draft in drafts.prefix(48) {
            if draft.kind == .confirm, isInQuietHours(draft.fireDate, calendar: calendar) {
                continue
            }
            guard draft.fireDate > Date().addingTimeInterval(8) else { continue }
            if draft.kind == .dose, alarmKitDoseIds.contains(draft.id) { continue }
            let content = UNMutableNotificationContent()
            content.sound = sound
            content.userInfo = ["logId": draft.id.uuidString, "kind": draft.kind.rawValue]
            content.interruptionLevel = .active
            switch draft.kind {
            case .dose:
                content.categoryIdentifier = ReminderAction.doseCategory
                content.title = session.t(.alarmDoseTitle)
                content.body = session.t(.alarmDoseBody, draft.medicine, draft.doseLabel)
            case .confirm:
                content.categoryIdentifier = ReminderAction.confirmCategory
                content.title = session.t(.notificationConfirmTitle, draft.medicine)
                content.body = session.t(.missedDoseDisclaimer)
            case .missed:
                content.categoryIdentifier = ReminderAction.confirmCategory
                content.title = session.t(.missedYouMissedOne)
                content.body = session.t(.missedDoseDisclaimer)
            case .advance:
                guard entitlements?.canUseAdvanceReminder == true,
                      ReminderPreferences.advanceHourEnabled else { continue }
                content.title = session.t(.notificationAdvanceTitle)
                content.body = session.t(.notificationAdvanceBody, draft.medicine, draft.time)
            case .refill:
                content.title = session.t(.notificationRefillTitle)
                content.body = session.t(.notificationRefillBody, draft.medicine)
            case .stockRefill:
                content.title = session.t(.refillRunningLow)
                content.body = session.t(.notificationStockRefillBody, draft.medicine)
            case .stockDaysLeft:
                content.title = session.t(.refillRunningLow)
                content.body = session.t(.notificationStockDaysBody, draft.medicine, draft.doseLabel)
            }
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: draft.fireDate
            )
            components.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: draft.notificationId,
                content: CheckMedNotificationIcon.decorate(content),
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
                UNNotificationRequest(
                    identifier: Engagement.winBackId,
                    content: CheckMedNotificationIcon.decorate(content),
                    trigger: trigger
                )
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
                UNNotificationRequest(
                    identifier: Engagement.leaveSetupId,
                    content: CheckMedNotificationIcon.decorate(content),
                    trigger: trigger
                )
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
            await handleLogAction(id: id, action: .confirmTaken)
        case ReminderAction.snooze, ReminderAction.remindLater:
            await handleLogAction(id: id, action: .snooze)
        case ReminderAction.didNotTake:
            await handleLogAction(id: id, action: .didNotTake)
        case UNNotificationDismissActionIdentifier:
            await handleLogAction(id: id, action: .stop)
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
