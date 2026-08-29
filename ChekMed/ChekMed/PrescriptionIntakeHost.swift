import PhotosUI
import SwiftUI

/// Home / Treatments “add prescription” path: photo, PDF, or manual, then analyse, edit, persist.
struct AddPrescriptionIntakeHost: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(TodayPathStore.self) private var path
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .choose
    @State private var method: OnboardingAddMethod = .photo
    @State private var draft = OnboardingPrescriptionDraft.empty
    @State private var pending: PendingPrescriptionImport = .none
    @State private var showPhotosPicker = false
    @State private var showPDFImporter = false
    @State private var photoItem: PhotosPickerItem?

    private enum Phase {
        case choose, camera, manual, analysing, confirm
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
                        pending = .none
                        phase = .manual
                    } },
                    onBack: { dismiss() }
                )
            case .camera:
                OnboardingCameraView(
                    onCaptured: { data in
                        pending = .image(data)
                        draft = .empty
                        phase = .analysing
                    },
                    onBack: { phase = .choose }
                )
            case .manual:
                OnboardingManualEntryView(
                    draft: $draft,
                    onContinue: { phase = .analysing },
                    onBack: { phase = .choose }
                )
            case .analysing:
                OnboardingAnalysingView(isShort: method == .manual, work: runImport) {
                    phase = .confirm
                }
            case .confirm:
                OnboardingConfirmView(
                    draft: $draft,
                    isManual: method == .manual,
                    onConfirm: confirm,
                    onBack: {
                        phase = method == .manual ? .manual : .choose
                    }
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
                    photoItem = nil
                    phase = .analysing
                }
            }
        }
        .prescriptionPDFImporter(isPresented: $showPDFImporter) { url in
            pending = .pdf(url)
            draft = .empty
            phase = .analysing
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

    private func runImport() async {
        switch pending {
        case .none:
            break
        case .image(let data):
            draft = await PrescriptionReader.draft(fromImageData: data)
            pending = .none
        case .pdf(let url):
            draft = await PrescriptionReader.draft(fromPDF: url)
            pending = .none
        }
    }

    private func confirm() {
        treatments.addFromDraft(
            draft,
            ownerId: session.auth.userId,
            profileId: session.profileId
        )
        if method == .photo || method == .pdf {
            ImportUsage.incrementPhotoPDF(ownerId: session.auth.userId)
        }
        path.reload()
        dismiss()
    }
}
