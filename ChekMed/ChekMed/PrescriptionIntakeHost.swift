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

    private enum Phase {
        case choose, camera, manual, analysing, confirm, planResume
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
                    onFinished: { phase = .confirm },
                    importToken: importToken
                )
            case .confirm:
                OnboardingConfirmView(
                    drafts: $drafts,
                    isManual: method == .manual,
                    onConfirm: {
                        for index in drafts.indices { drafts[index].syncDoseTimes() }
                        phase = .planResume
                    },
                    onBack: {
                        phase = method == .manual ? .manual : .choose
                    }
                )
            case .planResume:
                PlanResumeView(
                    drafts: drafts.filter(\.hasMedicineName),
                    onContinue: confirm,
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
    }

    private func start(_ next: OnboardingAddMethod, proceed: () -> Void) {
        let ownerId = session.auth.userId
        guard entitlements.gatePrescriptionAdd(
            method: next,
            existingCount: treatments.activeTreatmentCount,
            photoPDFUsed: ImportUsage.photoPDFCount(ownerId: ownerId)
        ) else { return }
        method = next
        proceed()
    }

    private func goAnalysing() {
        importToken += 1
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
            if parsed.contains(where: \.hasMedicineName) {
                drafts = cappedMedicines(parsed)
                draft = drafts[0]
            }
        case .pdf(let url):
            let parsed = await PrescriptionReader.drafts(fromPDF: url)
            if parsed.contains(where: \.hasMedicineName) {
                drafts = cappedMedicines(parsed)
                draft = drafts[0]
            }
        }
        if drafts.isEmpty {
            drafts = [.empty]
        }
    }

    private func cappedMedicines(_ parsed: [OnboardingPrescriptionDraft]) -> [OnboardingPrescriptionDraft] {
        let named = parsed.filter(\.hasMedicineName)
        let cap = entitlements.isSuper ? 12 : SuperLimits.freePrescriptions
        let sliced = Array(named.prefix(cap))
        return sliced.isEmpty ? [.empty] : sliced
    }

    private func confirm() {
        let named = drafts.filter(\.hasMedicineName)
        let room = entitlements.isSuper
            ? named.count
            : min(named.count, SuperLimits.freePrescriptions)
        treatments.addFromDrafts(
            Array(named.prefix(room)),
            ownerId: session.auth.userId,
            profileId: session.profileId
        )
        if method == .photo || method == .pdf {
            ImportUsage.incrementPhotoPDF(ownerId: session.auth.userId)
        }
        path.reload()
        if let onFinished {
            onFinished()
        } else {
            dismiss()
        }
    }
}
