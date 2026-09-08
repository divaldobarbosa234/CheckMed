import Foundation
import SwiftData

struct AdherenceSnapshot: Equatable, Sendable {
    var streakDays: Int
    var takenCount: Int
    var plannedCount: Int
    var percent: Int?
    var treatmentCount: Int
    var todayTaken: Int
    var todayTotal: Int
    var hasHistory: Bool
    var weekTaken: Int
    var weekPlanned: Int
    var weekPercent: Int?
}

struct ReminderDraft: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case dose
        case missed
        case advance
        case refill
    }

    var id: UUID
    var fireDate: Date
    var medicine: String
    var doseLabel: String
    var time: String
    var kind: Kind

    var notificationId: String {
        switch kind {
        case .dose: "checkmed.dose.\(id.uuidString)"
        case .missed: "checkmed.missed.\(id.uuidString)"
        case .advance: "checkmed.advance.\(id.uuidString)"
        case .refill: "checkmed.refill.\(id.uuidString)"
        }
    }
}

struct JourneyReport: Equatable, Sendable {
    var treatmentId: UUID
    var title: String
    var startDate: Date
    var endDate: Date?
    var takenCount: Int
    var skippedCount: Int
    var plannedCount: Int
    var percent: Int
    var medicines: [String]
    var feelingGreat: Int
    var feelingOkay: Int
    var feelingLow: Int
    var feelingSideEffect: Int
}

/// Local SwiftData is the UI source of truth for treatments, medicines, schedules, and logs.
@Observable
@MainActor
final class CheckMedStore {
    private let container: ModelContainer
    private let context: ModelContext
    private var ownerId: UUID?
    private var stampProfileId: UUID?
    private var scopeProfileId: UUID?
    private var includeUnscoped = true
    private var calendar = Calendar(identifier: .gregorian)
    private var cachedTreatments: [TreatmentRecord]?
    private var cachedMedicines: [MedicineRecord]?
    private var cachedSchedules: [DoseScheduleRecord]?
    private var cachedLogs: [DoseLogRecord]?
    private var logsEnsuredDay: Date?
    private var logsEnsuredSignature: Int?
    private(set) var revision = 0

    @ObservationIgnored
    var onRecordsChanged: (() -> Void)?
    @ObservationIgnored
    var onNeedsSync: (() async -> Void)?

