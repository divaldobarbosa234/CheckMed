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
    @ObservationIgnored
    private weak var path: TodayPathStore?

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

    func bind(store: CheckMedStore, session: SessionStore, entitlements: EntitlementStore, voice: PhilVoice, path: TodayPathStore) {
        self.store = store
        self.session = session
        self.entitlements = entitlements
        self.voice = voice
        self.path = path
        flushPendingAction()
        reschedule(force: true)
        FreezeDiag.log("ReminderScheduler.bind done")
    }

    func reschedule(force: Bool = true) {
        #if DEBUG
        Self.trace4h(
            "RESCHEDULE start force=\(force) lastRebuildAt=\(lastRebuildAt.map { "\($0)" } ?? "nil") "
            + "taskRunning=\(rescheduleTask != nil)"
        )
        #endif
        guard session?.restorationComplete == true else {
            #if DEBUG
            Self.trace4h("RESCHEDULE skipped restorationComplete=false")
            #endif
            return
        }
        guard session?.hasCompletedOnboarding == true else {
            #if DEBUG
            Self.trace4h("RESCHEDULE skipped hasCompletedOnboarding=false")
            #endif
            return
        }
        if !force, let lastRebuildAt, Date().timeIntervalSince(lastRebuildAt) < 20 {
            #if DEBUG
            Self.trace4h("RESCHEDULE skipped 20s throttle force=false")
            #endif
            Task { await purgeStaleDeliveredNotifications() }
            return
        }
        if !force, rescheduleTask != nil {
            #if DEBUG
            Self.trace4h("RESCHEDULE skipped task already running force=false")
            #endif
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
            guard !Task.isCancelled, generation == rescheduleGeneration else {
                #if DEBUG
                Self.trace4h("RESCHEDULE task cancelled before rebuild generation=\(generation)")
                #endif
                return
            }
            lastRebuildAt = Date()
            #if DEBUG
            Self.trace4h("REBUILD about to start force=\(force) generation=\(generation)")
            #endif
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
        let wasMissedLike = path?.preConfirmWasMissedLike(id: id.uuidString) ?? false
        let revisionBefore = store?.revision
        if let store {
            store.applyDoseAction(id: id, action: action)
            if action == .confirmTaken {
                scheduleStockDaysLeftIfNeeded(logId: id)
            }
        } else {
            CheckMedStore.persistDoseAction(id: id, action: action)
            pendingAction = (id, action)
        }
        #if DEBUG
        Self.trace4h("RESCHEDULE handleLogAction → reschedule(force:true default) action=\(String(describing: action)) id=\(id)")
        #endif
        reschedule()
        if action == .confirmTaken, let store, let revisionBefore, store.revision != revisionBefore {
            if let name = store.medicineName(forLogId: id) {
                if let path {
                    path.queueFeelingAfterCompletion(logId: id, medicine: name)
                } else {
                    FeelingCheckInQueue.enqueue(logId: id, medicine: name)
                }
            }
            path?.offerImmediatePhil(id: id.uuidString, wasMissedLike: wasMissedLike)
        }
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
        #if DEBUG
        Self.trace4h("RESCHEDULE applyIntent action=\(String(describing: action)) logId=\(logId)")
        #endif
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

    /// AlarmKit must run on the main actor/thread (`AlarmManager` / presentation APIs).
    /// Call from `rebuild` (already `@MainActor`) via `await` so the actor can suspend;
    /// never `Task.detached` — that caused `Call must be made on main thread` after
    /// notification-tap foreground rebuilds when the 2.8s timeout orphaned off-main work.
    private static func syncAlarmsOnMain(
        drafts: [ReminderDraft],
        asOf now: Date = Date(),
        copy: DoseAlarmKit.Copy
    ) async -> Set<UUID> {
        await DoseAlarmKit.syncDoseAlarms(drafts: drafts, asOf: now, copy: copy)
    }

    private func rebuild() async {
        guard let store, let session else { return }
        LaunchLog.alarm("rebuild start")
        FreezeDiag.context("ReminderScheduler.rebuild START", hasChanges: store.freezeDiagHasChanges())
        defer {
            FreezeDiag.context("ReminderScheduler.rebuild END", hasChanges: store.freezeDiagHasChanges())
        }
        #if DEBUG
        Self.unDiag("REBUILD START")
        #endif

        guard session.hasConfirmedMedicationPlan, store.surfacesPlan else {
            await Self.syncAlarmsOnMain(drafts: [], copy: Self.alarmKitCopy(locale: session.locale, theme: .philChime))
            let center = UNUserNotificationCenter.current()
            let existing = await center.pendingNotificationRequests()
            let ours = existing.filter { $0.identifier.hasPrefix("checkmed.") }.map(\.identifier)
            if !ours.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ours)
            }
            await purgeStaleDeliveredNotifications()
            #if DEBUG
            Self.unDiag("REBUILD END skipped (no confirmed plan / surfacesPlan=false) drafts=0 surviving=0 attempted=0 added=0")
            await Self.dumpCheckmedNotifications(center, label: "after skip-wipe")
            #endif
            return
        }

        let schedulingNow = Date()
        let drafts = store.reminderDrafts(now: schedulingNow).filter { draft in
            if draft.kind == .advance {
                return entitlements?.canUseAdvanceReminder == true && ReminderPreferences.advanceHourEnabled
            }
            return true
        }
            + store.stockRefillDrafts(now: schedulingNow)
            + store.refillDrafts(now: schedulingNow)
        let surviving = Self.draftsWithinNotificationCap(drafts)
        #if DEBUG
        Self.unDiag(
            "drafts=\(drafts.count) surviving=\(surviving.count) "
            + Self.kindCounts(drafts, label: "drafts") + " "
            + Self.kindCounts(surviving, label: "surviving")
        )
        let traced = store.debugMostRecentPendingConfirmation(now: schedulingNow)
        if let traced {
            Self.emit4hDoseAndDrafts(
                traced: traced,
                schedulingNow: schedulingNow,
                drafts: drafts,
                surviving: surviving,
                calendar: session.foundationCalendar
            )
        } else {
            Self.trace4h("DOSELOG none pendingConfirmation")
        }
        #endif
        let locale = session.locale
        let theme = entitlements?.canChooseAlarmTheme == true
            ? ReminderPreferences.alarmTheme
            : .philChime
        let alarmKitDoseIds = await Self.syncAlarmsOnMain(
            drafts: drafts,
            asOf: schedulingNow,
            copy: Self.alarmKitCopy(locale: locale, theme: theme)
        )
        #if DEBUG
        Self.trace4h("ALARMKIT nudge5Suppressed=false")
        Self.trace4h("ALARMKIT nudge30Suppressed=false")
        if let tid = store.debugMostRecentPendingConfirmation(now: schedulingNow)?.id {
            Self.trace4h("ALARMKIT doseSuppressed=\(alarmKitDoseIds.contains(tid)) id=\(tid)")
        }
        #endif

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        #if DEBUG
        Self.unDiag(Self.describeSettings(settings))
        Self.trace4h("UN-AUTH \(Self.describeSettings(settings))")
        #endif
        let existing = await center.pendingNotificationRequests()
        let ours = existing.filter { $0.identifier.hasPrefix("checkmed.") }.map(\.identifier)
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            #if DEBUG
            Self.unDiag(
                "REBUILD END blocked by UN auth drafts=\(drafts.count) surviving=\(surviving.count) attempted=0 added=0"
            )
            Self.trace4h("UN-ADD blocked by authorization")
            await Self.dumpCheckmedNotifications(center, label: "after auth-block wipe")
            await Self.emit4hQueueAndRoot(
                store: store,
                schedulingNow: schedulingNow,
                drafts: drafts,
                surviving: surviving,
                center: center,
                addedNudge5: false,
                addedNudge30: false
            )
            #endif
            await purgeStaleDeliveredNotifications()
            return
        }
        center.setNotificationCategories(Self.categories(locale: locale))
        let sound = UNNotificationSound(named: UNNotificationSoundName(theme.soundFileName))
        let calendar = session.foundationCalendar

        var attempted = 0
        var added = 0
        #if DEBUG
        var addedNudge5 = false
        var addedNudge30 = false
        let traceId = store.debugMostRecentPendingConfirmation(now: schedulingNow)?.id
        #endif
        for draft in surviving {
            if draft.kind == .confirm || draft.kind == .missed, isInQuietHours(draft.fireDate, calendar: calendar) {
                continue
            }
            guard draft.fireDate > schedulingNow.addingTimeInterval(8) else { continue }
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
            case .nudge5:
                content.categoryIdentifier = ReminderAction.doseCategory
                content.title = session.t(.notificationNudge5Title, draft.medicine)
                content.body = session.t(.notificationNudge5Body, draft.medicine, draft.doseLabel)
            case .nudge30:
                content.categoryIdentifier = ReminderAction.doseCategory
                content.title = session.t(.notificationNudge30Title, draft.medicine)
                content.body = session.t(.notificationNudge30Body, draft.medicine, draft.doseLabel)
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
            attempted += 1
            #if DEBUG
            Self.unDiag(
                "ADD ATTEMPT id=\(request.identifier) kind=\(draft.kind.rawValue) medicine=\(draft.medicine) "
                + "fireDate=\(draft.fireDate) comps=y=\(components.year ?? -1) m=\(components.month ?? -1) "
                + "d=\(components.day ?? -1) h=\(components.hour ?? -1) min=\(components.minute ?? -1) "
                + "s=\(components.second ?? -1) repeats=\(trigger.repeats) category=\(content.categoryIdentifier)"
            )
            if draft.id == traceId, draft.kind == .nudge5 || draft.kind == .nudge30 {
                Self.trace4h(
                    "UN-ADD attempt kind=\(draft.kind.rawValue) id=\(request.identifier) title=\(content.title) "
                    + "body=\(content.body) fire=\(draft.fireDate) "
                    + "comps=y=\(components.year ?? -1) m=\(components.month ?? -1) d=\(components.day ?? -1) "
                    + "h=\(components.hour ?? -1) min=\(components.minute ?? -1) s=\(components.second ?? -1)"
                )
            }
            #endif
            do {
                try await center.add(request)
                added += 1
                #if DEBUG
                Self.unDiag("UN ADD SUCCESS \(request.identifier)")
                if draft.id == traceId, draft.kind == .nudge5 {
                    addedNudge5 = true
                    Self.trace4h(
                        "UN-ADD nudge5 SUCCESS id=\(request.identifier) title=\(content.title) body=\(content.body) "
                        + "fire=\(draft.fireDate) comps=h=\(components.hour ?? -1) min=\(components.minute ?? -1)"
                    )
                }
                if draft.id == traceId, draft.kind == .nudge30 {
                    addedNudge30 = true
                    Self.trace4h(
                        "UN-ADD nudge30 SUCCESS id=\(request.identifier) title=\(content.title) body=\(content.body) "
                        + "fire=\(draft.fireDate) comps=h=\(components.hour ?? -1) min=\(components.minute ?? -1)"
                    )
                }
                #endif
            } catch {
                #if DEBUG
                Self.unDiag("UN ADD FAILED \(request.identifier) \(error)")
                if draft.id == traceId, draft.kind == .nudge5 {
                    Self.trace4h("UN-ADD nudge5 FAILED error=\(error) id=\(request.identifier)")
                }
                if draft.id == traceId, draft.kind == .nudge30 {
                    Self.trace4h("UN-ADD nudge30 FAILED error=\(error) id=\(request.identifier)")
                }
                #endif
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
        await purgeStaleDeliveredNotifications()
        #if DEBUG
        Self.unDiag(
            "REBUILD END drafts=\(drafts.count) surviving=\(surviving.count) "
            + "auth=\(Self.authName(settings.authorizationStatus)) attempted=\(attempted) added=\(added) "
            + "alarmKitDoseIds=\(alarmKitDoseIds.count)"
        )
        await Self.dumpCheckmedNotifications(center, label: "after UN loop")
        await Self.emit4hQueueAndRoot(
            store: store,
            schedulingNow: schedulingNow,
            drafts: drafts,
            surviving: surviving,
            center: center,
            addedNudge5: addedNudge5,
            addedNudge30: addedNudge30
        )
        #endif
    }

    #if DEBUG
    private static func trace4h(_ message: String) {
        print("[5B-4H-TRACE] \(ISO8601DateFormatter().string(from: Date())) \(message)")
    }

    private static func emit4hDoseAndDrafts(
        traced: (
            id: UUID,
            medicine: String,
            scheduledAt: Date,
            loggedAt: Date?,
            status: String,
            treatmentId: UUID?,
            medicineId: UUID?
        ),
        schedulingNow: Date,
        drafts: [ReminderDraft],
        surviving: [ReminderDraft],
        calendar: Calendar
    ) {
        let iso = { (d: Date) in ScanPipeline.iso(d, calendar: calendar) }
        trace4h(
            "DOSELOG id=\(traced.id.uuidString) medicine=\(traced.medicine) "
            + "scheduledAt=\(iso(traced.scheduledAt)) loggedAt=\(traced.loggedAt.map(iso) ?? "nil") "
            + "status=\(traced.status) treatmentID=\(traced.treatmentId?.uuidString ?? "nil") "
            + "medicineID=\(traced.medicineId?.uuidString ?? "nil")"
        )
        let cutoff = schedulingNow.addingTimeInterval(8)
        let expected: [(ReminderDraft.Kind, Date)] = [
            (.nudge5, traced.scheduledAt.addingTimeInterval(5 * 60)),
            (.nudge30, traced.scheduledAt.addingTimeInterval(30 * 60)),
            (.confirm, (traced.loggedAt ?? schedulingNow).addingTimeInterval(ReminderPreferences.confirmationGraceInterval)),
        ]
        for (kind, fire) in expected {
            trace4h(
                "EXPECTED kind=\(kind.rawValue) fire=\(iso(fire)) secondsFromNow=\(Int(fire.timeIntervalSince(schedulingNow))) "
                + "eligible8s=\(fire > cutoff)"
            )
        }
        let mine = drafts.filter { $0.id == traced.id }
        if mine.isEmpty {
            trace4h("DRAFT none for this UUID")
        }
        for draft in mine {
            trace4h(
                "DRAFT kind=\(draft.kind.rawValue) id=\(draft.notificationId) fire=\(iso(draft.fireDate)) "
                + "secondsFromNow=\(Int(draft.fireDate.timeIntervalSince(schedulingNow))) eligible=\(draft.fireDate > cutoff)"
            )
        }
        let kept5 = surviving.contains { $0.id == traced.id && $0.kind == .nudge5 }
        let kept30 = surviving.contains { $0.id == traced.id && $0.kind == .nudge30 }
        let pos5 = surviving.firstIndex { $0.id == traced.id && $0.kind == .nudge5 }
        let pos30 = surviving.firstIndex { $0.id == traced.id && $0.kind == .nudge30 }
        trace4h(
            "CAP before=\(drafts.count) after=\(surviving.count) nudge5=\(kept5 ? "KEPT" : "DROPPED") "
            + "nudge30=\(kept30 ? "KEPT" : "DROPPED") pos5=\(pos5.map(String.init) ?? "nil") "
            + "pos30=\(pos30.map(String.init) ?? "nil")"
        )
    }

    private static func emit4hQueueAndRoot(
        store: CheckMedStore,
        schedulingNow: Date,
        drafts: [ReminderDraft],
        surviving: [ReminderDraft],
        center: UNUserNotificationCenter,
        addedNudge5: Bool,
        addedNudge30: Bool
    ) async {
        guard let traced = store.debugMostRecentPendingConfirmation(now: schedulingNow) else {
            trace4h("ROOT_STAGE=A (no pendingConfirmation log)")
            return
        }
        let id5 = "checkmed.nudge5.\(traced.id.uuidString)"
        let id30 = "checkmed.nudge30.\(traced.id.uuidString)"
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let p5 = pending.first { $0.identifier == id5 }
        let p30 = pending.first { $0.identifier == id30 }
        trace4h("QUEUE nudge5 \(p5 == nil ? "ABSENT" : "PRESENT") id=\(id5)")
        if let p5, let cal = p5.trigger as? UNCalendarNotificationTrigger {
            let c = cal.dateComponents
            trace4h("QUEUE nudge5 trigger h=\(c.hour ?? -1) min=\(c.minute ?? -1) d=\(c.day ?? -1) m=\(c.month ?? -1)")
        }
        trace4h("QUEUE nudge30 \(p30 == nil ? "ABSENT" : "PRESENT") id=\(id30)")
        if let p30, let cal = p30.trigger as? UNCalendarNotificationTrigger {
            let c = cal.dateComponents
            trace4h("QUEUE nudge30 trigger h=\(c.hour ?? -1) min=\(c.minute ?? -1) d=\(c.day ?? -1) m=\(c.month ?? -1)")
        }
        let d5 = delivered.contains { $0.request.identifier == id5 }
        let d30 = delivered.contains { $0.request.identifier == id30 }
        trace4h("DELIVERED nudge5 \(d5 ? "PRESENT" : "ABSENT")")
        trace4h("DELIVERED nudge30 \(d30 ? "PRESENT" : "ABSENT")")
        let gen5 = drafts.contains { $0.id == traced.id && $0.kind == .nudge5 }
        let gen30 = drafts.contains { $0.id == traced.id && $0.kind == .nudge30 }
        let kept5 = surviving.contains { $0.id == traced.id && $0.kind == .nudge5 }
        let kept30 = surviving.contains { $0.id == traced.id && $0.kind == .nudge30 }
        let stage: String
        if !gen5 && !gen30 {
            stage = "A"
        } else if (gen5 && !kept5) || (gen30 && !kept30) {
            stage = "B"
        } else if p5 != nil || p30 != nil {
            stage = "D"
        } else {
            stage = "C"
        }
        trace4h(
            "ROOT_STAGE=\(stage) generated5=\(gen5) generated30=\(gen30) kept5=\(kept5) kept30=\(kept30) "
            + "added5=\(addedNudge5) added30=\(addedNudge30)"
        )
    }

    private static func unDiag(_ message: String) {
        print("[UN-DIAG] \(ISO8601DateFormatter().string(from: Date())) \(message)")
    }

    private static func kindCounts(_ drafts: [ReminderDraft], label: String) -> String {
        var counts: [String: Int] = [:]
        for draft in drafts {
            counts[draft.kind.rawValue, default: 0] += 1
        }
        let ordered = ["dose", "nudge5", "nudge30", "missed", "confirm", "advance", "refill", "stockRefill", "stockDaysLeft"]
            .compactMap { kind -> String? in
                guard let n = counts[kind] else { return nil }
                return "\(kind)=\(n)"
            }
            .joined(separator: " ")
        return "\(label){\(ordered)}"
    }

    private static func authName(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    private static func settingName(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: "notSupported"
        case .disabled: "disabled"
        case .enabled: "enabled"
        @unknown default: "unknown(\(setting.rawValue))"
        }
    }

    private static func describeSettings(_ settings: UNNotificationSettings) -> String {
        var line =
            "UN auth=\(authName(settings.authorizationStatus)) "
            + "alert=\(settingName(settings.alertSetting)) "
            + "sound=\(settingName(settings.soundSetting)) "
            + "notificationCenter=\(settingName(settings.notificationCenterSetting)) "
            + "lockScreen=\(settingName(settings.lockScreenSetting))"
        if #available(iOS 12.0, *) {
            line += " criticalAlert=\(settingName(settings.criticalAlertSetting))"
        }
        return line
    }

    private static func dumpCheckmedNotifications(_ center: UNUserNotificationCenter, label: String) async {
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("checkmed.") }
        unDiag("PENDING \(label) count=\(pending.count)")
        for request in pending.sorted(by: { $0.identifier < $1.identifier }) {
            let trigger: String
            if let cal = request.trigger as? UNCalendarNotificationTrigger {
                let c = cal.dateComponents
                trigger =
                    "calendar y=\(c.year ?? -1) m=\(c.month ?? -1) d=\(c.day ?? -1) "
                    + "h=\(c.hour ?? -1) min=\(c.minute ?? -1) s=\(c.second ?? -1) repeats=\(cal.repeats)"
            } else if let interval = request.trigger as? UNTimeIntervalNotificationTrigger {
                trigger = "interval=\(interval.timeInterval) repeats=\(interval.repeats)"
            } else {
                trigger = String(describing: request.trigger)
            }
            unDiag(
                "PENDING id=\(request.identifier) \(trigger) title=\(request.content.title) "
                + "body=\(request.content.body) category=\(request.content.categoryIdentifier)"
            )
        }
        let delivered = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix("checkmed.") }
        unDiag("DELIVERED \(label) count=\(delivered.count)")
        for item in delivered.sorted(by: { $0.request.identifier < $1.request.identifier }) {
            unDiag(
                "DELIVERED id=\(item.request.identifier) date=\(item.date) title=\(item.request.content.title) "
                + "body=\(item.request.content.body)"
            )
        }
    }
    #endif

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

    /// Global 48: `.confirm` keeps matching `.nudge5`/`.nudge30` (pendingConfirmation); `.dose` keeps matching nudges (pending).
    /// Then leftover `.dose`, `.advance`, `.missed`. Each draft is emitted at most once. Never exceeds `limit`.
    private static func draftsWithinNotificationCap(_ drafts: [ReminderDraft], limit: Int = 48) -> [ReminderDraft] {
        func slice(_ kind: ReminderDraft.Kind) -> [ReminderDraft] {
            drafts.filter { $0.kind == kind }
        }
        func keyed(_ kind: ReminderDraft.Kind) -> [UUID: ReminderDraft] {
            var map: [UUID: ReminderDraft] = [:]
            for draft in slice(kind) where map[draft.id] == nil {
                map[draft.id] = draft
            }
            return map
        }
        func byFireThenId(_ a: ReminderDraft, _ b: ReminderDraft) -> Bool {
            if a.fireDate != b.fireDate { return a.fireDate < b.fireDate }
            return a.id.uuidString < b.id.uuidString
        }
        func nudgeKey(_ draft: ReminderDraft) -> String {
            "\(draft.kind.rawValue).\(draft.id.uuidString)"
        }
        let refillLike = drafts.filter {
            switch $0.kind {
            case .refill, .stockRefill, .stockDaysLeft: true
            default: false
            }
        }.sorted(by: byFireThenId)
        let doses = slice(.dose).sorted(by: byFireThenId)
        let nudge5ByLog = keyed(.nudge5)
        let nudge30ByLog = keyed(.nudge30)

        var ordered: [ReminderDraft] = []
        var consumedNudgeKeys = Set<String>()

        func unusedNudges(for id: UUID) -> [ReminderDraft] {
            [nudge5ByLog[id], nudge30ByLog[id]].compactMap { extra in
                guard let extra, !consumedNudgeKeys.contains(nudgeKey(extra)) else { return nil }
                return extra
            }
        }

        func appendNudges(_ extras: [ReminderDraft]) {
            for extra in extras {
                consumedNudgeKeys.insert(nudgeKey(extra))
                ordered.append(extra)
            }
        }

        for confirm in slice(.confirm).sorted(by: byFireThenId) {
            let extras = unusedNudges(for: confirm.id)
            if ordered.count + 1 + extras.count <= limit {
                ordered.append(confirm)
                appendNudges(extras)
                #if DEBUG
                print(
                    "[5B-4J-CAP] pendingConfirmation bundle id=\(confirm.id.uuidString) "
                    + "confirm=KEPT nudge5=\(extras.contains { $0.kind == .nudge5 } ? "KEPT" : (nudge5ByLog[confirm.id] == nil ? "NONE" : "DROPPED")) "
                    + "nudge30=\(extras.contains { $0.kind == .nudge30 } ? "KEPT" : (nudge30ByLog[confirm.id] == nil ? "NONE" : "DROPPED"))"
                )
                #endif
            } else if ordered.count < limit {
                ordered.append(confirm)
                #if DEBUG
                print(
                    "[5B-4J-CAP] pendingConfirmation bundle id=\(confirm.id.uuidString) "
                    + "confirm=KEPT nudge5=\(nudge5ByLog[confirm.id] == nil ? "NONE" : "DROPPED") "
                    + "nudge30=\(nudge30ByLog[confirm.id] == nil ? "NONE" : "DROPPED")"
                )
                #endif
            } else {
                break
            }
        }
        for refill in refillLike {
            guard ordered.count < limit else { break }
            ordered.append(refill)
        }

        var bundledDoseIds = Set<UUID>()
        for dose in doses {
            let extras = unusedNudges(for: dose.id)
            let needed = 1 + extras.count
            guard ordered.count + needed <= limit else { continue }
            ordered.append(dose)
            appendNudges(extras)
            bundledDoseIds.insert(dose.id)
        }
        for dose in doses where !bundledDoseIds.contains(dose.id) {
            guard ordered.count < limit else { break }
            ordered.append(dose)
            bundledDoseIds.insert(dose.id)
        }
        for advance in slice(.advance).sorted(by: byFireThenId) {
            guard ordered.count < limit else { break }
            ordered.append(advance)
        }
        for missed in slice(.missed).sorted(by: byFireThenId) {
            guard ordered.count < limit else { break }
            ordered.append(missed)
        }
        #if DEBUG
        print("[5B-4J-CAP] finalCount=\(ordered.count) limit=\(limit) ok=\(ordered.count <= limit)")
        #endif
        return Array(ordered.prefix(limit))
    }

    private func isInQuietHours(_ date: Date, calendar: Calendar) -> Bool {
        guard ReminderPreferences.quietHoursEnabled else { return false }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let stamp = hour * 60 + minute
        return stamp >= 22 * 60 + 30 || stamp < 7 * 60
    }

    /// UN may invoke these off-main. The `@MainActor` type isolation must cover the
    /// full callback (including a default banner tap that is otherwise a no-op) so
    /// SwiftUI/UIKit scene CA transactions do not continue on the UN queue.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        #if DEBUG
        print("[UN-DELEGATE] willPresent entered")
        print("[UN-DELEGATE] willPresent MainActor")
        #endif
        await speakIfNeeded(notification)
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        #if DEBUG
        print("[UN-DELEGATE] didReceive entered")
        print("[UN-DELEGATE] didReceive MainActor")
        #endif
        let info = response.notification.request.content.userInfo
        defer {
            #if DEBUG
            print("[UN-DELEGATE] didReceive completed")
            #endif
        }
        guard let raw = info["logId"] as? String, let id = UUID(uuidString: raw) else { return }
        switch response.actionIdentifier {
        case ReminderAction.taken:
            handleLogAction(id: id, action: .confirmTaken)
        case ReminderAction.snooze, ReminderAction.remindLater:
            handleLogAction(id: id, action: .snooze)
        case ReminderAction.didNotTake:
            handleLogAction(id: id, action: .didNotTake)
        case UNNotificationDismissActionIdentifier:
            handleLogAction(id: id, action: .stop)
        case UNNotificationDefaultActionIdentifier:
            routeDefaultNotificationTap(id: id, kind: info["kind"] as? String)
        default:
            break
        }
    }

    private func routeDefaultNotificationTap(id: UUID, kind rawKind: String?) {
        guard let rawKind, let kind = ReminderDraft.Kind(rawValue: rawKind), kind.routesDefaultTapToHomeDose else {
            return
        }
        path?.queueNotificationFocus(logId: id)
        if let session, session.selectedMainTab != .home {
            session.selectedMainTab = .home
        }
    }

    /// Removes delivered `checkmed.*` banners whose treatment/medicine/log is gone or inactive.
    /// Does not strip live open-dose banners that already fired.
    private func purgeStaleDeliveredNotifications() async {
        guard let store else { return }
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let stale = delivered.map(\.request.identifier).filter { identifier in
            identifier.hasPrefix("checkmed.")
                && !store.shouldRetainDeliveredCheckmedNotification(identifier: identifier)
        }
        guard !stale.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: stale)
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
