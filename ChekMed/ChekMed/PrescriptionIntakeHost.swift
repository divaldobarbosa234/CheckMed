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
                    }
                )
            case .camera:
                OnboardingCameraView(
                    onCaptured: { data in
                        pending = .image(data)
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
                    onConfirm: {
                        for index in drafts.indices { drafts[index].syncDoseTimes() }
                        guard persistConfirmedDrafts() else { return }
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
                    pending = .image(compact)
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
        let stored = treatments.draftsFromActivePlan().filter(\.hasMedicineName)
        if !stored.isEmpty { return stored }
        return drafts.filter(\.hasMedicineName)
    }

    private var liveExistingCount: Int { treatments.storedMedicineCount }

    private func start(_ next: OnboardingAddMethod, proceed: () -> Void) {
        let ownerId = session.planOwnerId
        guard entitlements.gatePrescriptionAdd(
            method: next,
            existingCount: treatments.storedMedicineCount,
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

    /// Persist on confirm (before journey) so Home never depends on PlanResume continue.
    @discardableResult
    private func persistConfirmedDrafts() -> Bool {
        let liveCount = treatments.storedMedicineCount
        let capBase = min(medicineCountAtStart, liveCount)
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
            return false
        }
        let ok: Bool
        if didPersistPlan {
            // Already wrote this intake once; avoid duplicate rows on confirm → back → confirm.
            ok = true
        } else if liveCount == 0 {
            ok = treatments.seedFromDrafts(
                capped,
                ownerId: session.planOwnerId,
                profileId: session.planProfileId
            )
        } else {
            ok = treatments.addFromDrafts(
                capped,
                ownerId: session.planOwnerId,
                profileId: session.planProfileId
            )
        }
        guard ok else {
            #if DEBUG
            print("[CheckMed] persistConfirmedDrafts failed")
            #endif
            return false
        }
        let firstPersist = !didPersistPlan
        didPersistPlan = true
        session.markMedicationPlanConfirmed()
        // Always arm post-journey chain after any successful confirm (seed or add).
        session.markPendingPostJourneySetup()
        treatments.setSurfacesPlan(true)
        if firstPersist {
            treatments.archiveImportedSource(pending)
        }
        if firstPersist, method == .photo || method == .pdf {
            ImportUsage.incrementPhotoPDF(ownerId: session.planOwnerId)
        }
        path.reload()
        return true
    }

    private func finishIntake() {
        if !didPersistPlan {
            guard persistConfirmedDrafts() else { return }
        }
        // After journey: always alarms → notifications → Super → Phil before Home.
        session.startPostJourneyQueue()
        if let onFinished {
            onFinished()
        } else {
            session.beginResumeSetup()
            dismiss()
        }
    }
}