    init() {
        let schema = Schema([
            TreatmentRecord.self,
            MedicineRecord.self,
            DoseScheduleRecord.self,
            DoseLogRecord.self,
            FeelingRecord.self,
            CommunityCommentRecord.self,
        ])
        let disk = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let live = try? ModelContainer(for: schema, configurations: [disk]) {
            container = live
        } else {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memory])
        }
        context = ModelContext(container)
        context.autosaveEnabled = true
        calendar.timeZone = .current
    }

    func bindIdentity(ownerId: UUID?, profileId: UUID?) {
        let identityChanged = ownerId != self.ownerId
        self.ownerId = ownerId
        if identityChanged {
            stampProfileId = profileId
            scopeProfileId = profileId
            includeUnscoped = true
            invalidateCache()
            logsEnsuredDay = nil
        } else if stampProfileId == nil {
            stampProfileId = profileId
            if scopeProfileId == nil { scopeProfileId = profileId }
        } else if let profileId {
            stampProfileId = profileId
        }
        stampIdentity()
        ensureUpcomingLogs()
        notify()
    }

    func setActiveScope(profileId: UUID?, includeUnscoped: Bool) {
        let changed = profileId != scopeProfileId || includeUnscoped != self.includeUnscoped
        scopeProfileId = profileId
        self.includeUnscoped = includeUnscoped
        guard changed else { return }
        logsEnsuredDay = nil
        invalidateCache()
        ensureUpcomingLogs()
        notify()
    }

    func setTimeZone(_ timeZone: TimeZone) {
        guard calendar.timeZone.identifier != timeZone.identifier else { return }
        var next = Calendar(identifier: .gregorian)
        next.timeZone = timeZone
        calendar = next
        logsEnsuredDay = nil
        ensureUpcomingLogs()
        notify()
    }

    /// Treatments already owned by the signed-in user. Ignores unowned leftover rows.
    var hasExistingTreatments: Bool {
        guard let ownerId else { return false }
        return allTreatments().contains {
            $0.deletedAt == nil && $0.ownerId == ownerId
        }
    }

    var activeTreatmentCount: Int { activeTreatments().count }

    func daysUntilNextRevision(calendar: Calendar) -> Int? {
        _ = revision
        let today = calendar.startOfDay(for: Date())
        let ends = activeTreatments().compactMap(\.endDate).map { calendar.startOfDay(for: $0) }
        guard let soonest = ends.min() else { return nil }
        return calendar.dateComponents([.day], from: today, to: soonest).day
    }

    struct MedicineSummary: Identifiable {
        var id: UUID
        var treatmentId: UUID
        var name: String
        var doseLabel: String
        var frequency: String
        var duration: String
        var timesPerDay: Int
        var treatmentTitle: String
        var treatmentStatus: String
    }

    func medicineSummaries() -> [MedicineSummary] {
        _ = revision
        let treatmentsById = Dictionary(uniqueKeysWithValues: activeTreatments().map { ($0.id, $0) })
        return medicines().compactMap { medicine in
            guard let treatment = treatmentsById[medicine.treatmentId] else { return nil }
            return MedicineSummary(
                id: medicine.id,
                treatmentId: treatment.id,
                name: medicine.name,
                doseLabel: medicine.doseLabel,
                frequency: medicine.frequency,
                duration: medicine.duration,
                timesPerDay: max(1, schedules(for: medicine.id).count),
                treatmentTitle: treatment.title,
                treatmentStatus: treatment.status
            )
        }
    }

    /// First-treatment onboarding: create or replace the single active plan.
    func seedFromDraft(_ draft: OnboardingPrescriptionDraft, ownerId: UUID?, profileId: UUID?) {
        seedFromDrafts([draft], ownerId: ownerId, profileId: profileId)
    }

    func seedFromDrafts(_ drafts: [OnboardingPrescriptionDraft], ownerId: UUID?, profileId: UUID?) {
        for (index, draft) in drafts.enumerated() where draft.hasMedicineName {
            saveDraft(draft, ownerId: ownerId, profileId: profileId, replacingFirst: index == 0)
        }
    }

    /// Later adds from Home: always insert a new treatment.
    func addFromDraft(_ draft: OnboardingPrescriptionDraft, ownerId: UUID?, profileId: UUID?) {
        addFromDrafts([draft], ownerId: ownerId, profileId: profileId)
    }

    func addFromDrafts(_ drafts: [OnboardingPrescriptionDraft], ownerId: UUID?, profileId: UUID?) {
        for draft in drafts where draft.hasMedicineName {
            saveDraft(draft, ownerId: ownerId, profileId: profileId, replacingFirst: false)
        }
    }

    private func saveDraft(
        _ draft: OnboardingPrescriptionDraft,
        ownerId: UUID?,
        profileId: UUID?,
        replacingFirst: Bool
    ) {
        self.ownerId = ownerId ?? self.ownerId
        if let profileId {
            stampProfileId = stampProfileId ?? profileId
        }
        var draft = draft
        draft.syncDoseTimes()
        let now = Date()
        let medicineName = draft.medicine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !medicineName.isEmpty else { return }

        let treatment: TreatmentRecord
        if replacingFirst, let existing = activeTreatments().first {
            existing.title = medicineName
            existing.updatedAt = now
            existing.deletedAt = nil
            existing.status = "active"
            existing.endDate = Self.endDate(fromDuration: draft.duration, start: existing.startDate, calendar: calendar)
            stamp(existing)
            treatment = existing
        } else {
            treatment = TreatmentRecord(
                ownerId: self.ownerId,
                profileId: writeProfileId,
                title: medicineName,
                startDate: now,
                endDate: Self.endDate(fromDuration: draft.duration, start: now, calendar: calendar),
                updatedAt: now
            )
            context.insert(treatment)
            invalidateCache()
        }

        let medicine: MedicineRecord
        if replacingFirst, let existing = medicines(for: treatment.id).first {
            existing.name = medicineName
            existing.doseLabel = draft.dose
            existing.frequency = draft.scheduleFrequency
            existing.duration = draft.duration
            existing.reason = draft.reason
            existing.updatedAt = now
            existing.deletedAt = nil
            stamp(existing)
            medicine = existing
        } else {
            medicine = MedicineRecord(
                treatmentId: treatment.id,
                ownerId: self.ownerId,
                profileId: writeProfileId,
                name: medicineName,
                doseLabel: draft.dose,
                frequency: draft.scheduleFrequency,
                duration: draft.duration,
                reason: draft.reason,
                updatedAt: now
            )
            context.insert(medicine)
            invalidateCache()
        }

        replaceSchedules(for: medicine, times: draft.doseTimes, frequency: draft.scheduleFrequency, now: now)
        logsEnsuredDay = nil
        ensureUpcomingLogs()
        save()
        notify()
        requestSync()
    }

    func markLog(id: UUID, status: DoseLogStatus) {
        guard let log = allLogs().first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        log.status = status.rawValue
        log.loggedAt = Date()
        log.updatedAt = Date()
        stamp(log)
        save()
        notify()
        requestSync()
    }

    func completeTreatment(id: UUID) {
        guard let treatment = allTreatments().first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        treatment.status = "completed"
        treatment.endDate = treatment.endDate ?? Date()
        treatment.updatedAt = Date()
        stamp(treatment)
        save()
        notify()
        requestSync()
    }

    var hasMedicationDaysSet: Bool {
        _ = revision
        let meds = medicineSummaries()
        guard !meds.isEmpty else { return false }
        return meds.allSatisfy { summary in
            Self.endDate(fromDuration: summary.duration, start: Date(), calendar: calendar) != nil
        }
    }

    func draftsFromActivePlan() -> [OnboardingPrescriptionDraft] {
        _ = revision
        let drafts = medicines().compactMap { medicine -> OnboardingPrescriptionDraft? in
            guard medicine.deletedAt == nil else { return nil }
            let times = schedules(for: medicine.id).map(\.timeOfDay).sorted()
            return OnboardingPrescriptionDraft(
                medicine: medicine.name,
                dose: medicine.doseLabel,
                frequency: medicine.frequency,
                duration: medicine.duration,
                timesPerDay: times.isEmpty ? "" : "\(min(4, times.count))",
                doseTimes: times,
                reason: medicine.reason
            )
        }
        return drafts.isEmpty ? [.empty] : drafts
    }

    func deleteActiveTreatments() {
        let now = Date()
        let active = activeTreatments()
        guard !active.isEmpty else { return }
        let treatmentIds = Set(active.map(\.id))
        var scheduleIds = Set<UUID>()
        for treatment in active {
            treatment.deletedAt = now
            treatment.updatedAt = now
            stamp(treatment)
        }
        for medicine in medicines() where treatmentIds.contains(medicine.treatmentId) {
            medicine.deletedAt = now
            medicine.updatedAt = now
            stamp(medicine)
            for schedule in schedules(for: medicine.id) where schedule.deletedAt == nil {
                schedule.deletedAt = now
                schedule.updatedAt = now
                stamp(schedule)
                scheduleIds.insert(schedule.id)
            }
        }
        for log in allLogs() where log.deletedAt == nil && scheduleIds.contains(log.scheduleId) {
            log.deletedAt = now
            log.updatedAt = now
            stamp(log)
        }
        invalidateCache()
        logsEnsuredDay = nil
        save()
        notify()
        requestSync()
    }

    func refillDrafts(now: Date = Date()) -> [ReminderDraft] {
        _ = revision
        var drafts: [ReminderDraft] = []
        for treatment in activeTreatments() {
            guard let end = treatment.endDate else { continue }
            let fire = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: end)) ?? end
            guard fire > now.addingTimeInterval(8) else { continue }
            let firstMed = medicines(for: treatment.id).first
            drafts.append(
                ReminderDraft(
                    id: treatment.id,
                    fireDate: fire,
                    medicine: firstMed?.name ?? treatment.title,
                    doseLabel: firstMed?.duration ?? treatment.title,
                    time: "",
                    kind: .refill
                )
            )
        }
        return drafts
    }

    static func endDate(fromDuration text: String, start: Date, calendar: Calendar) -> Date? {
        if let end = PlanDuration.endDate(from: text, calendar: calendar) {
            return end
        }
        let days = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.last
        guard let days, days > 0 else { return nil }
        return calendar.date(byAdding: .day, value: days, to: start)
    }

    /// Used when AlarmKit / notification actions fire before the SwiftUI store is bound.
    static func persistDoseStatus(id: UUID, status: DoseLogStatus) {
        let schema = Schema([
            TreatmentRecord.self,
            MedicineRecord.self,
            DoseScheduleRecord.self,
            DoseLogRecord.self,
            FeelingRecord.self,
            CommunityCommentRecord.self,
        ])
        let disk = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        guard let container = try? ModelContainer(for: schema, configurations: [disk]) else { return }
        let context = ModelContext(container)
        let target = id
        let descriptor = FetchDescriptor<DoseLogRecord>(
            predicate: #Predicate { row in row.id == target && row.deletedAt == nil }
        )
        guard let log = try? context.fetch(descriptor).first else { return }
        log.status = status.rawValue
        log.loggedAt = Date()
        log.updatedAt = Date()
        try? context.save()
    }

    func todayNodes() -> [DoseNode] {
        _ = revision
        ensureUpcomingLogs()
        let dayLogs = todayLogs().sorted { $0.scheduledAt < $1.scheduledAt }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: schedules().map { ($0.id, $0) })
        var nodes: [DoseNode] = dayLogs.compactMap { log in
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId] else { return nil }
            return DoseNode(
                id: log.id.uuidString,
                time: schedule.timeOfDay,
                medicine: medicine.name,
                detail: medicine.doseLabel,
                status: pathStatus(for: log.status),
                scheduledAt: log.scheduledAt
            )
        }
        guard !nodes.isEmpty else { return [] }
        if let currentIndex = nodes.firstIndex(where: { $0.status == .current || $0.status == .locked }) {
            for index in nodes.indices {
                if index < currentIndex { continue }
                if nodes[index].status == .done || nodes[index].status == .skipped { continue }
                nodes[index].status = index == currentIndex ? .current : .locked
            }
        }
        return nodes
    }

    func adherence() -> AdherenceSnapshot {
        _ = revision
        ensureUpcomingLogs()
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let dayLogs = todayLogs()
        let todayTaken = dayLogs.filter { $0.status == DoseLogStatus.taken.rawValue }.count
        let todayTotal = dayLogs.count
        let history = logs()
        let due = history.filter { $0.scheduledAt <= now }
        let takenCount = due.filter { $0.status == DoseLogStatus.taken.rawValue }.count
        let plannedCount = due.count
        let percent: Int? = plannedCount == 0 ? nil : Int((Double(takenCount) / Double(plannedCount) * 100).rounded())
        var weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        weekStart = calendar.startOfDay(for: weekStart)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        let weekLogs = history.filter { $0.scheduledAt >= weekStart && $0.scheduledAt < weekEnd }
        let weekTaken = weekLogs.filter { $0.status == DoseLogStatus.taken.rawValue }.count
        let weekPlanned = weekLogs.count
        let weekPercent: Int? = weekPlanned == 0 ? nil : Int((Double(weekTaken) / Double(weekPlanned) * 100).rounded())
        return AdherenceSnapshot(
            streakDays: streakDays(now: now, today: today),
            takenCount: takenCount,
            plannedCount: plannedCount,
            percent: percent,
            treatmentCount: activeTreatments().count,
            todayTaken: todayTaken,
            todayTotal: todayTotal,
            hasHistory: !due.isEmpty,
            weekTaken: weekTaken,
            weekPlanned: weekPlanned,
            weekPercent: weekPercent
        )
    }

    func reminderDrafts(now: Date = Date()) -> [ReminderDraft] {
        ensureUpcomingLogs()
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: schedules().map { ($0.id, $0) })
        let horizon = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let grace: TimeInterval = 45 * 60
        var drafts: [ReminderDraft] = []
        for log in logs() where log.status == DoseLogStatus.pending.rawValue {
            guard log.scheduledAt < horizon else { continue }
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId] else { continue }
            if log.scheduledAt > now.addingTimeInterval(8) {
                drafts.append(
                    ReminderDraft(
                        id: log.id,
                        fireDate: log.scheduledAt,
                        medicine: medicine.name,
                        doseLabel: medicine.doseLabel,
                        time: schedule.timeOfDay,
                        kind: .dose
                    )
                )
                let advanceAt = log.scheduledAt.addingTimeInterval(-3600)
                if advanceAt > now.addingTimeInterval(8) {
                    drafts.append(
                        ReminderDraft(
                            id: log.id,
                            fireDate: advanceAt,
                            medicine: medicine.name,
                            doseLabel: medicine.doseLabel,
                            time: schedule.timeOfDay,
                            kind: .advance
                        )
                    )
                }
            }
            let missedAt = log.scheduledAt.addingTimeInterval(grace)
            if missedAt > now.addingTimeInterval(8), missedAt < horizon {
                drafts.append(
                    ReminderDraft(
                        id: log.id,
                        fireDate: missedAt,
                        medicine: medicine.name,
                        doseLabel: medicine.doseLabel,
                        time: schedule.timeOfDay,
                        kind: .missed
                    )
                )
            }
        }
        return drafts.sorted { $0.fireDate < $1.fireDate }
    }

    func reminderTimesLabel() -> String {
        let times = schedules().map(\.timeOfDay).sorted()
        let unique = Array(NSOrderedSet(array: times)).compactMap { $0 as? String }
        return unique.joined(separator: " · ")
    }

    func dayStatuses(count: Int = 14) -> [(day: Int, kind: String)] {
        let today = calendar.startOfDay(for: Date())
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -(count / 2), to: today) else { return [] }
        var cells: [(day: Int, kind: String)] = []
        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let dayLogs = logs().filter { $0.scheduledAt >= day && $0.scheduledAt < end }
            let number = calendar.component(.day, from: day)
            if day > today {
                cells.append((number, "soon"))
            } else if calendar.isDate(day, inSameDayAs: today) {
                cells.append((number, "today"))
            } else if dayLogs.isEmpty {
                cells.append((number, "soon"))
            } else if dayLogs.contains(where: { $0.status == DoseLogStatus.pending.rawValue && $0.scheduledAt < now }) {
                cells.append((number, "miss"))
            } else if dayLogs.contains(where: { $0.status == DoseLogStatus.taken.rawValue }) {
                cells.append((number, "done"))
            } else {
                cells.append((number, "done"))
            }
        }
        return cells
    }

    func addFeeling(logId: UUID?, medicineName: String, mood: FeelingMood, note: String) {
        let row = FeelingRecord(
            ownerId: ownerId,
            profileId: writeProfileId,
            logId: logId,
            medicineName: medicineName,
            mood: mood.rawValue,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(row)
        save()
        notify()
    }

    func recentFeelings(limit: Int = 14) -> [FeelingRecord] {
        _ = revision
        return feelings()
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func comments(forMedicine name: String) -> [CommunityCommentRecord] {
        _ = revision
        let key = Self.medicineKey(name)
        return allComments()
            .filter { $0.medicineKey == key }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func addComment(medicineName: String, author: String, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let row = CommunityCommentRecord(
            ownerId: ownerId,
            medicineKey: Self.medicineKey(medicineName),
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            body: trimmed
        )
        context.insert(row)
        save()
        notify()
    }

    func journeyReports() -> [JourneyReport] {
        _ = revision
        var seen = Set<UUID>()
        var reports: [JourneyReport] = []
        for treatment in activeTreatments() + finishedTreatments() {
            guard seen.insert(treatment.id).inserted, let report = journeyReport(for: treatment) else { continue }
            reports.append(report)
        }
        return reports
    }

    func finishedJourneyReports() -> [JourneyReport] {
        _ = revision
        return finishedTreatments().compactMap { journeyReport(for: $0) }
    }

    private func journeyReport(for treatment: TreatmentRecord) -> JourneyReport? {
        let meds = medicines().filter { $0.treatmentId == treatment.id }
        guard !meds.isEmpty else { return nil }
        let medIds = Set(meds.map(\.id))
        let scheduleIds = Set(schedules().filter { medIds.contains($0.medicineId) }.map(\.id))
        let related = logs().filter { scheduleIds.contains($0.scheduleId) && $0.scheduledAt <= Date() }
        let taken = related.filter { $0.status == DoseLogStatus.taken.rawValue }.count
        let skipped = related.filter { $0.status == DoseLogStatus.skipped.rawValue }.count
        let planned = related.count
        let percent = planned == 0 ? 0 : Int((Double(taken) / Double(planned) * 100).rounded())
        let names = Set(meds.map(\.name))
        let relatedFeelings = feelings().filter { feeling in
            names.contains { $0.caseInsensitiveCompare(feeling.medicineName) == .orderedSame }
        }
        return JourneyReport(
            treatmentId: treatment.id,
            title: treatment.title,
            startDate: treatment.startDate,
            endDate: treatment.endDate,
            takenCount: taken,
            skippedCount: skipped,
            plannedCount: planned,
            percent: percent,
            medicines: meds.map(\.name),
            feelingGreat: relatedFeelings.filter { $0.mood == FeelingMood.great.rawValue }.count,
            feelingOkay: relatedFeelings.filter { $0.mood == FeelingMood.okay.rawValue }.count,
            feelingLow: relatedFeelings.filter { $0.mood == FeelingMood.low.rawValue }.count,
            feelingSideEffect: relatedFeelings.filter { $0.mood == FeelingMood.sideEffect.rawValue }.count
        )
    }

    private func finishedTreatments() -> [TreatmentRecord] {
        let now = Date()
        return visible(allTreatments()).filter { treatment in
            guard treatment.deletedAt == nil else { return false }
            if treatment.status == "completed" { return true }
            if let end = treatment.endDate, end < calendar.startOfDay(for: now) { return true }
            return false
        }
    }

    private func feelings() -> [FeelingRecord] {
        visible(allFeelings())
    }

    private func allFeelings() -> [FeelingRecord] {
        fetch()
    }

    private func allComments() -> [CommunityCommentRecord] {
        fetch()
    }

    static func medicineKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sync support

    func treatmentSnapshots() -> [TreatmentSnapshot] { syncable(allTreatments()).map(\.snapshot) }
    func medicineSnapshots() -> [MedicineSnapshot] { syncable(allMedicines()).map(\.snapshot) }
    func scheduleSnapshots() -> [DoseScheduleSnapshot] { syncable(allSchedules()).map(\.snapshot) }
    func logSnapshots() -> [DoseLogSnapshot] { syncable(allLogs()).map(\.snapshot) }

    func mergeTreatment(_ row: TreatmentSnapshot) {
        if let existing = allTreatments().first(where: { $0.id == row.id }) {
            guard row.updatedAt >= existing.updatedAt else { return }
            existing.apply(row)
        } else {
            context.insert(TreatmentRecord(snapshot: row))
            invalidateCache()
        }
    }

    func mergeMedicine(_ row: MedicineSnapshot) {
        if let existing = allMedicines().first(where: { $0.id == row.id }) {
            guard row.updatedAt >= existing.updatedAt else { return }
            existing.apply(row)
        } else {
            context.insert(MedicineRecord(snapshot: row))
            invalidateCache()
        }
    }

    func mergeSchedule(_ row: DoseScheduleSnapshot) {
        if let existing = allSchedules().first(where: { $0.id == row.id }) {
            guard row.updatedAt >= existing.updatedAt else { return }
            existing.apply(row)
        } else {
            context.insert(DoseScheduleRecord(snapshot: row))
            invalidateCache()
        }
    }

    func mergeLog(_ row: DoseLogSnapshot) {
        if let existing = allLogs().first(where: { $0.id == row.id }) {
            guard row.updatedAt >= existing.updatedAt else { return }
            existing.apply(row)
        } else {
            context.insert(DoseLogRecord(snapshot: row))
            invalidateCache()
        }
    }

    func saveAfterSync() {
        logsEnsuredDay = nil
        save()
        ensureUpcomingLogs()
        notify()
    }

    private func allTreatments() -> [TreatmentRecord] {
        if let cachedTreatments { return cachedTreatments }
        let rows: [TreatmentRecord] = fetch()
        cachedTreatments = rows
        return rows
    }

    private func allMedicines() -> [MedicineRecord] {
        if let cachedMedicines { return cachedMedicines }
        let rows: [MedicineRecord] = fetch()
        cachedMedicines = rows
        return rows
    }

    private func allSchedules() -> [DoseScheduleRecord] {
        if let cachedSchedules { return cachedSchedules }
        let rows: [DoseScheduleRecord] = fetch()
        cachedSchedules = rows
        return rows
    }

    private func allLogs() -> [DoseLogRecord] {
        if let cachedLogs { return cachedLogs }
        let rows: [DoseLogRecord] = fetch()
        cachedLogs = rows
        return rows
    }

    // MARK: - Private

    private func replaceSchedules(for medicine: MedicineRecord, times: [String], frequency: String, now: Date) {
        let slots: [(time: String, period: String)]
        if times.contains(where: { !$0.isEmpty }) {
            slots = times.filter { !$0.isEmpty }.map { ($0, Self.period(for: $0)) }
        } else {
            slots = Self.slots(for: frequency)
        }
        let existing = schedules(for: medicine.id)
        for schedule in existing {
            schedule.deletedAt = now
            schedule.updatedAt = now
        }
        for slot in slots {
            if let match = existing.first(where: { $0.timeOfDay == slot.time && $0.period == slot.period }) {
                match.deletedAt = nil
                match.updatedAt = now
                stamp(match)
            } else {
                let schedule = DoseScheduleRecord(
                    medicineId: medicine.id,
                    ownerId: ownerId,
                    profileId: writeProfileId,
                    timeOfDay: slot.time,
                    period: slot.period,
                    updatedAt: now
                )
                context.insert(schedule)
                invalidateCache()
            }
        }
    }

    private func ensureUpcomingLogs() {
        let day = calendar.startOfDay(for: Date())
        let signature = [
            calendar.timeZone.identifier,
            schedules().map(\.id.uuidString).sorted().joined(),
            scopeProfileId?.uuidString ?? "",
            includeUnscoped ? "1" : "0",
        ].joined(separator: "|").hashValue
        if logsEnsuredDay == day, logsEnsuredSignature == signature { return }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        var inserted = 0
        for offset in 0..<7 {
            guard let slotDay = calendar.date(byAdding: .day, value: offset, to: day),
                  let end = calendar.date(byAdding: .day, value: 1, to: slotDay) else { continue }
            let existing = allLogs().filter {
                $0.deletedAt == nil && $0.scheduledAt >= slotDay && $0.scheduledAt < end
            }
            for schedule in schedules() {
                guard let medicine = medicinesById[schedule.medicineId],
                      medicine.deletedAt == nil,
                      activeTreatmentIds.contains(medicine.treatmentId) else { continue }
                guard let scheduledAt = date(on: slotDay, timeOfDay: schedule.timeOfDay) else { continue }
                let already = existing.contains { log in
                    log.scheduleId == schedule.id && calendar.isDate(log.scheduledAt, inSameDayAs: scheduledAt)
                }
                guard !already else { continue }
                let log = DoseLogRecord(
                    scheduleId: schedule.id,
                    ownerId: ownerId,
                    profileId: writeProfileId,
                    scheduledAt: scheduledAt,
                    status: DoseLogStatus.pending.rawValue,
                    updatedAt: Date()
                )
                context.insert(log)
                inserted += 1
            }
        }
        logsEnsuredDay = day
        logsEnsuredSignature = signature
        if inserted > 0 {
            invalidateCache()
            save()
        }
    }

    private func todayLogs() -> [DoseLogRecord] {
        let day = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return logs().filter { $0.scheduledAt >= day && $0.scheduledAt < end }
    }

    private func streakDays(now: Date, today: Date) -> Int {
        var cursor = today
        var counted = 0
        for _ in 0..<120 {
            guard let end = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let dayLogs = logs().filter { $0.scheduledAt >= cursor && $0.scheduledAt < end }
            let isToday = calendar.isDate(cursor, inSameDayAs: today)
            if dayLogs.isEmpty {
                if isToday {
                    guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = previous
                    continue
                }
                break
            }
            if isToday {
                if dayLogs.contains(where: { $0.status == DoseLogStatus.taken.rawValue }) {
                    counted += 1
                }
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
                continue
            }
            let missed = dayLogs.contains { $0.status == DoseLogStatus.pending.rawValue }
            if missed { break }
            if dayLogs.contains(where: { $0.status == DoseLogStatus.taken.rawValue }) {
                counted += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        _ = now
        return counted
    }

    private func activeTreatments() -> [TreatmentRecord] {
        treatments().filter { $0.status == "active" }
    }

    private var writeProfileId: UUID? { scopeProfileId ?? stampProfileId }

    private func treatments() -> [TreatmentRecord] { visible(allTreatments()).filter { $0.deletedAt == nil } }
    private func medicines() -> [MedicineRecord] { visible(allMedicines()).filter { $0.deletedAt == nil } }
    private func schedules() -> [DoseScheduleRecord] { visible(allSchedules()).filter { $0.deletedAt == nil } }
    private func logs() -> [DoseLogRecord] { visible(allLogs()).filter { $0.deletedAt == nil } }

    private func medicines(for treatmentId: UUID) -> [MedicineRecord] {
        medicines().filter { $0.treatmentId == treatmentId }
    }

    private func schedules(for medicineId: UUID) -> [DoseScheduleRecord] {
        allSchedules().filter { $0.medicineId == medicineId }
    }

    private func owned<T>(_ rows: [T]) -> [T] {
        guard let ownerId else { return rows }
        return rows.filter { row in
            if let record = row as? TreatmentRecord { return record.ownerId == nil || record.ownerId == ownerId }
            if let record = row as? MedicineRecord { return record.ownerId == nil || record.ownerId == ownerId }
            if let record = row as? DoseScheduleRecord { return record.ownerId == nil || record.ownerId == ownerId }
            if let record = row as? DoseLogRecord { return record.ownerId == nil || record.ownerId == ownerId }
            if let record = row as? FeelingRecord { return record.ownerId == nil || record.ownerId == ownerId }
            if let record = row as? CommunityCommentRecord { return record.ownerId == nil || record.ownerId == ownerId }
            return true
        }
    }

    private func visible<T>(_ rows: [T]) -> [T] {
        owned(rows).filter { row in
            let pid = profileId(of: row)
            if let scopeProfileId {
                if pid == scopeProfileId { return true }
                if includeUnscoped && (pid == nil || pid == stampProfileId) { return true }
                return false
            }
            return true
        }
    }

    private func profileId<T>(of row: T) -> UUID? {
        if let record = row as? TreatmentRecord { return record.profileId }
        if let record = row as? MedicineRecord { return record.profileId }
        if let record = row as? DoseScheduleRecord { return record.profileId }
        if let record = row as? DoseLogRecord { return record.profileId }
        if let record = row as? FeelingRecord { return record.profileId }
        return nil
    }

    private func syncable<T>(_ rows: [T]) -> [T] {
        rows.filter { row in
            let pid = profileId(of: row)
            return pid == nil || pid == stampProfileId
        }
    }

    private func stampIdentity() {
        var changed = false
        for treatment in allTreatments() where treatment.ownerId == nil {
            treatment.ownerId = ownerId
            treatment.profileId = stampProfileId ?? treatment.profileId
            treatment.updatedAt = Date()
            changed = true
        }
        for medicine in allMedicines() where medicine.ownerId == nil {
            medicine.ownerId = ownerId
            medicine.profileId = stampProfileId ?? medicine.profileId
            medicine.updatedAt = Date()
            changed = true
        }
        for schedule in allSchedules() where schedule.ownerId == nil {
            schedule.ownerId = ownerId
            schedule.profileId = stampProfileId ?? schedule.profileId
            schedule.updatedAt = Date()
            changed = true
        }
        for log in allLogs() where log.ownerId == nil {
            log.ownerId = ownerId
            log.profileId = stampProfileId ?? log.profileId
            log.updatedAt = Date()
            changed = true
        }
        if let stampProfileId {
            for treatment in allTreatments() where treatment.profileId == nil && treatment.ownerId == ownerId {
                treatment.profileId = stampProfileId
                changed = true
            }
            for medicine in allMedicines() where medicine.profileId == nil && medicine.ownerId == ownerId {
                medicine.profileId = stampProfileId
                changed = true
            }
            for schedule in allSchedules() where schedule.profileId == nil && schedule.ownerId == ownerId {
                schedule.profileId = stampProfileId
                changed = true
            }
            for log in allLogs() where log.profileId == nil && log.ownerId == ownerId {
                log.profileId = stampProfileId
                changed = true
            }
        }
        if changed { save() }
    }

    private func stamp(_ treatment: TreatmentRecord) {
        treatment.ownerId = ownerId ?? treatment.ownerId
        treatment.profileId = writeProfileId ?? treatment.profileId
    }

    private func stamp(_ medicine: MedicineRecord) {
        medicine.ownerId = ownerId ?? medicine.ownerId
        medicine.profileId = writeProfileId ?? medicine.profileId
    }

    private func stamp(_ schedule: DoseScheduleRecord) {
        schedule.ownerId = ownerId ?? schedule.ownerId
        schedule.profileId = writeProfileId ?? schedule.profileId
    }

    private func stamp(_ log: DoseLogRecord) {
        log.ownerId = ownerId ?? log.ownerId
        log.profileId = writeProfileId ?? log.profileId
    }

    private func pathStatus(for raw: String) -> PathStatus {
        switch DoseLogStatus(rawValue: raw) {
        case .taken: .done
        case .skipped: .skipped
        case .pending, .none: .locked
        }
    }

    private func fetch<T: PersistentModel>() -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func invalidateCache() {
        cachedTreatments = nil
        cachedMedicines = nil
        cachedSchedules = nil
        cachedLogs = nil
    }

    private func save() {
        try? context.save()
        invalidateCache()
    }

    private func notify() {
        revision += 1
        onRecordsChanged?()
    }

    private func requestSync() {
        Task { await onNeedsSync?() }
    }

    static func defaultTimes(count: Int) -> [String] {
        switch max(1, min(4, count)) {
        case 4: ["08:00", "12:00", "16:00", "20:00"]
        case 3: ["08:00", "12:00", "20:00"]
        case 2: ["08:00", "20:00"]
        default: ["08:00"]
        }
    }

    static func compactHourLabel(_ timeOfDay: String) -> String {
        let parts = timeOfDay.split(separator: ":")
        guard let hour = parts.first.flatMap({ Int($0) }) else { return timeOfDay }
        if parts.count > 1, parts[1] != "00" {
            return "\(hour)h\(parts[1])"
        }
        return "\(hour)h"
    }

    static func period(for timeOfDay: String) -> String {
        let hour = Int(timeOfDay.split(separator: ":").first ?? "8") ?? 8
        if hour < 12 { return "Morning" }
        if hour < 17 { return "Afternoon" }
        return "Evening"
    }

    static func slots(for frequency: String) -> [(time: String, period: String)] {
        let value = frequency.lowercased()
        if value.contains("as needed") || value.contains("quando") || value.contains("según") || value.contains("si besoin") {
            return [("12:00", "Afternoon")]
        }
        let count: Int
        if value.contains("4") { count = 4 }
        else if value.contains("3") { count = 3 }
        else if value.contains("2") { count = 2 }
        else { count = 1 }
        return defaultTimes(count: count).map { ($0, period(for: $0)) }
    }

    private func date(on day: Date, timeOfDay: String) -> Date? {
        Self.date(on: day, timeOfDay: timeOfDay, calendar: calendar)
    }

    static func date(on day: Date, timeOfDay: String, calendar: Calendar = .current) -> Date? {
        let parts = timeOfDay.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

enum PlanDuration {
    static func encode(start: Date, end: Date, calendar: Calendar) -> String {
        let days = dayCount(from: start, to: end, calendar: calendar)
        return "\(iso(start, calendar: calendar))|\(iso(end, calendar: calendar))|\(days)"
    }

    static func display(_ text: String, locale: Locale, calendar: Calendar) -> String {
        let bounds = bounds(from: text, calendar: calendar) ?? defaultBounds(from: text, calendar: calendar)
        guard let bounds else { return text }
        let days = dayCount(from: bounds.start, to: bounds.end, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMMy")
        let startText = formatter.string(from: bounds.start)
        let endText = formatter.string(from: bounds.end)
        if calendar.isDate(bounds.start, equalTo: bounds.end, toGranularity: .month) {
            let dayOnly = DateFormatter()
            dayOnly.calendar = calendar
            dayOnly.locale = locale
            dayOnly.setLocalizedDateFormatFromTemplate("d")
            return "\(dayOnly.string(from: bounds.start))–\(endText) (\(days))"
        }
        return "\(startText) – \(endText) (\(days))"
    }

    static func endDate(from text: String, calendar: Calendar) -> Date? {
        bounds(from: text, calendar: calendar)?.end
    }

    static func bounds(from text: String, calendar: Calendar) -> (start: Date, end: Date)? {
        let parts = text.split(separator: "|").map(String.init)
        guard parts.count >= 2, let start = date(parts[0], calendar: calendar), let end = date(parts[1], calendar: calendar) else {
            return nil
        }
        return (start, end)
    }

    private static func defaultBounds(from text: String, calendar: Calendar) -> (start: Date, end: Date)? {
        let days = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.last
        guard let days, days > 0 else { return nil }
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: max(0, days - 1), to: start) ?? start
        return (start, end)
    }

    private static func dayCount(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: max(end, start))
        return max(1, (calendar.dateComponents([.day], from: s, to: e).day ?? 0) + 1)
    }

    private static func iso(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(_ stamp: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: stamp)
    }
}
