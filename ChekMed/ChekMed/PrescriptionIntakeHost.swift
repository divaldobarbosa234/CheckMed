import PhotosUI
import SwiftUI

/// Home / Treatments “add prescription” path: photo, PDF, or manual, then analyse, edit, persist.
struct AddPrescriptionIntakeHost: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(TodayPathStore.self) private var path
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    var onFinished: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @State private var phase: Phase = .choose
    @State private var method: OnboardingAddMethod = .photo
    @State private var draft = OnboardingPrescriptionDraft.empty
    @State private var drafts = [OnboardingPrescriptionDraft.empty]
    @State private var pending: PendingPrescriptionImport = .none
    @State private var showPhotosPicker = false
    @State private var showPDFImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importToken = 0
    @State private var didPersistPlan = false
    @State private var medicineCountAtStart = 0
    @State private var didCaptureStartCount = false
    @State private var detectedDrafts: [OnboardingPrescriptionDraft] = []
    @State private var selectedDetectionKeys: Set<String> = []
    @State private var didNeedSlotGate = false
    @State private var oldPrescriptionWarningDate: Date? = nil
    @State private var laterAddIntent: LaterAddTreatmentIntent = .addToCurrent
    @State private var persistError: String? = nil
    @State private var isPersisting = false

    private enum Phase {
        case choose, camera, manual, analysing, slotLimit, confirm, planResume
    }

    var body: some View {
        Group {
            switch phase {
            case .choose:
                OnboardingAddMedicationView(
                    onPhoto: { start(.photo) { phase = .camera } },
                    onChoosePhotos: { start(.photo) { showPhotosPicker = true } },
                    onPDF: { start(.pdf) { showPDFImporter = true } },
                    onManual: { start(.manual) {
                        draft = .empty
                        drafts = [.empty]
                        pending = .none
                        phase = .manual
                    } },
                    onBack: {
                        if let onCancel {
                            onCancel()
                        } else {
                            dismiss()
                        }
                    },
                    showsTreatmentIntent: asksLaterAddTreatmentIntent,
                    treatmentIntent: $laterAddIntent
                )
            case .camera:
                OnboardingCameraView(
                    onCaptured: { data in
                        pending = .image(Data(data))
                        draft = .empty
                        drafts = [.empty]
                        goAnalysing()
                    },
                    onBack: { phase = .choose }
                )
            case .manual:
                OnboardingManualEntryView(
                    draft: $draft,
                    onContinue: {
                        drafts = [draft]
                        goAnalysing()
                    },
                    onBack: { phase = .choose }
                )
            case .analysing:
                OnboardingAnalysingView(
                    isShort: method == .manual,
                    work: runImport,
                    onFinished: { presentOldPrescriptionWarningOrContinue() },
                    importToken: importToken
                )
            case .slotLimit:
                ScanSlotLimitView(
                    detected: detectedDrafts,
                    existingCount: liveExistingCount,
                    selectedKeys: $selectedDetectionKeys,
                    onUnlockedAll: { continueWithDetectedAll() },
                    onContinueWithSelected: { chosen in
                        drafts = chosen.isEmpty ? [.empty] : chosen
                        draft = drafts[0]
                        phase = .confirm
                    },
                    onBack: { phase = .choose }
                )
            case .confirm:
                OnboardingConfirmView(
                    drafts: $drafts,
                    isManual: method == .manual,
                    existingMedicineCount: liveExistingCount,
                    source: pending,
                    onConfirm: {
                        for index in drafts.indices { drafts[index].syncDoseTimes() }
                        guard canAdvanceToPlanResume() else { return }
                        phase = .planResume
                    },
                    onBack: {
                        if didNeedSlotGate, !entitlements.isSuper {
                            phase = .slotLimit
                        } else {
                            phase = method == .manual ? .manual : .choose
                        }
                    }
                )
            case .planResume:
                PlanResumeView(
                    drafts: journeyDrafts(),
                    persistError: persistError,
                    isPersisting: isPersisting,
                    onDismissPersistError: { persistError = nil },
                    onContinue: finishIntake,
                    onBack: { phase = .confirm }
                )
            }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let compact = PrescriptionReader.downsampledJPEG(from: data)
                    pending = .image(Data(compact))
                    draft = .empty
                    drafts = [.empty]
                    photoItem = nil
                    goAnalysing()
                }
            }
        }
        .prescriptionPDFImporter(isPresented: $showPDFImporter) { url in
            pending = .pdf(url)
            draft = .empty
            drafts = [.empty]
            goAnalysing()
        }
        .onAppear {
            guard !didCaptureStartCount else { return }
            medicineCountAtStart = treatments.storedMedicineCount
            didCaptureStartCount = true
        }
        .onChange(of: entitlements.isSuper) { _, isSuper in
            guard isSuper, phase == .slotLimit else { return }
            continueWithDetectedAll()
        }
        .modifier(OldPrescriptionAgeAlert(
            date: $oldPrescriptionWarningDate,
            onBack: {
                oldPrescriptionWarningDate = nil
                phase = method == .manual ? .manual : .choose
            },
            onContinue: {
                oldPrescriptionWarningDate = nil
                routeAfterDetection()
            }
        ))
    }

    private func journeyDrafts() -> [OnboardingPrescriptionDraft] {
        let live = drafts.filter(\.hasMedicineName)
        if !live.isEmpty { return live }
        return treatments.draftsFromActivePlan().filter(\.hasMedicineName)
    }

    private var liveExistingCount: Int { treatments.storedMedicineCount }

    private var asksLaterAddTreatmentIntent: Bool {
        treatments.hasCurrentTreatment
    }

    private func start(_ next: OnboardingAddMethod, proceed: () -> Void) {
        let ownerId = session.planOwnerId
        guard entitlements.gatePrescriptionAdd(
            method: next,
            existingCount: treatments.intakeOpeningMedicineCount,
            photoPDFUsed: ImportUsage.photoPDFCount(ownerId: ownerId)
        ) else { return }
        method = next
        proceed()
    }

    private func goAnalysing() {
        importToken += 1
        didNeedSlotGate = false
        selectedDetectionKeys = []
        phase = .analysing
    }

    private func runImport() async {
        switch pending {
        case .none:
            if drafts.filter(\.hasMedicineName).isEmpty {
                drafts = [draft]
            }
        case .image(let data):
            let parsed = await PrescriptionReader.drafts(fromImageData: data)
            applyDetected(parsed)
        case .pdf(let url):
            let parsed = await PrescriptionReader.drafts(fromPDF: url)
            applyDetected(parsed)
        }
        if drafts.isEmpty {
            drafts = [.empty]
        }
    }

    private func applyDetected(_ parsed: [OnboardingPrescriptionDraft]) {
        let named = parsed.preparedDetectedMedicines()
        detectedDrafts = named
        selectedDetectionKeys = []
        if named.contains(where: \.hasMedicineName) {
            drafts = named
            draft = drafts[0]
        }
    }

    private func presentOldPrescriptionWarningOrContinue() {
        if method != .manual,
           let date = ScanPipeline.oldPrescriptionDateToWarn(in: detectedDrafts) {
            ScanLog.document("oldPrescription warning date=\(ScanPipeline.iso(date)) thresholdDays=\(ScanPipeline.oldPrescriptionThresholdDays)")
            oldPrescriptionWarningDate = date
            return
        }
        routeAfterDetection()
    }

    private func routeAfterDetection() {
        medicineCountAtStart = treatments.storedMedicineCount
        let named = detectedDrafts.uniqueNamedMedicines
        let existing = medicineCountAtStart
        ScanLog.document("slotGate detected=\(named.count) existing=\(existing) remaining=\(entitlements.freeMedicineSlotsRemaining(existingCount: existing))")
        if method != .manual,
           entitlements.needsScanSlotLimit(detectedCount: named.count, existingCount: existing) {
            didNeedSlotGate = true
            drafts = named.isEmpty ? [.empty] : named
            phase = .slotLimit
            return
        }
        didNeedSlotGate = false
        drafts = named.isEmpty ? drafts : named
        if drafts.isEmpty { drafts = [.empty] }
        phase = .confirm
    }

    private func continueWithDetectedAll() {
        let named = detectedDrafts.uniqueNamedMedicines
        drafts = named.isEmpty ? [.empty] : named
        draft = drafts[0]
        didNeedSlotGate = false
        phase = .confirm
    }

    private var laterAddPersistTarget: LaterAddPersistTarget {
        LaterAddPersist.target(
            intent: laterAddIntent,
            hasCurrentTreatment: treatments.hasCurrentTreatment
        )
    }

    private var laterAddDraftOccupancyBase: Int {
        LaterAddPersist.draftOccupancyBase(
            target: laterAddPersistTarget,
            liveCount: treatments.storedMedicineCount,
            capturedLiveCount: medicineCountAtStart,
            occupancyIfCurrentCompleted: treatments.medicineCountIfCurrentTreatmentsCompleted
        )
    }

    /// In-memory drafts only. Persist happens on Plan Resume Continue.
    private func canAdvanceToPlanResume() -> Bool {
        let liveCount = treatments.storedMedicineCount
        let capBase = laterAddDraftOccupancyBase
        let capped = drafts.cappedForPlan(
            isSuper: entitlements.isSuper,
            existingCount: capBase
        ).filter(\.hasMedicineName)
        guard !capped.isEmpty else {
            #if DEBUG
            print("[CheckMed] add-intake plan-resume blocked: empty after cap")
            #endif
            if !entitlements.isSuper,
               liveCount >= SuperLimits.freePrescriptions {
                entitlements.presentPaywall()
            }
            return false
        }
        return true
    }

    /// Commit on Plan Resume Continue. Confirm only advances in memory.
    private enum PersistDraftsResult {
        case success
        case blocked
        case failed
    }

    @discardableResult
    private func persistConfirmedDrafts() -> PersistDraftsResult {
        let liveCount = treatments.storedMedicineCount
        let persistTarget = laterAddPersistTarget
        let capBase = laterAddDraftOccupancyBase
        let capped = drafts.cappedForPlan(
            isSuper: entitlements.isSuper,
            existingCount: capBase
        ).filter(\.hasMedicineName)
        ScanLog.confirmed(capped)
        guard !capped.isEmpty else {
            #if DEBUG
            print("[CheckMed] add-intake confirm blocked: empty after cap")
            #endif
            if !entitlements.isSuper,
               liveCount >= SuperLimits.freePrescriptions {
                entitlements.presentPaywall()
            }
            return .blocked
        }
        let ok: Bool
        var persistedTreatmentId: UUID?
        if didPersistPlan {
            // Already wrote this intake once; avoid duplicate rows on confirm → back → confirm.
            ok = true
        } else if persistTarget == .completeThenSeed {
            let previousId = treatments.existingCurrentPlanId()
            persistedTreatmentId = treatments.startNewTreatmentFromDrafts(
                capped,
                ownerId: session.planOwnerId,
                profileId: session.planProfileId,
                maximumActiveMedicines: entitlements.maximumActiveMedicines
            )
            ok = persistedTreatmentId != nil
            #if DEBUG
            let newId = treatments.existingCurrentPlanId()
            print(
                "[TREATMENT-ID] startNew previous=\(previousId?.uuidString ?? "nil") "
                + "new=\(newId?.uuidString ?? "nil") persist=\(persistedTreatmentId?.uuidString ?? "nil") "
                + "differ=\(previousId != newId) live=\(treatments.hasLivePlanInSelectedProfile)"
            )
            #endif
        } else if persistTarget == .seed {
            persistedTreatmentId = treatments.seedFromDrafts(
                capped,
                ownerId: session.planOwnerId,
                profileId: session.planProfileId,
                maximumActiveMedicines: entitlements.maximumActiveMedicines
            )
            ok = persistedTreatmentId != nil
        } else {
            persistedTreatmentId = treatments.addFromDrafts(
                capped,
                ownerId: session.planOwnerId,
                profileId: session.planProfileId,
                maximumActiveMedicines: entitlements.maximumActiveMedicines
            )
            ok = persistedTreatmentId != nil
        }
        guard ok else {
            #if DEBUG
            print("[CheckMed] persistConfirmedDrafts failed")
            #endif
            return .failed
        }
        let firstPersist = !didPersistPlan
        didPersistPlan = true
        IntakeConfirmSessionEffects.applySuccessfulPersist(session: session, treatments: treatments)
        if firstPersist, let persistedTreatmentId {
            treatments.archiveImportedSource(pending, treatmentId: persistedTreatmentId)
        }
        if firstPersist, method == .photo || method == .pdf {
            ImportUsage.incrementPhotoPDF(ownerId: session.planOwnerId)
        }
        path.reload()
        return .success
    }

    private func finishIntake() {
        guard !isPersisting else { return }
        isPersisting = true
        persistError = nil
        let result = persistConfirmedDrafts()
        isPersisting = false
        switch result {
        case .blocked:
            return
        case .failed:
            persistError = session.t(.planPersistFailedBody)
            return
        case .success:
            break
        }
        IntakeConfirmSessionEffects.applyFinish(session: session)
        switch IntakeConfirmNavigation.destination(
            hasCompletedOnboarding: session.hasCompletedOnboarding
        ) {
        case .originatingSurface:
            dismiss()
        case .postJourneySetup:
            if let onFinished {
                onFinished()
            } else {
                session.beginResumeSetup()
                dismiss()
            }
        }
    }
}
