import Foundation
import SwiftData
import CoreData

struct AdherenceSnapshot: Equatable, Sendable {
    var streakDays: Int
    var longestStreakDays: Int
    var takenCount: Int
    var takenLateCount: Int
    var missedCount: Int
    var plannedCount: Int
    var percent: Int?
    var treatmentCount: Int
    var todayTaken: Int
    var todayTotal: Int
    var todayMissedCount: Int
    var hasHistory: Bool
    var weekTaken: Int
    var weekPlanned: Int
    var weekPercent: Int?
}

struct ReminderDraft: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case dose
        case confirm
        case missed
        case nudge5
        case nudge30
        case advance
        case refill
        case stockRefill
        case stockDaysLeft

        var routesDefaultTapToHomeDose: Bool {
            switch self {
            case .dose, .nudge5, .nudge30, .missed, .confirm, .advance:
                true
            case .refill, .stockRefill, .stockDaysLeft:
                false
            }
        }
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
        case .confirm: "checkmed.confirm.\(id.uuidString)"
        case .missed: "checkmed.missed.\(id.uuidString)"
        case .nudge5: "checkmed.nudge5.\(id.uuidString)"
        case .nudge30: "checkmed.nudge30.\(id.uuidString)"
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
    /// `TreatmentRecord.status` (`active` / `completed`). Display-only; not end-date inference.
    var treatmentStatus: String
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
    /// Bookkeeping only — must not invalidate SwiftUI. Writing these from a View
    /// getter (Home adherence / today nodes) used to loop the Dashboard.
    @ObservationIgnored private var cachedTreatments: [TreatmentRecord]?
    @ObservationIgnored private var cachedMedicines: [MedicineRecord]?
    @ObservationIgnored private var cachedSchedules: [DoseScheduleRecord]?
    @ObservationIgnored private var cachedLogs: [DoseLogRecord]?
    @ObservationIgnored private var cachedAdherence: AdherenceSnapshot?
    @ObservationIgnored private var cachedAdherenceRevision = -1
    @ObservationIgnored private var cachedAdherenceDay: Date?
    @ObservationIgnored private var cachedWeekly: DoseLoop.WeeklyMedicationProgressSnapshot?
    @ObservationIgnored private var cachedWeeklyRevision = -1
    @ObservationIgnored private var cachedWeeklyDay: Date?
    @ObservationIgnored private var lastChallengeDiag: String?
    @ObservationIgnored private var lastWeeklyDiag: String?
    @ObservationIgnored private var lastStreakWindowDiag: String?
    @ObservationIgnored private var logsEnsuredDay: Date?
    @ObservationIgnored private var logsEnsuredSignature: Int?
    @ObservationIgnored private var suppressNotify = false
    private(set) var revision = 0
    /// When false, Home / reminders / summaries hide plan rows even if SwiftData still has them.
    private(set) var surfacesPlan = false

    /// Bound SwiftUI store. Unbound `persistDoseAction` delegates reward follow-on here.
    @ObservationIgnored
    private static weak var liveStore: CheckMedStore?

    private struct PendingCanonicalDoseReward {
        var logId: UUID
        var previous: DoseLogStatus
        var next: DoseLogStatus
        var now: Date
    }

    @ObservationIgnored
    private static var pendingCanonicalDoseRewards: [PendingCanonicalDoseReward] = []

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
            RewardGrant.self,
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
        NotificationCenter.default.addObserver(
            forName: Notification.Name.NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { _ in
            FreezeDiag.log("SWIFTDATA AUTOSAVE/DIDSAVE NSManagedObjectContextDidSave")
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name.NSManagedObjectContextWillSave,
            object: nil,
            queue: .main
        ) { _ in
            FreezeDiag.log("SWIFTDATA WILLSAVE NSManagedObjectContextWillSave")
        }
        Self.liveStore = self
        flushPendingCanonicalDoseRewards()
    }

    func bindIdentity(ownerId: UUID?, profileId: UUID?) {
        let identityChanged = ownerId != self.ownerId
        if !identityChanged,
           ownerId != nil,
           stampProfileId != nil,
           profileId == nil || profileId == stampProfileId {
            return
        }
        let previousStamp = stampProfileId
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
        if let previousStamp, let profileId, previousStamp != profileId {
            adoptProfile(from: previousStamp, to: profileId)
        }
        stampIdentity()
        purgeUnownedOrphans()
        refreshDoseLogsForDisplay()
        notify()
    }

    /// Align Home visibility with a loaded plan. Never delete rows because auth/sync
    /// is late, names look like a demo, or UserDefaults flags were cleared on sign-out.
    @discardableResult
    func reconcileUnconfirmedMedicationPlan(session: SessionStore) -> Bool {
        let owner = ownerId
        let hasPlan = hasExistingTreatments
        if session.hasConfirmedMedicationPlan || (session.hasCompletedOnboarding && hasPlan) {
            if hasPlan { session.markMedicationPlanConfirmed() }
            // Confirmed flags must not surface an empty Home. Only real treatments.
            setSurfacesPlan(hasPlan)
            if !session.didPurgeUnconfirmedPlans(ownerId: owner) {
                session.markDidPurgeUnconfirmedPlans(ownerId: owner)
            }
            return false
        }

        // Keep local/sync rows. Hide Home only for a true mid-setup plan.
        setSurfacesPlan(false)
        return false
    }

    func setActiveScope(profileId: UUID?, includeUnscoped: Bool) {
        let changed = profileId != scopeProfileId || includeUnscoped != self.includeUnscoped
        scopeProfileId = profileId
        self.includeUnscoped = includeUnscoped
        guard changed else { return }
        logsEnsuredDay = nil
        invalidateCache()
        refreshDoseLogsForDisplay()
        notify()
    }

    func setTimeZone(_ timeZone: TimeZone) {
        guard calendar.timeZone.identifier != timeZone.identifier else { return }
        var next = Calendar(identifier: .gregorian)
        next.timeZone = timeZone
        calendar = next
        logsEnsuredDay = nil
        refreshDoseLogsForDisplay()
        notify()
    }

    func philPlanStatus() -> PhilPlanStatus {
        guard let ownerId else { return .loading }
        let defaults = UserDefaults.standard.string(forKey: Self.philPlanDefaultsKey(ownerId))
        if let defaults, let status = PhilPlanStatus(rawValue: defaults) {
            return status
        }
        if let keychain = ProfileSetupKeychain.philPlanStatus(for: ownerId),
           let status = PhilPlanStatus(rawValue: keychain) {
            return status
        }
        return hasExistingTreatments ? .active : .loading
    }

    func setPhilPlanStatus(_ status: PhilPlanStatus) {
        guard let ownerId else { return }
        UserDefaults.standard.set(status.rawValue, forKey: Self.philPlanDefaultsKey(ownerId))
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.philPlanUpdatedKey(ownerId))
        ProfileSetupKeychain.persistPhilPlanStatus(status.rawValue, userId: ownerId)
        LaunchLog.plan("status=\(status.rawValue) owner=\(ownerId.uuidString)")
    }

    func applyRemotePhilPlan(status raw: String, ownerId: UUID, updatedAt: Date) {
        guard let status = PhilPlanStatus(rawValue: raw), status.planExists || status == .error else { return }
        let localUpdated = UserDefaults.standard.double(forKey: Self.philPlanUpdatedKey(ownerId))
        if localUpdated > updatedAt.timeIntervalSince1970 { return }
        setPhilPlanStatus(status)
    }

    func philPlanSnapshot() -> (status: String, updatedAt: Date)? {
        guard let ownerId else { return nil }
        guard let raw = UserDefaults.standard.string(forKey: Self.philPlanDefaultsKey(ownerId)) else { return nil }
        let updated = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.philPlanUpdatedKey(ownerId)))
        return (raw, updated)
    }

    private static func philPlanDefaultsKey(_ ownerId: UUID) -> String {
        "checkmed.philPlanStatus.\(ownerId.uuidString)"
    }

    private static func philPlanUpdatedKey(_ ownerId: UUID) -> String {
        "checkmed.philPlanUpdated.\(ownerId.uuidString)"
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
        FreezeDiag.context("activeMedicineCount BEFORE summaries", hasChanges: context.hasChanges)
        let count = medicineSummaries().count
        FreezeDiag.context("activeMedicineCount AFTER summaries", hasChanges: context.hasChanges)
        return count
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
        var refillDataComplete: Bool
    }

    func medicineSummaries() -> [MedicineSummary] {
        summaries(treatments: activeTreatments(), requireSurfacesPlan: true)
    }

    /// Report reads the same medicine/treatment rows as Home / Journey / Plan.
    /// Ungated from `surfacesPlan` so a saved Rx is visible mid post-journey.
    /// Includes finished treatments (history) without creating extra active slots.
    func reportMedicineSummaries() -> [MedicineSummary] {
        ReportPerf.measure("store.reportMedicineSummaries") {
            summaries(treatments: treatments(), requireSurfacesPlan: false, applyDoseDefaults: false)
        }
    }

    func reportCurrentMedicines() -> [MedicineSummary] {
        ReportPerf.measure("store.reportCurrentMedicines") {
            reportMedicineSummaries().filter { $0.treatmentStatus == "active" }
        }
    }

    struct PrescriptionHistoryItem: Identifiable {
        var id: UUID
        var title: String
        var date: Date
        var doctorName: String
        var medicines: [String]
        var isActive: Bool
    }

    func reportPrescriptionHistory() -> [PrescriptionHistoryItem] {
        ReportPerf.measure("store.reportPrescriptionHistory") {
        _ = revision
        return treatments().compactMap { treatment in
            let meds = medicines(for: treatment.id)
            guard !meds.isEmpty else { return nil }
            let doctors = meds.map(\.doctorName).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return PrescriptionHistoryItem(
                id: treatment.id,
                title: treatment.title,
                date: treatment.startDate,
                doctorName: doctors.first ?? "",
                medicines: meds.map(\.name),
                isActive: treatment.status == "active"
            )
        }
        .sorted { $0.date > $1.date }
        }
    }

    struct PrescriptionSourceItem: Identifiable {
        var id: UUID
        var title: String
        var date: Date
        var url: URL
        var isPDF: Bool
    }

    func reportPrescriptionSources() -> [PrescriptionSourceItem] {
        ReportPerf.measure("store.reportPrescriptionSources") {
        _ = revision
        return treatments().compactMap { treatment in
            guard let url = PrescriptionSourceArchive.url(for: treatment.id) else { return nil }
            return PrescriptionSourceItem(
                id: treatment.id,
                title: treatment.title,
                date: treatment.startDate,
                url: url,
                isPDF: url.pathExtension.lowercased() == "pdf"
            )
        }
        .sorted { $0.date > $1.date }
        }
    }

    func archiveImportedSource(_ pending: PendingPrescriptionImport, treatmentId: UUID) {
        PrescriptionSourceArchive.save(pending, treatmentId: treatmentId)
    }

    private func summaries(
        treatments treatmentList: [TreatmentRecord],
        requireSurfacesPlan: Bool,
        applyDoseDefaults: Bool = true
    ) -> [MedicineSummary] {
        _ = revision
        if requireSurfacesPlan, !surfacesPlan { return [] }
        let treatmentsById = Dictionary(uniqueKeysWithValues: treatmentList.map { ($0.id, $0) })
        let now = Date()
        return medicines().compactMap { medicine in
            guard let treatment = treatmentsById[medicine.treatmentId] else { return nil }
            if applyDoseDefaults {
                medicine.applyDoseDefaultsIfNeeded()
            }
            let medSchedules = schedules(for: medicine.id)
            let times = max(1, medSchedules.count)
            let scheduleTimes = medSchedules.map(\.timeOfDay).sorted()
            let form = applyDoseDefaults ? medicine.medicineForm : Self.reportDisplayForm(medicine)
            let quantityPerDose = applyDoseDefaults ? medicine.quantityPerDose : Self.reportDisplayQuantity(medicine)
            let doseUnit = applyDoseDefaults ? medicine.doseMedicineUnit : Self.reportDisplayDoseUnit(medicine)
            let refillComplete = MedicineUnits.hasCompleteRefillData(
                packageAmount: medicine.packageAmount,
                quantityPerDose: quantityPerDose,
                packageUnit: medicine.packageMedicineUnit,
                doseUnit: doseUnit
            )
            let days = refillComplete ? MedicineUnits.daysLeft(
                packageAmount: medicine.packageAmount,
                packageUnit: medicine.packageMedicineUnit,
                stockPercent: medicine.stockPercent,
                quantityPerDose: quantityPerDose,
                doseUnit: doseUnit,
                timesPerDay: times
            ) : nil
            let scheduleIds = Set(medSchedules.map(\.id))
            let medLogs = allLogs().filter { scheduleIds.contains($0.scheduleId) && $0.deletedAt == nil }
            let missed = medLogs.filter {
                $0.scheduledAt <= now && DoseLogStatus(rawValue: $0.status)?.isMissedLike == true
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
                form: form,
                packageAmount: medicine.packageAmount,
                packageUnit: medicine.packageMedicineUnit,
                stockPercent: medicine.stockPercent,
                quantityPerDose: quantityPerDose,
                doseUnit: doseUnit,
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
                missedCount: missed,
                refillDataComplete: refillComplete
            )
        }
    }

    /// Read-only display inference. Does not write `form` / dose unit onto the model.
    private static func reportDisplayForm(_ medicine: MedicineRecord) -> MedicineForm {
        if !medicine.form.isEmpty, medicine.form != MedicineForm.other.rawValue {
            return medicine.medicineForm
        }
        return MedicineForm.infer(from: medicine.doseLabel, medicineName: medicine.name)
    }

    private static func reportDisplayQuantity(_ medicine: MedicineRecord) -> Double {
        if medicine.quantityPerDose > 0 { return medicine.quantityPerDose }
        return MedicineUnits.parseDoseLabel(medicine.doseLabel).quantity
    }

    private static func reportDisplayDoseUnit(_ medicine: MedicineRecord) -> MedicineUnit {
        if !medicine.doseUnit.isEmpty, medicine.doseUnit != MedicineUnit.other.rawValue {
            return medicine.doseMedicineUnit
        }
        return MedicineUnits.parseDoseLabel(medicine.doseLabel).unit
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
    func seedFromDraft(_ draft: OnboardingPrescriptionDraft, ownerId: UUID?, profileId: UUID?) -> UUID? {
        seedFromDrafts([draft], ownerId: ownerId, profileId: profileId)
    }

    @discardableResult
    func seedFromDrafts(_ drafts: [OnboardingPrescriptionDraft], ownerId: UUID?, profileId: UUID?) -> UUID? {
        persistDrafts(drafts, ownerId: ownerId, profileId: profileId, replacePlan: true)
    }

    /// Later adds from Home: append onto the active treatment when one exists.
    @discardableResult
    func addFromDraft(_ draft: OnboardingPrescriptionDraft, ownerId: UUID?, profileId: UUID?) -> UUID? {
        addFromDrafts([draft], ownerId: ownerId, profileId: profileId)
    }

    @discardableResult
    func addFromDrafts(_ drafts: [OnboardingPrescriptionDraft], ownerId: UUID?, profileId: UUID?) -> UUID? {
        persistDrafts(drafts, ownerId: ownerId, profileId: profileId, replacePlan: false)
    }

    /// Move leftover on-device rows onto the signed-in account so Home still shows the plan.
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

    /// Pre-profile SwiftData used a device profile UUID. After the real
    /// `profiles.id` arrives, rewrite so Home scope and Supabase FK both match.
    func adoptProfile(from previousProfileId: UUID, to newProfileId: UUID) {
        guard previousProfileId != newProfileId else { return }
        let now = Date()
        var changed = false
        func claim(_ pid: UUID?) -> Bool { pid == nil || pid == previousProfileId }
        for treatment in allTreatments() where matchesBoundOwner(treatment.ownerId) && claim(treatment.profileId) {
            treatment.profileId = newProfileId
            treatment.updatedAt = now
            changed = true
        }
        for medicine in allMedicines() where matchesBoundOwner(medicine.ownerId) && claim(medicine.profileId) {
            medicine.profileId = newProfileId
            medicine.updatedAt = now
            changed = true
        }
        for schedule in allSchedules() where matchesBoundOwner(schedule.ownerId) && claim(schedule.profileId) {
            schedule.profileId = newProfileId
            schedule.updatedAt = now
            changed = true
        }
        for log in allLogs() where matchesBoundOwner(log.ownerId) && claim(log.profileId) {
            log.profileId = newProfileId
            log.updatedAt = now
            changed = true
        }
        if stampProfileId == nil || stampProfileId == previousProfileId {
            stampProfileId = newProfileId
        }
        if scopeProfileId == nil || scopeProfileId == previousProfileId {
            scopeProfileId = newProfileId
        }
        guard changed else { return }
        invalidateCache()
        logsEnsuredDay = nil
        save()
        notify()
        #if DEBUG
        print("[CheckMed] adoptProfile \(previousProfileId) → \(newProfileId)")
        #endif
    }

    @discardableResult
    private func persistDrafts(
        _ drafts: [OnboardingPrescriptionDraft],
        ownerId: UUID?,
        profileId: UUID?,
        replacePlan: Bool
    ) -> UUID? {
        let named = drafts.filter(\.hasMedicineName)
        ScanLog.confirmed(named)
        guard let ownerId else {
            #if DEBUG
            print("[CheckMed] persistDrafts aborted: missing ownerId (named=\(named.count))")
            #endif
            return nil
        }
        guard let first = named.first else {
            #if DEBUG
            print("[CheckMed] persistDrafts aborted: no named medicines")
            #endif
            return nil
        }
        // Confirmed prescriptions must surface immediately (Home + logs + alarms).
        setSurfacesPlan(true)
        guard let treatmentId = saveDraft(
            first,
            ownerId: ownerId,
            profileId: profileId,
            replacingFirst: replacePlan,
            ontoTreatment: replacePlan ? nil : activeTreatments().first
        ) else {
            return nil
        }
        let plan = allTreatments().first(where: { $0.id == treatmentId && $0.deletedAt == nil })
        for draft in named.dropFirst() {
            _ = saveDraft(
                draft,
                ownerId: ownerId,
                profileId: profileId,
                replacingFirst: false,
                ontoTreatment: plan
            )
        }
        let saved = medicines().count
        ScanLog.saved(named)
        #if DEBUG
        print("[CheckMed] persistDrafts ok replace=\(replacePlan) seeded=\(named.count) stored=\(saved) surfacesPlan=\(surfacesPlan) treatmentId=\(treatmentId.uuidString)")
        #endif
        if saved > 0 {
            ReminderScheduler.shared.reschedule(force: true)
        }
        return saved > 0 ? treatmentId : nil
    }

    @discardableResult
    private func saveDraft(
        _ draft: OnboardingPrescriptionDraft,
        ownerId: UUID?,
        profileId: UUID?,
        replacingFirst: Bool,
        ontoTreatment: TreatmentRecord? = nil
    ) -> UUID? {
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
        guard !medicineName.isEmpty else { return nil }
        guard self.ownerId != nil else {
            #if DEBUG
            print("[CheckMed] saveDraft aborted: store ownerId still nil for \(medicineName)")
            #endif
            return nil
        }

        let start = ScanPipeline.resolvedTreatmentStart(draft: draft, now: now, calendar: calendar)
        draft.duration = ScanPipeline.durationAlignedToTreatmentStart(
            draft.duration,
            treatmentStart: start,
            calendar: calendar
        )
        let end = Self.endDate(fromDuration: draft.duration, start: start, calendar: calendar)
        ScanLog.med(
            "name=\(medicineName) prescriptionDate=\(draft.prescriptionDate.map { ScanPipeline.iso($0, calendar: calendar) } ?? "nil") "
            + "scanDate=\(ScanPipeline.iso(draft.scanDate, calendar: calendar)) "
            + "treatmentStartDate=\(ScanPipeline.iso(start, calendar: calendar)) "
            + "treatmentEndDate=\(end.map { ScanPipeline.iso($0, calendar: calendar) } ?? "nil")"
        )
        let treatment: TreatmentRecord
        if let ontoTreatment {
            treatment = ontoTreatment
        } else if replacingFirst, let existing = activeTreatments().first {
            existing.title = medicineName
            existing.updatedAt = now
            existing.deletedAt = nil
            existing.status = "active"
            existing.startDate = start
            existing.endDate = end
            stamp(existing)
            treatment = existing
        } else {
            treatment = TreatmentRecord(
                ownerId: self.ownerId,
                profileId: writeProfileId,
                title: medicineName,
                startDate: start,
                endDate: end,
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
        save()
        ensureUpcomingLogs()
        notify()
        requestSync()
        return treatment.id
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

    func updateMedicineDetails(
        id: UUID,
        name: String? = nil,
        doseLabel: String? = nil,
        frequency: String? = nil,
        duration: String? = nil,
        doctorName: String? = nil,
        doctorId: String? = nil,
        hospitalName: String? = nil,
        doctorNotes: String? = nil,
        reason: String? = nil
    ) {
        guard let medicine = medicines().first(where: { $0.id == id }) else { return }
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { medicine.name = trimmed }
        }
        if let doseLabel {
            let trimmed = doseLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                medicine.doseLabel = trimmed
                let parsed = MedicineUnits.parseDoseLabel(trimmed)
                medicine.quantityPerDose = parsed.quantity
                medicine.doseUnit = parsed.unit.rawValue
            }
        }
        if let frequency {
            medicine.frequency = PrescriptionParser.intervalOnly(frequency)
        }
        if let duration {
            medicine.duration = duration.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let doctorName { medicine.doctorName = doctorName }
        if let doctorId { medicine.doctorId = doctorId }
        if let hospitalName { medicine.hospitalName = hospitalName }
        if let doctorNotes { medicine.doctorNotes = doctorNotes }
        if let reason { medicine.reason = reason }
        medicine.updatedAt = Date()
        stamp(medicine)
        if let treatment = treatments().first(where: { $0.id == medicine.treatmentId }) {
            treatment.updatedAt = Date()
            stamp(treatment)
        }
        save()
        notify()
        requestSync()
    }

    func markLog(id: UUID, status: DoseLogStatus, now: Date = Date()) {
        applyDoseAction(id: id, next: status, now: now)
    }

    func applyDoseAction(id: UUID, action: DoseLoopAction, now: Date = Date()) {
        guard let log = allLogs().first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        let previous = DoseLogStatus(rawValue: log.status) ?? .pending
        let next = DoseLoop.apply(
            action,
            current: previous,
            scheduledAt: log.scheduledAt,
            now: now,
            grace: ReminderPreferences.confirmationGraceInterval
        )
        applyDoseAction(id: id, next: next, now: now)
    }

    func confirmDoseTaken(id: UUID, now: Date = Date()) {
        #if DEBUG
        print("[PHASE4A-REGRESSION] confirmDoseTaken \(id.uuidString)")
        #endif
        applyDoseAction(id: id, action: .confirmTaken, now: now)
    }

    private func applyDoseAction(id: UUID, next: DoseLogStatus, now: Date) {
        guard let log = allLogs().first(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        let previous = DoseLogStatus(rawValue: log.status) ?? .pending
        if previous.isConfirmedTaken, !next.isConfirmedTaken { return }
        if previous == next, next != .snoozed { return }
        let revisionBefore = revision
        #if DEBUG
        if previous.isMissedLike || previous == .pendingConfirmation {
            print(
                "[MISSED-DIAG] CONFIRM MISSED doseID=\(log.id.uuidString) oldStatus=\(previous.rawValue) newStatus=\(next.rawValue) takenAt=\(ScanPipeline.iso(now, calendar: calendar)) revisionBefore=\(revisionBefore)"
            )
            if next.isConfirmedTaken {
                print(
                    "[CHALLENGE-DIAG] LATE TAKE doseID=\(log.id.uuidString) oldStatus=\(previous.rawValue) newStatus=\(next.rawValue) scheduledAt=\(ScanPipeline.iso(log.scheduledAt, calendar: calendar)) takenAt=\(ScanPipeline.iso(now, calendar: calendar))"
                )
            }
        }
        #endif
        FreezeDiag.log("SWIFTDATA WRITE START source=applyDoseAction")
        FreezeDiag.log(
            "SWIFTDATA WRITE object=\(log.id) kind=update medicine=- oldStatus=\(previous.rawValue) newStatus=\(next.rawValue) scheduledAt=\(log.scheduledAt)"
        )
        log.status = next.rawValue
        log.loggedAt = now
        log.updatedAt = now
        stamp(log)
        FreezeDiag.log("SWIFTDATA WRITE END source=applyDoseAction")
        if DoseLoop.shouldConsumeStock(from: previous, to: next),
           let schedule = schedules().first(where: { $0.id == log.scheduleId }),
           let medicine = medicines().first(where: { $0.id == schedule.medicineId }) {
            medicine.applyDoseDefaultsIfNeeded()
            if MedicineUnits.hasCompleteRefillData(
                packageAmount: medicine.packageAmount,
                quantityPerDose: medicine.quantityPerDose,
                packageUnit: medicine.packageMedicineUnit,
                doseUnit: medicine.doseMedicineUnit
            ), let stock = MedicineUnits.stockPercentAfterDose(
                packageAmount: medicine.packageAmount,
                packageUnit: medicine.packageMedicineUnit,
                stockPercent: medicine.stockPercent,
                quantityPerDose: medicine.quantityPerDose,
                doseUnit: medicine.doseMedicineUnit
            ) {
                medicine.stockPercent = stock
                medicine.updatedAt = now
                stamp(medicine)
            }
        }
        save()
        recordRewardsAfterDoseConfirm(log: log, previous: previous, next: next, now: now)
        notify()
        requestSync()
        #if DEBUG
        if previous.isMissedLike || previous == .pendingConfirmation || next.isConfirmedTaken {
            let status = DoseLogStatus(rawValue: log.status) ?? next
            let inSummary = unresolvedDosesMatchingSummaryRules(now: now).contains { $0.id == log.id }
            print(
                "[MISSED-DIAG] AFTER CONFIRM doseID=\(log.id.uuidString) status=\(status.rawValue) unresolved=\(inSummary) taken=\(status == .taken) takenLate=\(status == .takenLate) inSummary=\(inSummary) revisionAfter=\(revision) revisionBefore=\(revisionBefore)"
            )
        }
        #endif
    }

    private func recordRewardsAfterDoseConfirm(
        log: DoseLogRecord,
        previous: DoseLogStatus,
        next: DoseLogStatus,
        now: Date
    ) {
        guard next.isConfirmedTaken, !previous.isConfirmedTaken else { return }
        guard let owner = log.ownerId ?? ownerId, let profile = log.profileId ?? writeProfileId else { return }
        let counts = todayChallengeCounts(now: now)
        let streak = streakFromCanonical(now: now, todayCounts: counts)
        RewardEngine.applyDoseRewards(
            context: context,
            facts: RewardEngine.DoseFacts(
                logId: log.id,
                ownerId: owner,
                profileId: profile,
                previous: previous,
                next: next,
                dayIsComplete: counts.isComplete,
                currentStreak: streak.currentDays,
                now: now
            ),
            calendar: calendar
        )
    }

    /// Same follow-on as Home confirm. Call after the DoseLog row is already saved.
    private func applyCanonicalDoseRewards(
        logId: UUID,
        previous: DoseLogStatus,
        next: DoseLogStatus,
        now: Date
    ) {
        invalidateCache()
        guard let log = allLogs().first(where: { $0.id == logId && $0.deletedAt == nil }) else { return }
        recordRewardsAfterDoseConfirm(log: log, previous: previous, next: next, now: now)
    }

    private static func enqueueOrApplyCanonicalDoseRewards(
        logId: UUID,
        previous: DoseLogStatus,
        next: DoseLogStatus,
        now: Date
    ) {
        if let live = liveStore {
            live.applyCanonicalDoseRewards(logId: logId, previous: previous, next: next, now: now)
            return
        }
        pendingCanonicalDoseRewards.append(
            PendingCanonicalDoseReward(logId: logId, previous: previous, next: next, now: now)
        )
    }

    private func flushPendingCanonicalDoseRewards() {
        let pending = Self.pendingCanonicalDoseRewards
        Self.pendingCanonicalDoseRewards = []
        for item in pending {
            applyCanonicalDoseRewards(
                logId: item.logId,
                previous: item.previous,
                next: item.next,
                now: item.now
            )
        }
    }

    /// Create upcoming logs + expire overdue ones. Call from lifecycle / sync /
    /// alarm rebuild — never from a SwiftUI View body getter.
    func refreshDoseLogsForDisplay() {
        FreezeDiag.context("refreshDoseLogs START", hasChanges: context.hasChanges)
        let t0 = Date()
        let previous = suppressNotify
        suppressNotify = true
        // Drop the in-memory log snapshot so foreground restore reads SwiftData
        // before reconcile / missed-summary. Never call from View.body.
        invalidateCache()
        ensureUpcomingLogs()
        reconcileExpiredDoseLogs()
        suppressNotify = previous
        FreezeDiag.context(
            String(format: "refreshDoseLogs END %.0fms", Date().timeIntervalSince(t0) * 1000),
            hasChanges: context.hasChanges
        )
    }

    func reconcileExpiredDoseLogs(now: Date = Date()) {
        FreezeDiag.context("reconcileExpiredDoseLogs START", hasChanges: context.hasChanges)
        #if DEBUG
        print("[NEW-DOSE-DIAG] reconcile START now=\(ScanPipeline.iso(now, calendar: calendar))")
        #endif
        let grace = ReminderPreferences.confirmationGraceInterval
        let snooze = ReminderPreferences.snoozeInterval
        let window = now.addingTimeInterval(-36 * 60 * 60)
        #if DEBUG
        let schedulesById = Dictionary(uniqueKeysWithValues: allSchedules().map { ($0.id, $0) })
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let treatmentsById = Dictionary(uniqueKeysWithValues: treatments().map { ($0.id, $0) })
        #endif
        var changed = 0
        for log in allLogs() where log.deletedAt == nil {
            guard changed < 24 else { break }
            guard log.scheduledAt >= window else { continue }
            let status = DoseLogStatus(rawValue: log.status) ?? .pending
            guard DoseLoop.shouldMarkMissed(
                status: status,
                scheduledAt: log.scheduledAt,
                loggedAt: log.loggedAt,
                now: now,
                grace: grace,
                snooze: snooze
            ) else { continue }
            FreezeDiag.log("SWIFTDATA WRITE START source=reconcileExpiredDoseLogs")
            FreezeDiag.log(
                "SWIFTDATA WRITE object=\(log.id) kind=update medicine=- oldStatus=\(status.rawValue) newStatus=missed scheduledAt=\(log.scheduledAt)"
            )
            #if DEBUG
            if status == .pending {
                let schedule = schedulesById[log.scheduleId]
                let medicine = schedule.flatMap { medicinesById[$0.medicineId] }
                let treatmentStart = medicine.flatMap { treatmentsById[$0.treatmentId]?.startDate }
                print(
                    "[NEW-DOSE-DIAG] PENDING -> MISSED treatmentID=\(medicine?.treatmentId.uuidString ?? "nil") "
                    + "medicineID=\(medicine?.id.uuidString ?? "nil") scheduledAt=\(ScanPipeline.iso(log.scheduledAt, calendar: calendar)) "
                    + "now=\(ScanPipeline.iso(now, calendar: calendar)) "
                    + "treatmentStart=\(treatmentStart.map { ScanPipeline.iso($0, calendar: calendar) } ?? "nil") "
                    + "createdAt=\(ScanPipeline.iso(log.updatedAt, calendar: calendar))"
                )
            }
            #endif
            log.status = DoseLogStatus.missed.rawValue
            log.loggedAt = log.loggedAt ?? now
            log.updatedAt = now
            stamp(log)
            FreezeDiag.log("SWIFTDATA WRITE END source=reconcileExpiredDoseLogs")
            changed += 1
        }
        if changed == 0 {
            FreezeDiag.context("reconcileExpiredDoseLogs END no writes", hasChanges: context.hasChanges)
            #if DEBUG
            print("[NEW-DOSE-DIAG] reconcile END changed=0")
            #endif
            return
        }
        save()
        if !suppressNotify {
            notify()
            requestSync()
        }
        FreezeDiag.context("reconcileExpiredDoseLogs END changed=\(changed)", hasChanges: context.hasChanges)
        #if DEBUG
        print("[NEW-DOSE-DIAG] reconcile END changed=\(changed)")
        #endif
    }

    struct UnresolvedDose: Identifiable, Equatable {
        var id: UUID
        var medicine: String
        var doseLabel: String
        var time: String
        var scheduledAt: Date
        var status: DoseLogStatus
        var medicineId: UUID
        var treatmentId: UUID
    }

    func unresolvedDosesForSummary(now: Date = Date()) -> [UnresolvedDose] {
        _ = revision
        return unresolvedDosesMatchingSummaryRules(now: now)
            .filter { !MissedDoseAcknowledgement.contains($0.id) }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .prefix(8)
            .map { $0 }
    }

    /// Window/status matches before acknowledgement and the max-8 cap. Diagnostic only.
    func missedSummaryDiagnosticCounts(now: Date = Date()) -> (unresolved: Int, acknowledged: Int, eligible: Int) {
        let matching = unresolvedDosesMatchingSummaryRules(now: now)
        let acknowledged = matching.filter { MissedDoseAcknowledgement.contains($0.id) }.count
        let eligible = unresolvedDosesForSummary(now: now).count
        return (matching.count, acknowledged, eligible)
    }

    /// Same status / 36h / active-treatment rules as the summary sheet, including acknowledged logs.
    private func unresolvedDosesMatchingSummaryRules(now: Date) -> [UnresolvedDose] {
        guard surfacesPlan else { return [] }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: allSchedules().map { ($0.id, $0) })
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        let liveLogs = logs()
        let probes: [DoseLoop.DoseSummaryProbe] = liveLogs.compactMap { log in
            guard let schedule = schedulesById[log.scheduleId] else { return nil }
            return DoseLoop.DoseSummaryProbe(
                id: log.id,
                scheduleId: log.scheduleId,
                medicineId: schedule.medicineId,
                scheduledAt: log.scheduledAt,
                status: DoseLogStatus(rawValue: log.status) ?? .pending
            )
        }
        #if DEBUG
        for group in DoseLoop.duplicateSlotGroups(logs: probes, calendar: calendar) {
            let statuses = group.map(\.status.rawValue).joined(separator: ",")
            let ids = group.map(\.id.uuidString).joined(separator: ",")
            print(
                "[MISSED-DIAG] DUPLICATE SLOT medicineID=\(group[0].medicineId.uuidString) scheduledAt=\(ScanPipeline.iso(group[0].scheduledAt, calendar: calendar)) doseIDs=\(ids) statuses=\(statuses)"
            )
        }
        #endif
        let unresolvedIds = DoseLoop.unresolvedIdsForMissedSummary(
            logs: probes,
            now: now,
            calendar: calendar
        )
        let window = now.addingTimeInterval(-36 * 60 * 60)
        return liveLogs.compactMap { log in
            let status = DoseLogStatus(rawValue: log.status) ?? .pending
            let acknowledged = MissedDoseAcknowledgement.contains(log.id)
            let included = unresolvedIds.contains(log.id)
            let schedule = schedulesById[log.scheduleId]
            let medicine = schedule.flatMap { medicinesById[$0.medicineId] }
            #if DEBUG
            let inWindow = log.scheduledAt >= window
            let looksUnresolved = DoseLoop.qualifiesForMissedSummary(status: status, scheduledAt: log.scheduledAt, now: now)
            if included || (inWindow && looksUnresolved) {
                let reason: String
                if status.isConfirmedTaken {
                    reason = "canonical dose already confirmed"
                } else if !inWindow {
                    reason = "outside 36h window"
                } else if !looksUnresolved {
                    reason = "canonical status is not unresolved"
                } else if !included {
                    reason = "sibling slot already confirmed taken"
                } else {
                    reason = "canonical state still unresolved"
                }
                print(
                    "[MISSED-DIAG] doseID=\(log.id.uuidString) medicineID=\(medicine?.id.uuidString ?? "nil") scheduledAt=\(ScanPipeline.iso(log.scheduledAt, calendar: calendar)) status=\(status.rawValue) takenAt=\(log.loggedAt.map { ScanPipeline.iso($0, calendar: calendar) } ?? "nil") acknowledged=\(acknowledged) isUnresolved=\(included) isTaken=\(status == .taken) isTakenLate=\(status == .takenLate) treatmentID=\(medicine?.treatmentId.uuidString ?? "nil") source=unresolvedDosesMatchingSummaryRules revision=\(revision) reason=\(reason)"
                )
            }
            #endif
            guard included else { return nil }
            guard let schedule,
                  let medicine,
                  activeTreatmentIds.contains(medicine.treatmentId) else { return nil }
            if let treatment = activeTreatments().first(where: { $0.id == medicine.treatmentId }),
               log.scheduledAt < treatment.startDate,
               status != .pendingConfirmation {
                // Historical / pre-start slots are not a miss. A dose that
                // became overdue after treatment start still qualifies today.
                return nil
            }
            return UnresolvedDose(
                id: log.id,
                medicine: medicine.name,
                doseLabel: medicine.doseLabel,
                time: schedule.timeOfDay,
                scheduledAt: log.scheduledAt,
                status: status,
                medicineId: medicine.id,
                treatmentId: medicine.treatmentId
            )
        }
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
        RewardEngine.applyTreatmentComplete(
            context: context,
            ownerId: treatment.ownerId ?? ownerId,
            profileId: treatment.profileId ?? writeProfileId,
            treatmentId: treatment.id
        )
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
                let status = DoseLogStatus(rawValue: $0.status) ?? .pending
                return status.isOpen || status.isMissedLike
            }
            let neverFullyTaken = !dueLogs.isEmpty
                && !dueLogs.contains { DoseLogStatus(rawValue: $0.status)?.isConfirmedTaken == true }
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
                missedCount: 0,
                refillDataComplete: false
            )
        }
    }

    func draftsFromActivePlan() -> [OnboardingPrescriptionDraft] {
        _ = revision
        let activeIds = Set(activeTreatments().map(\.id))
        let drafts = medicines().compactMap { medicine -> OnboardingPrescriptionDraft? in
            guard medicine.deletedAt == nil, activeIds.contains(medicine.treatmentId) else { return nil }
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

    func medicineName(forLogId id: UUID) -> String? {
        guard let medicineId = medicineId(forLogId: id) else { return nil }
        return medicines().first(where: { $0.id == medicineId })?.name
    }

    /// Read-only: whether a delivered `checkmed.*` banner still belongs to a live plan.
    func shouldRetainDeliveredCheckmedNotification(identifier: String) -> Bool {
        if identifier == Engagement.winBackId || identifier == Engagement.leaveSetupId {
            return true
        }
        guard identifier.hasPrefix("checkmed.") else { return true }
        let parts = identifier.split(separator: ".").map(String.init)
        guard parts.count >= 3 else { return true }
        let kindRaw = parts[1]
        guard let uuid = UUID(uuidString: parts[2]) else { return true }
        // Identifier uses `stockDays`; Kind raw value is `stockDaysLeft`. Do not treat as DoseLog.
        if kindRaw == "stockDays" {
            return isMedicineOnActiveTreatment(uuid)
        }
        guard let kind = ReminderDraft.Kind(rawValue: kindRaw) else { return true }
        switch kind {
        case .dose, .nudge5, .nudge30, .missed, .confirm, .advance:
            return isDeliveredDoseFamilyStillValid(logId: uuid)
        case .refill:
            return isActiveTreatment(uuid)
        case .stockRefill, .stockDaysLeft:
            return isMedicineOnActiveTreatment(uuid)
        }
    }

    private func isDeliveredDoseFamilyStillValid(logId: UUID) -> Bool {
        guard let log = allLogs().first(where: { $0.id == logId && $0.deletedAt == nil }) else { return false }
        let status = DoseLogStatus(rawValue: log.status) ?? .pending
        if status.isConfirmedTaken { return false }
        guard let schedule = allSchedules().first(where: { $0.id == log.scheduleId && $0.deletedAt == nil }) else {
            return false
        }
        return isMedicineOnActiveTreatment(schedule.medicineId)
    }

    private func isActiveTreatment(_ id: UUID) -> Bool {
        allTreatments().contains {
            $0.id == id && $0.deletedAt == nil && $0.status == "active"
        }
    }

    private func isMedicineOnActiveTreatment(_ medicineId: UUID) -> Bool {
        guard let medicine = allMedicines().first(where: { $0.id == medicineId && $0.deletedAt == nil }) else {
            return false
        }
        return isActiveTreatment(medicine.treatmentId)
    }

    #if DEBUG
    /// One-shot 5B-4H: nearest `.pendingConfirmation` log to `now` (read-only).
    func debugMostRecentPendingConfirmation(now: Date) -> (
        id: UUID,
        medicine: String,
        scheduledAt: Date,
        loggedAt: Date?,
        status: String,
        treatmentId: UUID?,
        medicineId: UUID?
    )? {
        let rows = logs().compactMap { log -> DoseLogRecord? in
            (DoseLogStatus(rawValue: log.status) ?? .pending) == .pendingConfirmation ? log : nil
        }
        guard let log = rows.min(by: {
            abs($0.scheduledAt.timeIntervalSince(now)) < abs($1.scheduledAt.timeIntervalSince(now))
        }) else { return nil }
        let schedule = schedules().first(where: { $0.id == log.scheduleId })
        let medicine = schedule.flatMap { slot in medicines().first(where: { $0.id == slot.medicineId }) }
        return (
            log.id,
            medicine?.name ?? "?",
            log.scheduledAt,
            log.loggedAt,
            log.status,
            medicine?.treatmentId,
            medicine?.id
        )
    }
    #endif

    func hasFeelingRecord(forLogId id: UUID) -> Bool {
        feelings().contains { $0.logId == id }
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
    static func persistDoseAction(id: UUID, action: DoseLoopAction, now: Date = Date()) {
        let schema = Schema([
            TreatmentRecord.self,
            MedicineRecord.self,
            DoseScheduleRecord.self,
            DoseLogRecord.self,
            FeelingRecord.self,
            RewardGrant.self,
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
        let previous = DoseLogStatus(rawValue: log.status) ?? .pending
        let next = DoseLoop.apply(
            action,
            current: previous,
            scheduledAt: log.scheduledAt,
            now: now,
            grace: ReminderPreferences.confirmationGraceInterval
        )
        if previous.isConfirmedTaken, !next.isConfirmedTaken { return }
        if previous == next, next != .snoozed { return }
        FreezeDiag.log("SWIFTDATA WRITE START source=persistDoseAction")
        FreezeDiag.log(
            "SWIFTDATA WRITE object=\(log.id) kind=update medicine=- oldStatus=\(previous.rawValue) newStatus=\(next.rawValue) scheduledAt=\(log.scheduledAt)"
        )
        log.status = next.rawValue
        log.loggedAt = now
        log.updatedAt = now
        if DoseLoop.shouldConsumeStock(from: previous, to: next) {
            let scheduleId = log.scheduleId
            let scheduleDesc = FetchDescriptor<DoseScheduleRecord>(
                predicate: #Predicate { row in row.id == scheduleId && row.deletedAt == nil }
            )
            if let schedule = try? context.fetch(scheduleDesc).first {
                let medicineId = schedule.medicineId
                let medDesc = FetchDescriptor<MedicineRecord>(
                    predicate: #Predicate { row in row.id == medicineId && row.deletedAt == nil }
                )
                if let medicine = try? context.fetch(medDesc).first,
                   MedicineUnits.hasCompleteRefillData(
                    packageAmount: medicine.packageAmount,
                    quantityPerDose: medicine.quantityPerDose,
                    packageUnit: medicine.packageMedicineUnit,
                    doseUnit: medicine.doseMedicineUnit
                   ),
                   let stock = MedicineUnits.stockPercentAfterDose(
                    packageAmount: medicine.packageAmount,
                    packageUnit: medicine.packageMedicineUnit,
                    stockPercent: medicine.stockPercent,
                    quantityPerDose: medicine.quantityPerDose,
                    doseUnit: medicine.doseMedicineUnit
                   ) {
                    medicine.stockPercent = stock
                    medicine.updatedAt = now
                }
            }
        }
        try? context.save()
        FreezeDiag.log("SWIFTDATA WRITE END source=persistDoseAction")
        if next.isConfirmedTaken, !previous.isConfirmedTaken {
            enqueueOrApplyCanonicalDoseRewards(
                logId: id,
                previous: previous,
                next: next,
                now: now
            )
            let scheduleId = log.scheduleId
            let scheduleDesc = FetchDescriptor<DoseScheduleRecord>(
                predicate: #Predicate { row in row.id == scheduleId && row.deletedAt == nil }
            )
            let medicineName: String
            if let schedule = try? context.fetch(scheduleDesc).first {
                let medicineId = schedule.medicineId
                let medDesc = FetchDescriptor<MedicineRecord>(
                    predicate: #Predicate { row in row.id == medicineId && row.deletedAt == nil }
                )
                medicineName = (try? context.fetch(medDesc).first)?.name ?? ""
            } else {
                medicineName = ""
            }
            FeelingCheckInQueue.enqueue(logId: id, medicine: medicineName)
        }
    }

    static func persistDoseStatus(id: UUID, status: DoseLogStatus) {
        let action: DoseLoopAction
        switch status {
        case .taken, .takenLate: action = .confirmTaken
        case .snoozed: action = .snooze
        case .pendingConfirmation: action = .stop
        case .missed, .skipped: action = .didNotTake
        case .pending: return
        }
        persistDoseAction(id: id, action: action)
    }

    func todayNodes() -> [DoseNode] {
        _ = revision
        guard surfacesPlan else { return [] }
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        guard !activeTreatmentIds.isEmpty else { return [] }
        let dayLogs = todayLogs().sorted { $0.scheduledAt < $1.scheduledAt }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: allSchedules().map { ($0.id, $0) })
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
                scheduledAt: log.scheduledAt,
                isTakenLate: DoseLogStatus(rawValue: log.status) == .takenLate
            )
        }
        nodes = collapseDuplicateSlotNodes(nodes)
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

    /// Display-only: one Challenge/path node per medicine + minute. Never deletes logs.
    private func collapseDuplicateSlotNodes(_ nodes: [DoseNode]) -> [DoseNode] {
        func rank(_ status: PathStatus) -> Int {
            switch status {
            case .done: return 3
            case .current: return 2
            case .skipped: return 1
            case .locked: return 0
            }
        }
        var chosen: [String: DoseNode] = [:]
        var order: [String] = []
        for node in nodes {
            let key = DoseLoop.obligationKey(
                medicineId: node.medicineId,
                scheduledAt: node.scheduledAt,
                calendar: calendar
            )
            if chosen[key] == nil {
                order.append(key)
                chosen[key] = node
            } else if rank(node.status) > rank(chosen[key]!.status) {
                chosen[key] = node
            }
        }
        return order.compactMap { chosen[$0] }
    }

    /// Read-only today's challenge counts. One slot per medicine + minute.
    func todayChallengeCounts(now: Date = CheckMedClock.now) -> DoseLoop.TodayChallengeCounts {
        _ = revision
        let counts = DoseLoop.todayChallengeCounts(
            logs: todayChallengeProbes(),
            now: now,
            calendar: calendar
        )
        #if DEBUG
        let signature = "\(calendar.startOfDay(for: now).timeIntervalSince1970)|\(counts.scheduledCount)|\(counts.completedCount)|\(counts.takenLateCount)|\(counts.missedCount)|\(counts.remainingCount)|\(counts.isComplete)"
        let day = ScanPipeline.iso(calendar.startOfDay(for: now), calendar: calendar)
        if lastChallengeDiag != signature {
            if let previous = lastChallengeDiag {
                print("[CHALLENGE-DIAG] STATE CHANGE old=\(previous) new=\(signature) reason=canonicalTodaySlots")
            }
            lastChallengeDiag = signature
            print(
                "[CHALLENGE-DIAG] date=\(day) scheduled=\(counts.scheduledCount) taken=\(counts.takenCount) takenLate=\(counts.takenLateCount) completed=\(counts.completedCount) missed=\(counts.missedCount) remaining=\(counts.remainingCount) isComplete=\(counts.isComplete)"
            )
        }
        #endif
        return counts
    }

    /// Read-only Mon–Sun progress. Cached by revision + calendar day. Does not write.
    func weeklyMedicationProgress(now: Date = CheckMedClock.now) -> DoseLoop.WeeklyMedicationProgressSnapshot {
        _ = revision
        let today = calendar.startOfDay(for: now)
        if let cached = cachedWeekly,
           cachedWeeklyRevision == revision,
           cachedWeeklyDay == today {
            return cached
        }
        guard surfacesPlan else {
            let empty = DoseLoop.WeeklyMedicationProgressSnapshot.empty
            cachedWeekly = empty
            cachedWeeklyRevision = revision
            cachedWeeklyDay = today
            return empty
        }
        let windows = treatmentWindowsForAdherence()
        let bounds = DoseLoop.mondayWeekInterval(containing: now, calendar: calendar)
        let weekLogs: [DoseLoop.DoseSummaryProbe] = doseSummaryProbes(from: logsOnActiveTreatments(logs())).filter {
            $0.scheduledAt >= bounds.start && $0.scheduledAt < bounds.end
        }
        let snapshot = DoseLoop.weeklyMedicationProgress(
            logs: weekLogs,
            treatmentWindows: windows,
            now: now,
            calendar: calendar,
            todayCounts: todayChallengeCounts(now: now)
        )
        #if DEBUG
        let signature = "\(snapshot.weekStart.timeIntervalSince1970)|\(snapshot.completedDays)|\(snapshot.applicableDays)|\(snapshot.adherencePercentage ?? -1)|\(snapshot.days.map { "\($0.status)" }.joined(separator: ","))"
        if lastWeeklyDiag != signature {
            if let previous = lastWeeklyDiag {
                print("[WEEKLY-DIAG] STATE CHANGE old=\(previous) new=\(signature) reason=canonicalDoseLogs")
            }
            lastWeeklyDiag = signature
            print(
                "[WEEKLY-DIAG] weekStart=\(ScanPipeline.iso(snapshot.weekStart, calendar: calendar)) weekEnd=\(ScanPipeline.iso(snapshot.weekEnd, calendar: calendar)) applicableDays=\(snapshot.applicableDays) completedDays=\(snapshot.completedDays) adherence=\(snapshot.adherencePercentage ?? -1)"
            )
            for day in snapshot.days {
                print(
                    "[WEEKLY-DIAG] DAY date=\(ScanPipeline.iso(day.date, calendar: calendar)) status=\(day.status) scheduled=\(day.scheduledCount) taken=\(day.takenCount) takenLate=\(day.takenLateCount) missed=\(day.missedCount) completed=\(day.completedCount)"
                )
            }
        }
        #endif
        cachedWeekly = snapshot
        cachedWeeklyRevision = revision
        cachedWeeklyDay = today
        return snapshot
    }

    private func todayChallengeProbes() -> [DoseLoop.DoseSummaryProbe] {
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: allSchedules().map { ($0.id, $0) })
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        return todayLogs().compactMap { log in
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId],
                  activeTreatmentIds.contains(medicine.treatmentId) else { return nil }
            return DoseLoop.DoseSummaryProbe(
                id: log.id,
                scheduleId: log.scheduleId,
                medicineId: medicine.id,
                scheduledAt: log.scheduledAt,
                status: DoseLogStatus(rawValue: log.status) ?? .pending
            )
        }
    }

    func adherence() -> AdherenceSnapshot {
        FreezeDiag.context("adherence START revision=\(revision)", hasChanges: context.hasChanges)
        let t0 = Date()
        _ = revision
        let now = Date()
        let today = calendar.startOfDay(for: now)
        if let cached = cachedAdherence,
           cachedAdherenceRevision == revision,
           cachedAdherenceDay == today {
            FreezeDiag.log("adherence END (cached)")
            return cached
        }
        guard surfacesPlan else {
            FreezeDiag.log("adherence END (no plan)")
            let empty = AdherenceSnapshot(
                streakDays: 0,
                longestStreakDays: 0,
                takenCount: 0,
                takenLateCount: 0,
                missedCount: 0,
                plannedCount: 0,
                percent: nil,
                treatmentCount: 0,
                todayTaken: 0,
                todayTotal: 0,
                todayMissedCount: 0,
                hasHistory: false,
                weekTaken: 0,
                weekPlanned: 0,
                weekPercent: nil
            )
            cachedAdherence = empty
            cachedAdherenceRevision = revision
            cachedAdherenceDay = today
            return empty
        }
        let challenge = todayChallengeCounts(now: now)
        let todayTaken = challenge.completedCount
        let todayTotal = challenge.scheduledCount
        let todayMissedCount = challenge.missedCount
        let history = logs()
        let activeHistory = logsOnActiveTreatments(history)
        let due = activeHistory.filter { $0.scheduledAt <= now }
        let takenLateCount = due.filter { $0.status == DoseLogStatus.takenLate.rawValue }.count
        let takenOnTime = due.filter { $0.status == DoseLogStatus.taken.rawValue }.count
        let missedCount = due.filter { DoseLogStatus(rawValue: $0.status)?.isMissedLike == true }.count
        let takenCount = takenOnTime + takenLateCount
        let plannedCount = due.count
        let percent: Int? = plannedCount == 0 ? nil : Int((Double(takenCount) / Double(plannedCount) * 100).rounded())
        let weekBounds = DoseLoop.mondayWeekInterval(containing: now, calendar: calendar)
        let weekStart = weekBounds.start
        let weekEnd = weekBounds.end
        let weekLogs = activeHistory.filter { log in
            log.scheduledAt >= weekStart && log.scheduledAt < weekEnd
        }
        let weekTaken = weekLogs.filter { DoseLogStatus(rawValue: $0.status)?.isConfirmedTaken == true }.count
        let weekPlanned = weekLogs.count
        let weekPercent: Int? = weekPlanned == 0 ? nil : Int((Double(weekTaken) / Double(weekPlanned) * 100).rounded())
        let streak = streakFromCanonical(now: now, todayCounts: challenge)
        FreezeDiag.context(
            String(format: "adherence END logs=%d revision=%d %.0fms", history.count, revision, Date().timeIntervalSince(t0) * 1000),
            hasChanges: context.hasChanges
        )
        let snap = AdherenceSnapshot(
            streakDays: streak.currentDays,
            longestStreakDays: max(streak.currentDays, streak.longestDays),
            takenCount: takenCount,
            takenLateCount: takenLateCount,
            missedCount: missedCount,
            plannedCount: plannedCount,
            percent: percent,
            treatmentCount: activeTreatments().count,
            todayTaken: todayTaken,
            todayTotal: todayTotal,
            todayMissedCount: todayMissedCount,
            hasHistory: !due.isEmpty,
            weekTaken: weekTaken,
            weekPlanned: weekPlanned,
            weekPercent: weekPercent
        )
        cachedAdherence = snap
        cachedAdherenceRevision = revision
        cachedAdherenceDay = today
        return snap
    }

    func reminderDrafts(now: Date = Date()) -> [ReminderDraft] {
        guard surfacesPlan else { return [] }
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        guard !activeTreatmentIds.isEmpty else { return [] }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: schedules().map { ($0.id, $0) })
        let horizon = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let grace = ReminderPreferences.confirmationGraceInterval
        let snooze = ReminderPreferences.snoozeInterval
        var drafts: [ReminderDraft] = []
        for log in logs() {
            let status = DoseLogStatus(rawValue: log.status) ?? .pending
            guard status.isOpen else { continue }
            guard log.scheduledAt < horizon || status == .snoozed || status == .pendingConfirmation else { continue }
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId],
                  activeTreatmentIds.contains(medicine.treatmentId) else { continue }
            func append(_ fire: Date, kind: ReminderDraft.Kind) {
                guard fire > now.addingTimeInterval(8), fire < horizon.addingTimeInterval(grace) else { return }
                drafts.append(
                    ReminderDraft(
                        id: log.id,
                        fireDate: fire,
                        medicine: medicine.name,
                        doseLabel: medicine.doseLabel,
                        time: schedule.timeOfDay,
                        kind: kind
                    )
                )
            }
            switch status {
            case .pending:
                append(log.scheduledAt, kind: .dose)
                append(log.scheduledAt.addingTimeInterval(5 * 60), kind: .nudge5)
                append(log.scheduledAt.addingTimeInterval(30 * 60), kind: .nudge30)
                append(log.scheduledAt.addingTimeInterval(grace), kind: .missed)
                let advanceAt = log.scheduledAt.addingTimeInterval(-3600)
                if log.scheduledAt > now.addingTimeInterval(8) {
                    append(advanceAt, kind: .advance)
                }
            case .snoozed:
                append(DoseLoop.snoozeFireDate(loggedAt: log.loggedAt ?? now, snooze: snooze, now: now), kind: .dose)
            case .pendingConfirmation:
                append(log.scheduledAt.addingTimeInterval(5 * 60), kind: .nudge5)
                append(log.scheduledAt.addingTimeInterval(30 * 60), kind: .nudge30)
                let followUp = (log.loggedAt ?? now).addingTimeInterval(grace)
                append(followUp, kind: .confirm)
            case .taken, .takenLate, .missed, .skipped:
                break
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
            } else if dayLogs.contains(where: { DoseLogStatus(rawValue: $0.status)?.isMissedLike == true || ($0.status == DoseLogStatus.pending.rawValue && $0.scheduledAt < now) }) {
                cells.append((number, "miss"))
            } else if dayLogs.contains(where: { DoseLogStatus(rawValue: $0.status)?.isConfirmedTaken == true }) {
                cells.append((number, "done"))
            } else {
                cells.append((number, "done"))
            }
        }
        return cells
    }

    func addFeeling(logId: UUID?, medicineName: String, mood: FeelingMood, note: String) {
        if let logId, hasFeelingRecord(forLogId: logId) {
            FeelingCheckInQueue.clearIfLogId(logId)
            return
        }
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
        if let logId {
            FeelingCheckInQueue.clearIfLogId(logId)
        }
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
        let taken = related.filter { DoseLogStatus(rawValue: $0.status)?.isConfirmedTaken == true }.count
        let skipped = related.filter { DoseLogStatus(rawValue: $0.status)?.isMissedLike == true }.count
        let planned = related.count
        let percent = planned == 0 ? 0 : Int((Double(taken) / Double(planned) * 100).rounded())
        let treatmentLogIds = Set(
            logs().filter { scheduleIds.contains($0.scheduleId) }.map(\.id)
        )
        let relatedFeelings = feelings().filter { feeling in
            guard let logId = feeling.logId else { return false }
            return treatmentLogIds.contains(logId)
        }
        return JourneyReport(
            treatmentId: treatment.id,
            title: treatment.title,
            startDate: treatment.startDate,
            endDate: treatment.endDate,
            treatmentStatus: treatment.status,
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

    /// Journey Tree / Report / History. Derived only — does not write.
    func journeyKind(
        status: String,
        startDate: Date,
        endDate: Date?,
        now: Date = Date()
    ) -> TreatmentJourneyKind? {
        TreatmentJourneyClassification.classify(
            deletedAt: nil,
            status: status,
            startDate: startDate,
            endDate: endDate,
            now: now,
            calendar: calendar
        )
    }

    func isCurrentOnJourneyHistory(status: String, startDate: Date, endDate: Date?, now: Date = Date()) -> Bool {
        journeyKind(status: status, startDate: startDate, endDate: endDate, now: now) == .current
    }

    func isCurrentOnJourneyHistory(treatmentId: UUID, now: Date = Date()) -> Bool {
        _ = revision
        guard let treatment = treatments().first(where: { $0.id == treatmentId }) else { return false }
        return journeyKind(
            status: treatment.status,
            startDate: treatment.startDate,
            endDate: treatment.endDate,
            now: now
        ) == .current
    }

    func isPastOnJourneyHistory(treatmentId: UUID, now: Date = Date()) -> Bool {
        _ = revision
        guard let treatment = treatments().first(where: { $0.id == treatmentId }) else { return false }
        return journeyKind(
            status: treatment.status,
            startDate: treatment.startDate,
            endDate: treatment.endDate,
            now: now
        ) == .past
    }

    struct JourneyTreeBranch: Identifiable, Equatable, Sendable {
        var id: UUID
        var title: String
        var startDate: Date
        var endDate: Date?
        var medicineNames: [String]
    }

    struct JourneyTreeSnapshot: Equatable, Sendable {
        var current: [JourneyTreeBranch]
        var future: [JourneyTreeBranch]
        var past: [JourneyTreeBranch]

        var isEmpty: Bool { current.isEmpty && future.isEmpty && past.isEmpty }
    }

    /// Read-only Journey Tree. Groups medicines under their Treatment UUID.
    func journeyTreeSnapshot(now: Date = Date()) -> JourneyTreeSnapshot {
        _ = revision
        var current: [JourneyTreeBranch] = []
        var future: [JourneyTreeBranch] = []
        var past: [JourneyTreeBranch] = []
        for treatment in treatments() {
            guard let kind = TreatmentJourneyClassification.classify(
                deletedAt: treatment.deletedAt,
                status: treatment.status,
                startDate: treatment.startDate,
                endDate: treatment.endDate,
                now: now,
                calendar: calendar
            ) else { continue }
            let names = medicines(for: treatment.id).map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !names.isEmpty else { continue }
            let branch = JourneyTreeBranch(
                id: treatment.id,
                title: treatment.title,
                startDate: treatment.startDate,
                endDate: treatment.endDate,
                medicineNames: names
            )
            switch kind {
            case .current: current.append(branch)
            case .future: future.append(branch)
            case .past: past.append(branch)
            }
        }
        current.sort { $0.startDate > $1.startDate }
        future.sort { $0.startDate < $1.startDate }
        past.sort { $0.startDate > $1.startDate }
        return JourneyTreeSnapshot(current: current, future: future, past: past)
    }

    /// Today's Challenge / Home path: current Journey treatments only. Does not seed logs.
    private func currentJourneyTreatmentIds(now: Date = Date()) -> Set<UUID> {
        Set(
            treatments().compactMap { treatment in
                TreatmentJourneyClassification.classify(
                    deletedAt: treatment.deletedAt,
                    status: treatment.status,
                    startDate: treatment.startDate,
                    endDate: treatment.endDate,
                    now: now,
                    calendar: calendar
                ) == .current ? treatment.id : nil
            }
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

    /// True when this owner already has an active (not completed/deleted) treatment.
    var hasActivePlan: Bool {
        guard let ownerId else { return false }
        return allTreatments().contains {
            $0.deletedAt == nil && $0.ownerId == ownerId && $0.status == "active"
        }
    }

    /// Existing valid plan for this owner — load it; do not create a duplicate.
    func existingActivePlanId() -> UUID? {
        guard let ownerId else { return nil }
        return allTreatments().first {
            $0.deletedAt == nil && $0.ownerId == ownerId && $0.status == "active"
        }?.id
    }

    /// Only push rows owned by the signed-in user. Never upload unowned leftover SwiftData.
    func treatmentSnapshots() -> [TreatmentSnapshot] { syncable(ownedExact(allTreatments())).map(\.snapshot) }
    func medicineSnapshots() -> [MedicineSnapshot] { syncable(ownedExact(allMedicines())).map(\.snapshot) }
    func scheduleSnapshots() -> [DoseScheduleSnapshot] { syncable(ownedExact(allSchedules())).map(\.snapshot) }
    func logSnapshots() -> [DoseLogSnapshot] { syncable(ownedExact(allLogs())).map(\.snapshot) }

    func mergeTreatment(_ row: TreatmentSnapshot) {
        mergeTreatments([row])
    }

    func mergeMedicine(_ row: MedicineSnapshot) {
        mergeMedicines([row])
    }

    func mergeSchedule(_ row: DoseScheduleSnapshot) {
        mergeSchedules([row])
    }

    func mergeLog(_ row: DoseLogSnapshot) {
        mergeLogs([row])
    }

    func applyRemoteReplica(
        treatments: [TreatmentSnapshot],
        medicines: [MedicineSnapshot],
        schedules: [DoseScheduleSnapshot],
        logs: [DoseLogSnapshot]
    ) async {
        let previous = suppressNotify
        suppressNotify = true
        mergeTreatments(treatments)
        await Task.yield()
        mergeMedicines(medicines)
        await Task.yield()
        mergeSchedules(schedules)
        await Task.yield()
        let cutoff = Date().addingTimeInterval(-36 * 60 * 60)
        let recentLogs = logs.filter { row in
            if row.status == DoseLogStatus.pending.rawValue
                || row.status == DoseLogStatus.snoozed.rawValue {
                return row.scheduledAt >= cutoff
            }
            return true
        }
        await mergeLogsYielding(recentLogs)
        suppressNotify = previous
    }

    func saveAfterSync() {
        let previous = suppressNotify
        suppressNotify = true
        logsEnsuredDay = nil
        save()
        suppressNotify = previous
        notify()
    }

    private func mergeTreatments(_ rows: [TreatmentSnapshot]) {
        guard !rows.isEmpty else { return }
        var byId = Dictionary(uniqueKeysWithValues: allTreatments().map { ($0.id, $0) })
        var inserted = false
        for row in rows {
            if let existing = byId[row.id] {
                guard row.updatedAt >= existing.updatedAt else { continue }
                existing.apply(row)
            } else {
                let record = TreatmentRecord(snapshot: row)
                context.insert(record)
                byId[row.id] = record
                inserted = true
            }
        }
        if inserted { invalidateCache() }
    }

    private func mergeMedicines(_ rows: [MedicineSnapshot]) {
        guard !rows.isEmpty else { return }
        var byId = Dictionary(uniqueKeysWithValues: allMedicines().map { ($0.id, $0) })
        var inserted = false
        for row in rows {
            if let existing = byId[row.id] {
                guard row.updatedAt >= existing.updatedAt else { continue }
                existing.apply(row)
            } else {
                let record = MedicineRecord(snapshot: row)
                context.insert(record)
                byId[row.id] = record
                inserted = true
            }
        }
        if inserted { invalidateCache() }
    }

    private func mergeSchedules(_ rows: [DoseScheduleSnapshot]) {
        guard !rows.isEmpty else { return }
        var byId = Dictionary(uniqueKeysWithValues: allSchedules().map { ($0.id, $0) })
        var inserted = false
        for row in rows {
            if let existing = byId[row.id] {
                guard row.updatedAt >= existing.updatedAt else { continue }
                existing.apply(row)
            } else {
                let record = DoseScheduleRecord(snapshot: row)
                context.insert(record)
                byId[row.id] = record
                inserted = true
            }
        }
        if inserted { invalidateCache() }
    }

    private func mergeLogs(_ rows: [DoseLogSnapshot]) {
        guard !rows.isEmpty else { return }
        var byId = Dictionary(uniqueKeysWithValues: allLogs().map { ($0.id, $0) })
        let inserted = mergeLogs(rows, into: &byId)
        if inserted { invalidateCache() }
    }

    @discardableResult
    private func mergeLogs(
        _ rows: [DoseLogSnapshot],
        into byId: inout [UUID: DoseLogRecord]
    ) -> Bool {
        var inserted = false
        for row in rows {
            if let existing = byId[row.id] {
                guard row.updatedAt >= existing.updatedAt else { continue }
                let statusChanging = existing.status != row.status
                if statusChanging
                    || existing.scheduleId != row.scheduleId
                    || existing.ownerId != row.ownerId
                    || existing.profileId != row.profileId
                    || existing.scheduledAt != row.scheduledAt
                    || existing.loggedAt != row.loggedAt
                    || existing.updatedAt != row.updatedAt
                    || existing.deletedAt != row.deletedAt {
                    FreezeDiag.log("SWIFTDATA WRITE START source=mergeLogs.apply")
                    FreezeDiag.log(
                        "SWIFTDATA WRITE object=\(row.id) kind=update medicine=- oldStatus=\(existing.status) newStatus=\(row.status) scheduledAt=\(row.scheduledAt)"
                    )
                    existing.apply(row)
                    FreezeDiag.log("SWIFTDATA WRITE END source=mergeLogs.apply")
                }
            } else {
                let record = DoseLogRecord(snapshot: row)
                FreezeDiag.log("SWIFTDATA WRITE START source=mergeLogs.insert")
                FreezeDiag.log(
                    "SWIFTDATA WRITE object=\(row.id) kind=insert medicine=- oldStatus=- newStatus=\(row.status) scheduledAt=\(row.scheduledAt)"
                )
                context.insert(record)
                FreezeDiag.log("SWIFTDATA WRITE END source=mergeLogs.insert")
                byId[row.id] = record
                inserted = true
            }
        }
        return inserted
    }

    private func mergeLogsYielding(_ rows: [DoseLogSnapshot]) async {
        guard !rows.isEmpty else { return }
        var byId = Dictionary(uniqueKeysWithValues: allLogs().map { ($0.id, $0) })
        var inserted = false
        let chunk = 24
        var start = 0
        while start < rows.count {
            let end = min(start + chunk, rows.count)
            if mergeLogs(Array(rows[start..<end]), into: &byId) {
                inserted = true
            }
            start = end
            await Task.yield()
        }
        if inserted { invalidateCache() }
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

    /// Effective DoseLog calendar window. A medicine with a decoded PlanDuration
    /// uses its own start/end; otherwise the parent TreatmentRecord dates apply.
    /// Does not rewrite stored treatment or medicine dates.
    private func doseLogWindow(
        for medicine: MedicineRecord,
        treatment: TreatmentRecord?
    ) -> (start: Date?, end: Date?, source: String) {
        if let bounds = PlanDuration.bounds(from: medicine.duration, calendar: calendar),
           calendar.startOfDay(for: bounds.start) <= calendar.startOfDay(for: bounds.end) {
            var start = calendar.startOfDay(for: bounds.start)
            let end = calendar.startOfDay(for: bounds.end)
            if let treatmentStart = treatment?.startDate {
                let activation = calendar.startOfDay(for: treatmentStart)
                if start < activation {
                    start = activation
                }
            }
            if start <= end {
                return (start, end, "medicine")
            }
        }
        return (treatment?.startDate, treatment?.endDate, "treatment")
    }

    private func ensureUpcomingLogs() {
        FreezeDiag.context("ensureUpcomingLogs START", hasChanges: context.hasChanges)
        guard surfacesPlan else {
            FreezeDiag.context("ensureUpcomingLogs END no plan", hasChanges: context.hasChanges)
            return
        }
        let now = Date()
        let day = calendar.startOfDay(for: now)
        let signature = [
            calendar.timeZone.identifier,
            schedules().map(\.id.uuidString).sorted().joined(),
            scopeProfileId?.uuidString ?? "",
            includeUnscoped ? "1" : "0",
        ].joined(separator: "|").hashValue
        if logsEnsuredDay == day, logsEnsuredSignature == signature {
            FreezeDiag.context("ensureUpcomingLogs END already ensured", hasChanges: context.hasChanges)
            return
        }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let treatmentsById = Dictionary(uniqueKeysWithValues: activeTreatments().map { ($0.id, $0) })
        let activeTreatmentIds = Set(treatmentsById.keys)
        let scheduleMedicineId = Dictionary(uniqueKeysWithValues: allSchedules().map { ($0.id, $0.medicineId) })
        var medicinesWithLogsBeforeToday = Set<UUID>()
        for log in allLogs() where log.deletedAt == nil {
            guard calendar.startOfDay(for: log.scheduledAt) < day else { continue }
            if let medicineId = scheduleMedicineId[log.scheduleId] {
                medicinesWithLogsBeforeToday.insert(medicineId)
            }
        }
        var inserted = 0
        for offset in 0..<7 {
            guard let slotDay = calendar.date(byAdding: .day, value: offset, to: day),
                  let end = calendar.date(byAdding: .day, value: 1, to: slotDay) else { continue }
            let existing = allLogs().filter {
                $0.deletedAt == nil && $0.scheduledAt >= slotDay && $0.scheduledAt < end
            }
            let schedulesById = Dictionary(uniqueKeysWithValues: allSchedules().map { ($0.id, $0) })
            var existingKeys = Set<String>()
            for log in existing {
                existingKeys.insert(
                    "\(log.scheduleId.uuidString)|\(calendar.startOfDay(for: log.scheduledAt).timeIntervalSince1970)"
                )
                if let medicineId = schedulesById[log.scheduleId]?.medicineId {
                    existingKeys.insert(
                        DoseLoop.obligationKey(medicineId: medicineId, scheduledAt: log.scheduledAt, calendar: calendar)
                    )
                }
            }
            for schedule in schedules() {
                guard let medicine = medicinesById[schedule.medicineId],
                      medicine.deletedAt == nil,
                      activeTreatmentIds.contains(medicine.treatmentId) else { continue }
                guard let scheduledAt = date(on: slotDay, timeOfDay: schedule.timeOfDay) else { continue }
                let treatment = treatmentsById[medicine.treatmentId]
                let window = doseLogWindow(for: medicine, treatment: treatment)
                if calendar.startOfDay(for: scheduledAt) < day {
                    ScanLog.dose(
                        "skip historical day scheduled=\(ScanPipeline.iso(scheduledAt, calendar: calendar)) medicine=\(medicine.name)"
                    )
                    continue
                }
                if let start = window.start,
                   calendar.startOfDay(for: scheduledAt) < calendar.startOfDay(for: start) {
                    ScanLog.dose(
                        "skip before \(window.source)StartDate=\(ScanPipeline.iso(start, calendar: calendar)) "
                        + "scheduled=\(ScanPipeline.iso(scheduledAt, calendar: calendar)) medicine=\(medicine.name)"
                    )
                    continue
                }
                if let end = window.end,
                   calendar.startOfDay(for: scheduledAt) > calendar.startOfDay(for: end) {
                    ScanLog.dose(
                        "skip after \(window.source)EndDate=\(ScanPipeline.iso(end, calendar: calendar)) "
                        + "scheduled=\(ScanPipeline.iso(scheduledAt, calendar: calendar)) medicine=\(medicine.name)"
                    )
                    continue
                }
                // First tracking day: do not invent clocks that already passed.
                // Medicines with logs before today still seed today's overdue slots.
                if DoseLoop.shouldSkipAlreadyPassedClockOnFirstTrackingDay(
                    scheduledAt: scheduledAt,
                    now: now,
                    dayStart: day,
                    hasLogsBeforeDay: medicinesWithLogsBeforeToday.contains(medicine.id),
                    calendar: calendar
                ) {
                    ScanLog.dose(
                        "skip first-tracking-day past clock \(window.source)StartDate=\(window.start.map { ScanPipeline.iso($0, calendar: calendar) } ?? "nil") "
                        + "scheduled=\(ScanPipeline.iso(scheduledAt, calendar: calendar)) medicine=\(medicine.name)"
                    )
                    continue
                }
                let key = "\(schedule.id.uuidString)|\(calendar.startOfDay(for: scheduledAt).timeIntervalSince1970)"
                let medicineSlot = DoseLoop.obligationKey(
                    medicineId: medicine.id,
                    scheduledAt: scheduledAt,
                    calendar: calendar
                )
                guard !existingKeys.contains(key), !existingKeys.contains(medicineSlot) else { continue }
                existingKeys.insert(key)
                existingKeys.insert(medicineSlot)
                let log = DoseLogRecord(
                    scheduleId: schedule.id,
                    ownerId: ownerId,
                    profileId: writeProfileId,
                    scheduledAt: scheduledAt,
                    status: DoseLogStatus.pending.rawValue,
                    updatedAt: now
                )
                ScanLog.dose(
                    "create scheduled=\(ScanPipeline.iso(scheduledAt, calendar: calendar)) medicine=\(medicine.name) status=pending"
                )
                FreezeDiag.log("SWIFTDATA WRITE START source=ensureUpcomingLogs")
                FreezeDiag.log(
                    "SWIFTDATA WRITE object=\(log.id) kind=insert medicine=\(medicine.id) oldStatus=- newStatus=pending scheduledAt=\(scheduledAt)"
                )
                context.insert(log)
                FreezeDiag.log("SWIFTDATA WRITE END source=ensureUpcomingLogs")
                inserted += 1
                #if DEBUG
                let durationBounds = PlanDuration.bounds(from: medicine.duration, calendar: calendar)
                print(
                    "[NEW-DOSE-DIAG] treatmentID=\(medicine.treatmentId.uuidString) medicineID=\(medicine.id.uuidString) "
                    + "scheduledAt=\(ScanPipeline.iso(scheduledAt, calendar: calendar)) now=\(ScanPipeline.iso(now, calendar: calendar)) "
                    + "treatmentStart=\(treatment.map { ScanPipeline.iso($0.startDate, calendar: calendar) } ?? "nil") "
                    + "durationStart=\(durationBounds.map { ScanPipeline.iso($0.start, calendar: calendar) } ?? "nil") "
                    + "durationEnd=\(durationBounds.map { ScanPipeline.iso($0.end, calendar: calendar) } ?? "nil") "
                    + "statusBefore=pending source=ensureUpcomingLogs"
                )
                #endif
                #if DEBUG
                if offset == 0 {
                    print(
                        "[CHALLENGE-DIAG] CHALLENGE INSTANCE date=\(ScanPipeline.iso(slotDay, calendar: calendar)) reason=ensureUpcomingLogs.insertToday doseIDs=\(log.id.uuidString) medicine=\(medicine.name)"
                    )
                }
                #endif
            }
        }
        logsEnsuredDay = day
        logsEnsuredSignature = signature
        if inserted > 0 {
            invalidateCache()
            save()
        }
        FreezeDiag.context("ensureUpcomingLogs END inserted=\(inserted)", hasChanges: context.hasChanges)
    }

    private func todayLogs() -> [DoseLogRecord] {
        let day = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return logs().filter { $0.scheduledAt >= day && $0.scheduledAt < end }
    }

    /// Current Dashboard streak / weekly coverage for **active** treatments.
    /// Same effective window as DoseLog seeding: medicine PlanDuration when valid,
    /// otherwise that medicine's TreatmentRecord dates. Does not rewrite stored dates.
    private func treatmentWindowsForAdherence() -> [DoseLoop.TreatmentWindow] {
        let treatmentsById = Dictionary(uniqueKeysWithValues: activeTreatments().map { ($0.id, $0) })
        var windows: [DoseLoop.TreatmentWindow] = []
        var seen = Set<String>()
        #if DEBUG
        var diagLines: [String] = []
        #endif
        for medicine in medicines() {
            guard let treatment = treatmentsById[medicine.treatmentId] else { continue }
            let resolved = doseLogWindow(for: medicine, treatment: treatment)
            #if DEBUG
            diagLines.append(
                "medicine=\(medicine.name) PlanDuration=\(medicine.duration.isEmpty ? "none" : medicine.duration) "
                    + "TreatmentRecord=\(ScanPipeline.iso(treatment.startDate, calendar: calendar))"
                    + "→\(treatment.endDate.map { ScanPipeline.iso($0, calendar: calendar) } ?? "nil") "
                    + "effective=\(resolved.start.map { ScanPipeline.iso($0, calendar: calendar) } ?? "nil")"
                    + "→\(resolved.end.map { ScanPipeline.iso($0, calendar: calendar) } ?? "nil") "
                    + "source=\(resolved.source)"
            )
            #endif
            guard let start = resolved.start else { continue }
            let startDay = calendar.startOfDay(for: start)
            let endDay = resolved.end.map { calendar.startOfDay(for: $0) }
            let key = "\(startDay.timeIntervalSince1970)|\(endDay?.timeIntervalSince1970 ?? -1)"
            guard seen.insert(key).inserted else { continue }
            windows.append(DoseLoop.TreatmentWindow(start: startDay, end: endDay))
        }
        if windows.isEmpty {
            windows = treatmentsById.values.map {
                DoseLoop.TreatmentWindow(start: $0.startDate, end: $0.endDate)
            }
        }
        #if DEBUG
        let signature = diagLines.joined(separator: ";") + "|windows=\(windows.count)"
        if lastStreakWindowDiag != signature {
            lastStreakWindowDiag = signature
            for line in diagLines {
                print("[STREAK-WINDOW] \(line)")
            }
        }
        #endif
        return windows
    }

    private func doseSummaryProbes(from history: [DoseLogRecord]) -> [DoseLoop.DoseSummaryProbe] {
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: allSchedules().map { ($0.id, $0) })
        return history.compactMap { log in
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId] else { return nil }
            return DoseLoop.DoseSummaryProbe(
                id: log.id,
                scheduleId: log.scheduleId,
                medicineId: medicine.id,
                scheduledAt: log.scheduledAt,
                status: DoseLogStatus(rawValue: log.status) ?? .pending
            )
        }
    }

    private func streakFromCanonical(now: Date, todayCounts: DoseLoop.TodayChallengeCounts) -> DoseLoop.AdherenceStreakSnapshot {
        FreezeDiag.log("streakDays START")
        let t0 = Date()
        let snapshot = DoseLoop.adherenceStreak(
            logs: doseSummaryProbes(from: logsOnActiveTreatments(logs())),
            treatmentWindows: treatmentWindowsForAdherence(),
            now: now,
            calendar: calendar,
            todayCounts: todayCounts
        )
        FreezeDiag.log(String(format: "streakDays END counted=%d %.0fms", snapshot.currentDays, Date().timeIntervalSince(t0) * 1000))
        return snapshot
    }

    /// Active-treatment logs for weekly dose counts in `adherence()`. Streak uses treatment windows.
    private func logsOnActiveTreatments(_ history: [DoseLogRecord]) -> [DoseLogRecord] {
        let activeTreatmentIds = Set(activeTreatments().map(\.id))
        guard !activeTreatmentIds.isEmpty else { return [] }
        let medicinesById = Dictionary(uniqueKeysWithValues: medicines().map { ($0.id, $0) })
        let schedulesById = Dictionary(uniqueKeysWithValues: schedules().map { ($0.id, $0) })
        return history.filter { log in
            guard let schedule = schedulesById[log.scheduleId],
                  let medicine = medicinesById[schedule.medicineId] else { return false }
            return activeTreatmentIds.contains(medicine.treatmentId)
        }
    }

    /// Longest consecutive streak using the same day-complete rule as current streak. Read-only.
    func longestAdherenceStreak() -> Int {
        _ = revision
        guard surfacesPlan else { return 0 }
        let now = Date()
        return streakFromCanonical(now: now, todayCounts: todayChallengeCounts(now: now)).longestDays
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

    /// Strict owner match only. Nil `ownerId` on the store → nothing.
    private func ownedExact<T>(_ rows: [T]) -> [T] {
        guard let ownerId else { return [] }
        return rows.filter { row in
            if let record = row as? TreatmentRecord { return record.ownerId == ownerId }
            if let record = row as? MedicineRecord { return record.ownerId == ownerId }
            if let record = row as? DoseScheduleRecord { return record.ownerId == ownerId }
            if let record = row as? DoseLogRecord { return record.ownerId == ownerId }
            if let record = row as? FeelingRecord { return record.ownerId == ownerId }
            if let record = row as? RewardGrant { return record.ownerId == ownerId }
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
        if let record = row as? RewardGrant { return record.profileId }
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
        FreezeDiag.context("stampIdentity START", hasChanges: context.hasChanges)
        guard let ownerId, let stampProfileId else {
            FreezeDiag.context("stampIdentity END skipped", hasChanges: context.hasChanges)
            return
        }
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
            FreezeDiag.log("SWIFTDATA WRITE START source=stampIdentity")
            FreezeDiag.log(
                "SWIFTDATA WRITE object=\(log.id) kind=update medicine=- oldStatus=\(log.status) newStatus=\(log.status) scheduledAt=\(log.scheduledAt) profile nil->\(stampProfileId)"
            )
            log.profileId = stampProfileId
            FreezeDiag.log("SWIFTDATA WRITE END source=stampIdentity")
            changed = true
        }
        if changed { save() }
        FreezeDiag.context("stampIdentity END changed=\(changed)", hasChanges: context.hasChanges)
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
        let oldOwner = log.ownerId
        let oldProfile = log.profileId
        let newOwner = ownerId ?? log.ownerId
        let newProfile = writeProfileId ?? log.profileId
        if oldOwner != newOwner || oldProfile != newProfile {
            FreezeDiag.log("SWIFTDATA WRITE START source=stamp(DoseLog)")
            FreezeDiag.log(
                "SWIFTDATA WRITE object=\(log.id) kind=update medicine=- oldStatus=\(log.status) newStatus=\(log.status) scheduledAt=\(log.scheduledAt) owner \(String(describing: oldOwner))->\(String(describing: newOwner)) profile \(String(describing: oldProfile))->\(String(describing: newProfile))"
            )
        } else {
            FreezeDiag.log("stamp(DoseLog) assign-same object=\(log.id)")
        }
        log.ownerId = newOwner
        log.profileId = newProfile
        if oldOwner != newOwner || oldProfile != newProfile {
            FreezeDiag.log("SWIFTDATA WRITE END source=stamp(DoseLog)")
        }
    }

    private func pathStatus(for raw: String) -> PathStatus {
        switch DoseLogStatus(rawValue: raw) {
        case .taken, .takenLate: .done
        case .missed, .skipped: .skipped
        case .pendingConfirmation, .snoozed: .current
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
        cachedAdherence = nil
        cachedAdherenceRevision = -1
        cachedAdherenceDay = nil
        cachedWeekly = nil
        cachedWeeklyRevision = -1
        cachedWeeklyDay = nil
    }

    #if DEBUG
    /// Clock command only: drop weekly cache so the next read uses `CheckMedClock.now`.
    /// Does not notify, does not bump revision, does not touch adherence cache.
    func invalidateTimeDerivedCachesForTestClock() {
        cachedWeekly = nil
        cachedWeeklyRevision = -1
        cachedWeeklyDay = nil
        lastChallengeDiag = nil
        lastWeeklyDiag = nil
    }
    #endif

    private func save() {
        FreezeDiag.context("save() BEFORE", hasChanges: context.hasChanges)
        FreezeDiag.log("SwiftData save() CALLED \(FreezeDiag.caller())")
        try? context.save()
        invalidateCache()
        FreezeDiag.context("save() AFTER", hasChanges: context.hasChanges)
    }

    private func notify() {
        guard !suppressNotify else {
            FreezeDiag.log("notify() SUPPRESSED revision=\(revision)")
            return
        }
        let old = revision
        let new = old + 1
        FreezeDiag.log("REVISION WILL CHANGE old=\(old) new=\(new)")
        FreezeDiag.log("notify() CALLED \(FreezeDiag.caller())")
        revision += 1
        FreezeDiag.log("onRecordsChanged() CALLED")
        onRecordsChanged?()
    }

    /// Diagnostic only — does not mutate state.
    func freezeDiagHasChanges() -> Bool {
        context.hasChanges
    }

    private func requestSync() {
        LaunchLog.sync("request")
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

    nonisolated static func date(on day: Date, timeOfDay: String, calendar: Calendar = clockCalendar()) -> Date? {
        let parts = timeOfDay.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// Gregorian + current time zone — same convention as store DoseLog `scheduledAt`.
    nonisolated static func clockCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    nonisolated static func clockTime(from date: Date, calendar: Calendar = clockCalendar()) -> String {
        String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
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
