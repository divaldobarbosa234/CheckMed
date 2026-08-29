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
}

struct ReminderDraft: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case dose
        case missed
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
        }
    }
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

    struct MedicineSummary: Identifiable {
        var id: UUID
        var name: String
        var doseLabel: String
        var frequency: String
        var duration: String
        var treatmentTitle: String
    }

    func medicineSummaries() -> [MedicineSummary] {
        _ = revision
        let treatmentsById = Dictionary(uniqueKeysWithValues: activeTreatments().map { ($0.id, $0) })
        return medicines().compactMap { medicine in
            guard let treatment = treatmentsById[medicine.treatmentId] else { return nil }
            return MedicineSummary(
                id: medicine.id,
                name: medicine.name,
                doseLabel: medicine.doseLabel,
                frequency: medicine.frequency,
                duration: medicine.duration,
                treatmentTitle: treatment.title
            )
        }
    }

    /// First-treatment onboarding: create or replace the single active plan.
    func seedFromDraft(_ draft: OnboardingPrescriptionDraft, ownerId: UUID?, profileId: UUID?) {
        saveDraft(draft, ownerId: ownerId, profileId: profileId, replacingFirst: true)
    }

    /// Later adds from Home: always insert a new treatment.
    func addFromDraft(_ draft: OnboardingPrescriptionDraft, ownerId: UUID?, profileId: UUID?) {
        saveDraft(draft, ownerId: ownerId, profileId: profileId, replacingFirst: false)
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
        let now = Date()
        let medicineName = draft.medicine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !medicineName.isEmpty else { return }

        let treatment: TreatmentRecord
        if replacingFirst, let existing = activeTreatments().first {
            existing.title = medicineName
            existing.updatedAt = now
            existing.deletedAt = nil
            existing.status = "active"
            stamp(existing)
            treatment = existing
        } else {
            treatment = TreatmentRecord(
                ownerId: self.ownerId,
                profileId: writeProfileId,
                title: medicineName,
                startDate: now,
                updatedAt: now
            )
            context.insert(treatment)
            invalidateCache()
        }

        let medicine: MedicineRecord
        if replacingFirst, let existing = medicines(for: treatment.id).first {
            existing.name = medicineName
            existing.doseLabel = draft.dose
            existing.frequency = draft.frequency
            existing.duration = draft.duration
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
                frequency: draft.frequency,
                duration: draft.duration,
                updatedAt: now
            )
            context.insert(medicine)
            invalidateCache()
        }

        replaceSchedules(for: medicine, frequency: draft.frequency, now: now)
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

    /// Used when AlarmKit / notification actions fire before the SwiftUI store is bound.
    static func persistDoseStatus(id: UUID, status: DoseLogStatus) {
        let schema = Schema([
            TreatmentRecord.self,
            MedicineRecord.self,
            DoseScheduleRecord.self,
            DoseLogRecord.self,
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
        return AdherenceSnapshot(
            streakDays: streakDays(now: now, today: today),
            takenCount: takenCount,
            plannedCount: plannedCount,
            percent: percent,
            treatmentCount: activeTreatments().count,
            todayTaken: todayTaken,
            todayTotal: todayTotal,
            hasHistory: !due.isEmpty
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

    private func replaceSchedules(for medicine: MedicineRecord, frequency: String, now: Date) {
        let slots = Self.slots(for: frequency)
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

    static func slots(for frequency: String) -> [(time: String, period: String)] {
        let value = frequency.lowercased()
        if value.contains("as needed") || value.contains("quando") || value.contains("según") || value.contains("si besoin") {
            return [("12:00", "Afternoon")]
        }
        if value.contains("4") {
            return [
                ("08:00", "Morning"),
                ("12:00", "Afternoon"),
                ("16:00", "Afternoon"),
                ("20:00", "Evening"),
            ]
        }
        if value.contains("3") {
            return [
                ("08:00", "Morning"),
                ("14:00", "Afternoon"),
                ("20:00", "Evening"),
            ]
        }
        if value.contains("2") {
            return [
                ("08:00", "Morning"),
                ("20:00", "Evening"),
            ]
        }
        return [("08:00", "Morning")]
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
