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
        case stockRefill
        case stockDaysLeft
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
        case .stockRefill: "checkmed.stockRefill.\(id.uuidString)"
        case .stockDaysLeft: "checkmed.stockDays.\(id.uuidString).\(Int(fireDate.timeIntervalSince1970))"
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
    /// When false, Home / reminders / summaries hide plan rows even if SwiftData still has them.
    private(set) var surfacesPlan = false

    @ObservationIgnored
    var onRecordsChanged: (() -> Void)?
    @ObservationIgnored
    var onNeedsSync: (() async -> Void)?

    func setSurfacesPlan(_ enabled: Bool) {
        guard surfacesPlan != enabled else { return }
        surfacesPlan = enabled
        if !enabled {
            logsEnsuredDay = nil
        }
        notify()
    }
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
        purgeUnownedOrphans()
        ensureUpcomingLogs()
        notify()
    }

    /// One-time: if the user never confirmed a medication plan, wipe leftover / sync-restored rows.
    /// Completed intentional plans (days set + notifications done) are bootstrapped as confirmed.
    /// Unfinished plans are kept for resume UI but stay hidden on Home until confirmed.
    /// Never deletes after `hasConfirmedMedicationPlan` — confirm + seed win over migration.
    @discardableResult
    func reconcileUnconfirmedMedicationPlan(session: SessionStore) -> Bool {
        if session.hasConfirmedMedicationPlan {
            setSurfacesPlan(true)
            let owner = ownerId
            if !session.didPurgeUnconfirmedPlans(ownerId: owner) {
                session.markDidPurgeUnconfirmedPlans(ownerId: owner)
            }
            return false
        }

        setSurfacesPlan(false)
        let owner = ownerId
        guard !session.didPurgeUnconfirmedPlans(ownerId: owner) else {
            return false
        }
        session.markDidPurgeUnconfirmedPlans(ownerId: owner)

        let medicineCount = medicines().count
        if medicineCount == 0 {
            return false
        }

        let fixture = looksLikeFixtureOrDemoPlan()
        let daysSet = hasMedicationDaysSet
        let notificationsDone = !session.needsNotificationsPrompt

        // Returning user who finished setup before this flag existed — keep unless OCR fixture.
        if daysSet && notificationsDone && session.hasCompletedOnboarding && !fixture {
            session.markMedicationPlanConfirmed()
            setSurfacesPlan(true)
            return false
        }

        // Mid unfinished setup: keep rows for resume / unfinished prompt, hide from Home + alarms.
        if !fixture && (session.needsNotificationsPrompt || !daysSet) {
            return false
        }

        // Ghost / fixture / sync-restored leftover the user never confirmed.
        deleteAllOwnedPlanData()
        setSurfacesPlan(false)
        return true
    }

    /// OCR test fixtures and common leftover demo names (Amoxidal is never a real catalog RX here).
    private func looksLikeFixtureOrDemoPlan() -> Bool {
        let names = medicines().map { $0.name.lowercased() }
        guard !names.isEmpty else { return false }
        if names.contains(where: { $0.contains("amoxidal") }) { return true }
        let tokens = [
            "amoxicilina", "amoxicillin", "paracetamol",
            "ibuprofen", "ibuprofeno", "losartana", "metformina",
        ]
        let hits = names.filter { name in tokens.contains { name.contains($0) } }.count
        return hits >= 2 && hits == names.count
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

    var activeTreatmentCount: Int {
        _ = revision
        guard surfacesPlan else { return 0 }
        return activeTreatments().count
    }

    var activeMedicineCount: Int {
        _ = revision
        guard surfacesPlan else { return 0 }
        return medicineSummaries().count
    }

    /// Active-plan medicine count for free-plan caps / scan gates.
    /// Ungated from `surfacesPlan` (unfinished plans still consume slots).
    /// Completed / soft-deleted treatments never count — they must not block Scan.
    var storedMedicineCount: Int {
        _ = revision
        let activeIds = Set(activeTreatments().map(\.id))
        return medicines().filter { activeIds.contains($0.treatmentId) }.count
    }

    func deleteMedicine(id: UUID) {
        guard let medicine = medicines().first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        let now = Date()
        removeMedicine(medicine, now: now)
        if medicines(for: medicine.treatmentId).isEmpty,
           let treatment = activeTreatments().first(where: { $0.id == medicine.treatmentId }) {
            treatment.deletedAt = now
            treatment.updatedAt = now
            stamp(treatment)
        }
        logsEnsuredDay = nil
        invalidateCache()
        save()
        notify()
        requestSync()
    }

    func daysUntilNextRevision(calendar: Calendar) -> Int? {
        _ = revision
        guard surfacesPlan else { return nil }
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
        var form: MedicineForm
        var packageAmount: Double
        var packageUnit: MedicineUnit
        var stockPercent: Double
        var quantityPerDose: Double
        var doseUnit: MedicineUnit
        var doctorName: String
        var doctorId: String
        var hospitalName: String
        var doctorNotes: String
        var reason: String
        var lastRefillAt: Date?
        var refillRemindEnabled: Bool
        var daysLeft: Double?
        var scheduleTimes: [String]
        var daysOnTreatment: Int
        var missedCount: Int
    }

    func medicineSummaries() -> [MedicineSummary] {
        _ = revision
        guard surfacesPlan else { return [] }
        let treatmentsById = Dictionary(uniqueKeysWithValues: activeTreatments().map { ($0.id, $0) })
        let now = Date()
        return medicines().compactMap { medicine in
            guard let treatment = treatmentsById[medicine.treatmentId] else { return nil }
            medicine.applyDoseDefaultsIfNeeded()
            let medSchedules = schedules(for: medicine.id)
            let times = max(1, medSchedules.count)
            let scheduleTimes = medSchedules.map(\.timeOfDay).sorted()
            let days = MedicineUnits.daysLeft(
                packageAmount: medicine.packageAmount,
                packageUnit: medicine.packageMedicineUnit,
                stockPercent: medicine.stockPercent,
                quantityPerDose: medicine.quantityPerDose,
                doseUnit: medicine.doseMedicineUnit,
                timesPerDay: times
            )
            let scheduleIds = Set(medSchedules.map(\.id))
            let medLogs = allLogs().filter { scheduleIds.contains($0.scheduleId) && $0.deletedAt == nil }
            let missed = medLogs.filter {
                $0.scheduledAt <= now && $0.status == DoseLogStatus.skipped.rawValue
            }.count
            let daysOn = max(
                1,
                calendar.dateComponents([.day], from: calendar.startOfDay(for: treatment.startDate), to: calendar.startOfDay(for: now)).day ?? 1
            )
            return MedicineSummary(
                id: medicine.id,
                treatmentId: treatment.id,
                name: medicine.name,
                doseLabel: medicine.doseLabel,
                frequency: medicine.frequency,
                duration: medicine.duration,
                timesPerDay: times,
                treatmentTitle: treatment.title,
                treatmentStatus: treatment.status,
                form: medicine.medicineForm,
                packageAmount: medicine.packageAmount,
                packageUnit: medicine.packageMedicineUnit,
                stockPercent: medicine.stockPercent,
                quantityPerDose: medicine.quantityPerDose,
                doseUnit: medicine.doseMedicineUnit,
                doctorName: medicine.doctorName,
                doctorId: medicine.doctorId,
                hospitalName: medicine.hospitalName,
                doctorNotes: medicine.doctorNotes,
                reason: medicine.reason,
                lastRefillAt: medicine.lastRefillAt,
                refillRemindEnabled: medicine.refillRemindEnabled,
                daysLeft: days,
                scheduleTimes: scheduleTimes,
                daysOnTreatment: daysOn,
                missedCount: missed
            )
        }
    }

    func medicineMostUrgentForRefill() -> MedicineSummary? {
        medicineSummaries()
            .filter { $0.refillRemindEnabled && ($0.daysLeft != nil || $0.stockPercent < 100) }
            .sorted { lhs, rhs in
                let ld = lhs.daysLeft ?? 999
                let rd = rhs.daysLeft ?? 999
                if ld != rd { return ld < rd }
                return lhs.timesPerDay > rhs.timesPerDay
            }
            .first
    }

    /// First-treatment onboarding: create or replace the single active plan.
    @discardableResult
    func seedFromDraft(_ draft: OnboardingPrescriptionDraft, ownerId: UUID?, profileId: UUID?) -> Bool {
        seedFromDrafts([draft], ownerId: ownerId, profileId: profileId)
    }

    @discardableResult
    func seedFromDrafts(_ drafts: [OnboardingPrescriptionDraft], ownerId: UUID?, profileId: UUID?) -> Bool {
        persistDrafts(drafts, ownerId: ownerId, profileId: profileId, replacePlan: true)
    }

    /// Later adds from Home: always insert a new treatment.
    @discardableResult
    func addFromDraft(_ draft: OnboardingPrescriptionDraft, ownerId: UUID?, profileId: UUID?) -> Bool {
        addFromDrafts([draft], ownerId: ownerId, profileId: profileId)
    }

    @discardableResult
    func addFromDrafts(_ drafts: [OnboardingPrescriptionDraft], ownerId: UUID?, profileId: UUID?) -> Bool {
        persistDrafts(drafts, ownerId: ownerId, profileId: profileId, replacePlan: false)
    }

    /// Move guest / local-device rows onto the signed-in account so Home still shows the plan.
    func adoptOwner(from previousOwnerId: UUID, to newOwnerId: UUID, profileId: UUID?) {
        guard previousOwnerId != newOwnerId else { return }
        let now = Date()
        var changed = false
        for treatment in allTreatments() where treatment.ownerId == previousOwnerId {
            treatment.ownerId = newOwnerId
            if let profileId { treatment.profileId = treatment.profileId ?? profileId }
            treatment.updatedAt = now
            changed = true
        }
        for medicine in allMedicines() where medicine.ownerId == previousOwnerId {
            medicine.ownerId = newOwnerId
            if let profileId { medicine.profileId = medicine.profileId ?? profileId }
            medicine.updatedAt = now
            changed = true
        }
        for schedule in allSchedules() where schedule.ownerId == previousOwnerId {
            schedule.ownerId = newOwnerId
            if let profileId { schedule.profileId = schedule.profileId ?? profileId }
            schedule.updatedAt = now
            changed = true
        }
        for log in allLogs() where log.ownerId == previousOwnerId {
            log.ownerId = newOwnerId
            if let profileId { log.profileId = log.profileId ?? profileId }
            log.updatedAt = now
            changed = true
        }
        guard changed else { return }
        invalidateCache()
        logsEnsuredDay = nil
        save()
        notify()
        #if DEBUG
        print("[CheckMed] adoptOwner \(previousOwnerId) → \(newOwnerId)")
        #endif
    }

    @discardableResult
    private func persistDrafts(
        _ drafts: [OnboardingPrescriptionDraft],
        ownerId: UUID?,
        profileId: UUID?,
        replacePlan: Bool
    ) -> Bool {
        let named = drafts.filter(\.hasMedicineName)
        guard let ownerId else {
            #if DEBUG
            print("[CheckMed] persistDrafts aborted: missing ownerId (named=\(named.count))")
            #endif
            return false
        }
        guard let first = named.first else {
            #if DEBUG
            print("[CheckMed] persistDrafts aborted: no named medicines")
            #endif
            return false
        }
        // Confirmed prescriptions must surface immediately (Home + logs + alarms).
        setSurfacesPlan(true)
        saveDraft(
            first,
            ownerId: ownerId,
            profileId: profileId,
            replacingFirst: replacePlan,
            ontoTreatment: replacePlan ? nil : activeTreatments().first
        )
        let plan = activeTreatments().first
        for draft in named.dropFirst() {
            saveDraft(
                draft,
                ownerId: ownerId,
                profileId: profileId,
                replacingFirst: false,
                ontoTreatment: plan
            )
        }
        let saved = medicines().count
        #if DEBUG
        print("[CheckMed] persistDrafts ok replace=\(replacePlan) seeded=\(named.count) stored=\(saved) surfacesPlan=\(surfacesPlan)")
        #endif
        return saved > 0
    }

    private func saveDraft(
        _ draft: OnboardingPrescriptionDraft,
        ownerId: UUID?,
        profileId: UUID?,
        replacingFirst: Bool,
        ontoTreatment: TreatmentRecord? = nil
    ) {
        if let ownerId {
            self.ownerId = ownerId
        }
        if let profileId {
            stampProfileId = stampProfileId ?? profileId
            if scopeProfileId == nil { scopeProfileId = profileId }
        }
        var draft = draft
        draft.syncDoseTimes()
        let now = Date()
        let medicineName = draft.medicine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !medicineName.isEmpty else { return }
        guard self.ownerId != nil else {
            #if DEBUG
            print("[CheckMed] saveDraft aborted: store ownerId still nil for \(medicineName)")
            #endif
            return
        }

        let treatment: TreatmentRecord
        if let ontoTreatment {
            treatment = ontoTreatment
        } else if replacingFirst, let existing = activeTreatments().first {
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
        if replacingFirst, ontoTreatment == nil, let existing = medicines(for: treatment.id).first {
            existing.name = medicineName
            existing.doseLabel = draft.dose
            existing.frequency = draft.scheduleFrequency
            existing.duration = draft.duration
            existing.reason = draft.reason
            applyReportFields(from: draft, to: existing)
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
            applyReportFields(from: draft, to: medicine)
            context.insert(medicine)
            invalidateCache()
        }
        medicine.applyDoseDefaultsIfNeeded()

        replaceSchedules(for: medicine, times: draft.doseTimes, frequency: draft.scheduleFrequency, now: now)
        logsEnsuredDay = nil
        ensureUpcomingLogs()
        save()
        notify()
        requestSync()
    }

    private func applyReportFields(from draft: OnboardingPrescriptionDraft, to medicine: MedicineRecord) {
        if !draft.reason.isEmpty { medicine.reason = draft.reason }
        if !draft.doctorName.isEmpty { medicine.doctorName = draft.doctorName }
        if !draft.doctorId.isEmpty { medicine.doctorId = draft.doctorId }
        if !draft.hospitalName.isEmpty { medicine.hospitalName = draft.hospitalName }
        if !draft.doctorNotes.isEmpty { medicine.doctorNotes = draft.doctorNotes }
        if !draft.form.isEmpty { medicine.form = draft.form }
        let parsedDose = MedicineUnits.parseDoseLabel(draft.dose)
        medicine.quantityPerDose = parsedDose.quantity
        medicine.doseUnit = parsedDose.unit.rawValue
        if let amount = Double(draft.packageAmount.replacingOccurrences(of: ",", with: ".")), amount > 0 {
            medicine.packageAmount = amount
            if let unit = MedicineUnit.parse(draft.packageUnit) ?? MedicineUnit(rawValue: draft.packageUnit) {
                medicine.packageUnit = unit.rawValue
            }
        }
        if medicine.form.isEmpty || medicine.form == MedicineForm.other.rawValue {
            medicine.form = MedicineForm.infer(from: draft.dose, medicineName: draft.medicine).rawValue
        }
    }

    func updateMedicineStock(
        id: UUID,
        stockPercent: Double? = nil,
        packageAmount: Double? = nil,
        packageUnit: MedicineUnit? = nil,
        quantityPerDose: Double? = nil,
        doseUnit: MedicineUnit? = nil,
        form: MedicineForm? = nil,
        refillRemindEnabled: Bool? = nil,
        markRefilled: Bool = false,
        doctorName: String? = nil,
        doctorId: String? = nil,
        hospitalName: String? = nil,
        doctorNotes: String? = nil,
        reason: String? = nil
    ) {
        guard let medicine = medicines().first(where: { $0.id == id }) else { return }
        if let stockPercent { medicine.stockPercent = min(100, max(0, stockPercent)) }
        if let packageAmount { medicine.packageAmount = max(0, packageAmount) }
        if let packageUnit { medicine.packageUnit = packageUnit.rawValue }
        if let quantityPerDose { medicine.quantityPerDose = max(0.01, quantityPerDose) }
        if let doseUnit { medicine.doseUnit = doseUnit.rawValue }
        if let form { medicine.form = form.rawValue }
        if let refillRemindEnabled { medicine.refillRemindEnabled = refillRemindEnabled }
        if let doctorName { medicine.doctorName = doctorName }
        if let doctorId { medicine.doctorId = doctorId }
        if let hospitalName { medicine.hospitalName = hospitalName }
        if let doctorNotes { medicine.doctorNotes = doctorNotes }
        if let reason { medicine.reason = reason }
        if markRefilled {
            medicine.stockPercent = 100
            medicine.lastRefillAt = Date()
        }
        medicine.updatedAt = Date()
        stamp(medicine)
        save()
        notify()
        requestSync()
    }

    func markLog(id: UUID, status: DoseLogStatus) {
        guard let log = allLogs().first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        let wasPending = log.status == DoseLogStatus.pending.rawValue
        log.status = status.rawValue
        log.loggedAt = Date()
        log.updatedAt = Date()
        stamp(log)
        if status == .taken, wasPending,
           let schedule = schedules().first(where: { $0.id == log.scheduleId }),
           let medicine = medicines().first(where: { $0.id == schedule.medicineId }) {
            medicine.applyDoseDefaultsIfNeeded()
            if let next = MedicineUnits.stockPercentAfterDose(
                packageAmount: medicine.packageAmount,
                packageUnit: medicine.packageMedicineUnit,
                stockPercent: medicine.stockPercent,
                quantityPerDose: medicine.quantityPerDose,
                doseUnit: medicine.doseMedicineUnit
            ) {
                medicine.stockPercent = next
                medicine.updatedAt = Date()
                stamp(medicine)
            }
        }
        save()
        notify()
        requestSync()
    }

    func completeTreatment(id: UUID) {
        guard let treatment = allTreatments().first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        // Status only — never set deletedAt. Journey report needs finished treatments + medicines.
        treatment.status = "completed"
        treatment.endDate = treatment.endDate ?? Date()
        treatment.updatedAt = Date()
        stamp(treatment)
        logsEnsuredDay = nil
        save()
        notify()
        requestSync()
    }

    /// Completes every active plan in place. Medicines, schedules, and logs stay for journey history.
    func completeAllActiveTreatments() {
        let ids = activeTreatments().map(\.id)
        for id in ids {
            completeTreatment(id: id)
        }
    }

    /// Medicines on the active plan that still have missed/pending expected doses, or a course that is not fully taken yet.
    func incompleteMedicineNamesForActivePlan() -> [String] {
        _ = revision
        ensureUpcomingLogs()
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let treatmentsById = Dictionary(uniqueKeysWithValues: activeTreatments().map { ($0.id, $0) })
        var names: [String] = []
        var seen = Set<String>()
        for medicine in medicines() {
            guard let treatment = treatmentsById[medicine.treatmentId] else { continue }
            let scheduleIds = Set(schedules(for: medicine.id).map(\.id))
            let medLogs = logs().filter { scheduleIds.contains($0.scheduleId) }
            let dueLogs = medLogs.filter { $0.scheduledAt <= now }
            let dueIncomplete = dueLogs.contains {
                $0.status == DoseLogStatus.pending.rawValue || $0.status == DoseLogStatus.skipped.rawValue
            }
            let neverFullyTaken = !dueLogs.isEmpty
                && !dueLogs.contains { $0.status == DoseLogStatus.taken.rawValue }
            let courseStillOpen = treatment.endDate.map { calendar.startOfDay(for: $0) > today } ?? false
            guard dueIncomplete || neverFullyTaken || courseStillOpen else { continue }
            let key = Self.medicineKey(medicine.name)
            guard seen.insert(key).inserted else { continue }
            names.append(medicine.name)
        }
        return names
    }

    var hasMedicationDaysSet: Bool {
        _ = revision
        let meds = surfacesPlan ? medicineSummaries() : medicineSummariesForPlanCheck()
        guard !meds.isEmpty else { return false }
        return meds.allSatisfy { summary in
            Self.endDate(fromDuration: summary.duration, start: Date(), calendar: calendar) != nil
        }
    }

    /// Ungated summaries for migration / unfinished-plan checks before `surfacesPlan` is on.
    private func medicineSummariesForPlanCheck() -> [MedicineSummary] {
        let treatmentsById = Dictionary(uniqueKeysWithValues: activeTreatments().map { ($0.id, $0) })
        return medicines().compactMap { medicine in
            guard let treatment = treatmentsById[medicine.treatmentId] else { return nil }
            let times = max(1, schedules(for: medicine.id).count)
            return MedicineSummary(
                id: medicine.id,
                treatmentId: treatment.id,
                name: medicine.name,
                doseLabel: medicine.doseLabel,
                frequency: medicine.frequency,
                duration: medicine.duration,
                timesPerDay: times,
                treatmentTitle: treatment.title,
                treatmentStatus: treatment.status,
                form: medicine.medicineForm,
                packageAmount: medicine.packageAmount,
                packageUnit: medicine.packageMedicineUnit,
                stockPercent: medicine.stockPercent,
                quantityPerDose: medicine.quantityPerDose,
                doseUnit: medicine.doseMedicineUnit,
                doctorName: medicine.doctorName,
                doctorId: medicine.doctorId,
                hospitalName: medicine.hospitalName,
                doctorNotes: medicine.doctorNotes,
                reason: medicine.reason,
                lastRefillAt: medicine.lastRefillAt,
                refillRemindEnabled: medicine.refillRemindEnabled,
                daysLeft: nil,
                scheduleTimes: schedules(for: medicine.id).map(\.timeOfDay).sorted(),
                daysOnTreatment: 1,
                missedCount: 0
            )
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

    func pruneDuplicateAndFreeCap(isSuper: Bool) {
        let cap = isSuper ? 12 : SuperLimits.freePrescriptions
        // Only active treatments fill / compete for free slots; completed history stays.
        let activeIds = Set(activeTreatments().map(\.id))
        let meds = medicines()
            .filter { activeIds.contains($0.treatmentId) }
            .sorted { $0.updatedAt < $1.updatedAt }
        var seen = Set<String>()
        var kept = 0
        let now = Date()
        var changed = false
        for med in meds {
            let cleaned = PrescriptionParser.intervalOnly(med.frequency)
            if cleaned != med.frequency {
                med.frequency = cleaned
                med.updatedAt = now
                stamp(med)
                changed = true
            }
            let key = PrescriptionParser.canonicalMedicineKey(med.name)
            let duplicate = !key.isEmpty && !seen.insert(key).inserted
            if duplicate || kept >= cap {
                removeMedicine(med, now: now)
                changed = true
            } else {
                kept += 1
            }
        }
        for treatment in activeTreatments() where medicines(for: treatment.id).isEmpty {
            treatment.deletedAt = now
            treatment.updatedAt = now
            stamp(treatment)
            changed = true
        }
        guard changed else { return }
        logsEnsuredDay = nil
        invalidateCache()
        save()
        notify()
        requestSync()
    }

    private func removeMedicine(_ medicine: MedicineRecord, now: Date) {
        medicine.deletedAt = now
        medicine.updatedAt = now
        stamp(medicine)
        var scheduleIds = Set<UUID>()
        for schedule in schedules(for: medicine.id) where schedule.deletedAt == nil {
            schedule.deletedAt = now
            schedule.updatedAt = now
            stamp(schedule)
            scheduleIds.insert(schedule.id)
        }
        for log in allLogs() where log.deletedAt == nil && scheduleIds.contains(log.scheduleId) {
            log.deletedAt = now
            log.updatedAt = now
            stamp(log)
        }
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

    /// Soft-delete every treatment/medicine/schedule/log owned by the bound user (sync pushes deletes).
    func deleteAllOwnedPlanData() {
        let now = Date()
        var changed = false
        for treatment in allTreatments() where treatment.deletedAt == nil && matchesBoundOwner(treatment.ownerId) {
            treatment.deletedAt = now
            treatment.updatedAt = now
            stamp(treatment)
            changed = true
        }
        for medicine in allMedicines() where medicine.deletedAt == nil && matchesBoundOwner(medicine.ownerId) {
            medicine.deletedAt = now
            medicine.updatedAt = now
            stamp(medicine)
            changed = true
        }
        for schedule in allSchedules() where schedule.deletedAt == nil && matchesBoundOwner(schedule.ownerId) {
            schedule.deletedAt = now
            schedule.updatedAt = now
            stamp(schedule)
            changed = true
        }
        for log in allLogs() where log.deletedAt == nil && matchesBoundOwner(log.ownerId) {
            log.deletedAt = now
            log.updatedAt = now
            stamp(log)
            changed = true
        }
        guard changed else { return }
        invalidateCache()
        logsEnsuredDay = nil
        save()
        notify()
        requestSync()
    }

    /// Remove leftover SwiftData with nil owner (simulator / pre-auth orphans).
    private func purgeUnownedOrphans() {
        let now = Date()
        var changed = false
        for treatment in allTreatments() where treatment.deletedAt == nil && treatment.ownerId == nil {
            treatment.deletedAt = now
            treatment.updatedAt = now
            changed = true
        }
        for medicine in allMedicines() where medicine.deletedAt == nil && medicine.ownerId == nil {
            medicine.deletedAt = now
            medicine.updatedAt = now
            changed = true
        }
        for schedule in allSchedules() where schedule.deletedAt == nil && schedule.ownerId == nil {
            schedule.deletedAt = now
            schedule.updatedAt = now
            changed = true
        }
        for log in allLogs() where log.deletedAt == nil && log.ownerId == nil {
            log.deletedAt = now
            log.updatedAt = now
            changed = true
        }
        guard changed else { return }
        invalidateCache()
        logsEnsuredDay = nil
        save()
    }

    private func matchesBoundOwner(_ rowOwner: UUID?) -> Bool {
        guard let ownerId else { return rowOwner == nil }
        return rowOwner == ownerId
    }

    func refillDrafts(now: Date = Date()) -> [ReminderDraft] {
        _ = revision
        guard surfacesPlan else { return [] }
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

    /// Free stock-based refill: fire ~1 day before projected empty.
    func stockRefillDrafts(now: Date = Date()) -> [ReminderDraft] {
        _ = revision
        var drafts: [ReminderDraft] = []
        for summary in medicineSummaries() where summary.refillRemindEnabled {
            guard let days = summary.daysLeft, days.isFinite, days > 0 else { continue }
            let whole = max(1, Int(days.rounded(.down)))
            guard let fireDay = calendar.date(byAdding: .day, value: whole - 1, to: calendar.startOfDay(for: now)) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: fireDay)
            comps.hour = 9
            comps.minute = 0
            guard let fire = calendar.date(from: comps), fire > now.addingTimeInterval(60) else { continue }
            drafts.append(
                ReminderDraft(
                    id: summary.id,
                    fireDate: fire,
                    medicine: summary.name,
                    doseLabel: String(format: "%.0f", days),
                    time: "",
                    kind: .stockRefill
                )
            )
        }
        return drafts
    }

    func medicineId(forLogId id: UUID) -> UUID? {
        guard let log = allLogs().first(where: { $0.id == id }),
              let schedule = schedules().first(where: { $0.id == log.scheduleId })
        else { return nil }
        return schedule.medicineId
    }

    func stockDaysLeftDraft(for medicineId: UUID, now: Date = Date()) -> ReminderDraft? {
        guard let summary = medicineSummaries().first(where: { $0.id == medicineId }),
              summary.refillRemindEnabled,
              let days = summary.daysLeft,
              days.isFinite
        else { return nil }
        return ReminderDraft(
            id: medicineId,
            fireDate: now.addingTimeInterval(2),
            medicine: summary.name,
            doseLabel: String(format: "%.0f", max(0, days.rounded())),
            time: "",
            kind: .stockDaysLeft
        )
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
        guard surfacesPlan else { return [] }
        ensureUpcomingLogs()
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        guard !activeTreatmentIds.isEmpty else { return [] }
        let dayLogs = todayLogs().sorted { $0.scheduledAt < $1.scheduledAt }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: schedules().map { ($0.id, $0) })
        var nodes: [DoseNode] = dayLogs.compactMap { log in
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId],
                  activeTreatmentIds.contains(medicine.treatmentId) else { return nil }
            return DoseNode(
                id: log.id.uuidString,
                time: schedule.timeOfDay,
                medicine: medicine.name,
                medicineId: medicine.id,
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
        guard surfacesPlan else {
            return AdherenceSnapshot(
                streakDays: 0,
                takenCount: 0,
                plannedCount: 0,
                percent: nil,
                treatmentCount: 0,
                todayTaken: 0,
                todayTotal: 0,
                hasHistory: false,
                weekTaken: 0,
                weekPlanned: 0,
                weekPercent: nil
            )
        }
        ensureUpcomingLogs()
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: schedules().map { ($0.id, $0) })
        let dayLogs = todayLogs().filter { log in
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId] else { return false }
            return activeTreatmentIds.contains(medicine.treatmentId)
        }
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
        let weekLogs = history.filter { log in
            guard log.scheduledAt >= weekStart && log.scheduledAt < weekEnd else { return false }
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId] else { return false }
            return activeTreatmentIds.contains(medicine.treatmentId)
        }
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
        guard surfacesPlan else { return [] }
        ensureUpcomingLogs()
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        guard !activeTreatmentIds.isEmpty else { return [] }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: schedules().map { ($0.id, $0) })
        let horizon = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let grace: TimeInterval = 45 * 60
        var drafts: [ReminderDraft] = []
        for log in logs() where log.status == DoseLogStatus.pending.rawValue {
            guard log.scheduledAt < horizon else { continue }
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId],
                  activeTreatmentIds.contains(medicine.treatmentId) else { continue }
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
        PrescriptionParser.canonicalMedicineKey(name)
    }

    // MARK: - Sync support

    /// Only push rows owned by the signed-in user. Never upload unowned leftover SwiftData.
    func treatmentSnapshots() -> [TreatmentSnapshot] { syncable(ownedExact(allTreatments())).map(\.snapshot) }
    func medicineSnapshots() -> [MedicineSnapshot] { syncable(ownedExact(allMedicines())).map(\.snapshot) }
    func scheduleSnapshots() -> [DoseScheduleSnapshot] { syncable(ownedExact(allSchedules())).map(\.snapshot) }
    func logSnapshots() -> [DoseLogSnapshot] { syncable(ownedExact(allLogs())).map(\.snapshot) }

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
        guard surfacesPlan else { return }
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

    /// Rows visible in the UI for the bound identity.
    /// Unowned leftover SwiftData (prior simulator tests / pre-auth orphans) must never surface as a live plan.
    private func owned<T>(_ rows: [T]) -> [T] {
        ownedExact(rows)
    }

    /// Strict owner match only. Nil `ownerId` on the store → nothing (no guest ghost plan).
    private func ownedExact<T>(_ rows: [T]) -> [T] {
        guard let ownerId else { return [] }
        return rows.filter { row in
            if let record = row as? TreatmentRecord { return record.ownerId == ownerId }
            if let record = row as? MedicineRecord { return record.ownerId == ownerId }
            if let record = row as? DoseScheduleRecord { return record.ownerId == ownerId }
            if let record = row as? DoseLogRecord { return record.ownerId == ownerId }
            if let record = row as? FeelingRecord { return record.ownerId == ownerId }
            if let record = row as? CommunityCommentRecord { return record.ownerId == ownerId }
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

    /// Backfill `profileId` on rows already owned by this user.
    /// Do **not** claim unowned leftover SwiftData — that created ghost plans for fresh accounts.
    private func stampIdentity() {
        guard let ownerId, let stampProfileId else { return }
        var changed = false
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

    static func intervalHours(from frequency: String, timesCount: Int) -> Int {
        let fallback = max(1, 24 / max(1, min(4, timesCount)))
        let raw = frequency.lowercased()
        let patterns = [
            #"cada\s+(\d+)\s*(?:h|horas?|hours?|heures?)?\b"#,
            #"every\s+(\d+)\s*(?:h|hours?)\b"#,
            #"todas as\s+(\d+)\s*(?:h|horas?)?\b"#,
            #"toutes les\s+(\d+)\s*(?:h|heures?)?\b"#,
            #"(\d+)\s*(?:hours?|horas?|heures?)\b"#,
            #"(\d+)\s*h\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: raw),
                  let hours = Int(raw[range]),
                  (1...24).contains(hours)
            else { continue }
            return hours
        }
        return fallback
    }

    static func spreadTimes(from first: String, count: Int, intervalHours: Int) -> [String] {
        let slots = max(1, min(4, count))
        let parts = first.split(separator: ":")
        let hour = parts.first.flatMap { Int($0) } ?? 8
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let start = ((hour % 24) * 60) + max(0, min(59, minute))
        let step = max(1, intervalHours) * 60
        return (0..<slots).map { index in
            let total = (start + index * step) % (24 * 60)
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
    }

    static func defaultTimes(count: Int) -> [String] {
        spreadTimes(from: "08:00", count: count, intervalHours: intervalHours(from: "", timesCount: count))
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
