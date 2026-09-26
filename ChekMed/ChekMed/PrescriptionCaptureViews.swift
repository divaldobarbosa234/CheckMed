import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CameraCaptureView: UIViewControllerRepresentable {
    var onComplete: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (Data?) -> Void

        init(onComplete: @escaping (Data?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.originalImage] as? UIImage)
            let data = image.flatMap { PrescriptionReader.jpeg(from: $0) }
            onComplete(data)
        }
    }
}

struct PrescriptionPDFImporter: ViewModifier {
    @Binding var isPresented: Bool
    var onURL: (URL) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("checkmed-\(UUID().uuidString).pdf")
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                do {
                    let data = try Data(contentsOf: url)
                    try data.write(to: destination, options: .atomic)
                } catch {
                    #if DEBUG
                    print("[SOURCE] PDF IMPORT COPY FAILURE dest=\(destination.lastPathComponent) error=\(error.localizedDescription)")
                    #endif
                    return
                }
            }
            guard FileManager.default.fileExists(atPath: destination.path),
                  ((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
            else {
                #if DEBUG
                print("[SOURCE] PDF IMPORT EMPTY dest=\(destination.lastPathComponent)")
                #endif
                return
            }
            onURL(destination)
        }
    }
}

extension View {
    func prescriptionPDFImporter(isPresented: Binding<Bool>, onURL: @escaping (URL) -> Void) -> some View {
        modifier(PrescriptionPDFImporter(isPresented: isPresented, onURL: onURL))
    }
}

enum PendingPrescriptionImport {
    case none
    case image(Data)
    case pdf(URL)

    var showsOriginalPreview: Bool {
        switch self {
        case .none:
            return false
        case .image(let data):
            return UIImage(data: data) != nil
        case .pdf(let url):
            return FileManager.default.fileExists(atPath: url.path)
        }
    }
}

/// Compact original + larger sheet. Does not own or persist `PendingPrescriptionImport`.
struct ConfirmOriginalPrescriptionCard: View {
    @Environment(SessionStore.self) private var session
    let source: PendingPrescriptionImport
    @State private var showOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.confirmOriginalPrescription))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            compactPreview
                .frame(maxWidth: .infinity)
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture { showOriginal = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(session.t(.confirmViewOriginal))
            Button(session.t(.confirmViewOriginal)) { showOriginal = true }
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.primaryShadow)
                .frame(minHeight: 44)
            Text(session.t(.confirmCheckDetected))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showOriginal) {
            PendingImportOriginalSheet(source: source)
        }
    }

    @ViewBuilder
    private var compactPreview: some View {
        switch source {
        case .none:
            EmptyView()
        case .image(let data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 148)
                    .background(CheckMedTheme.surface)
            }
        case .pdf(let url):
            PDFKitRepresentedView(url: url)
        }
    }
}

struct PendingImportOriginalSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let source: PendingPrescriptionImport

    var body: some View {
        NavigationStack {
            Group {
                switch source {
                case .none:
                    Text(session.t(.reportMissingSection))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                case .image(let data):
                    if let image = UIImage(data: data) {
                        ScrollView {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        }
                    } else {
                        Text(session.t(.reportMissingSection))
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                case .pdf(let url):
                    PDFKitRepresentedView(url: url)
                }
            }
            .background(CheckMedTheme.background)
            .navigationTitle(session.t(.confirmOriginalPrescription))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.t(.done)) { dismiss() }
                }
            }
        }
    }
}

struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

/// One original file per treatment UUID. Medicine edits never rewrite these files.
/// A newly confirmed PDF/photo for the same treatment replaces the previous file.
enum PrescriptionSourceArchive {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("CheckMed/PrescriptionSources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for treatmentId: UUID) -> URL? {
        let jpeg = folder.appendingPathComponent("\(treatmentId.uuidString).jpg")
        let pdf = folder.appendingPathComponent("\(treatmentId.uuidString).pdf")
        if usableFile(jpeg) { return jpeg }
        if usableFile(pdf) { return pdf }
        return nil
    }

    static func save(_ pending: PendingPrescriptionImport, treatmentId: UUID) {
        let pendingKind: String
        switch pending {
        case .none: pendingKind = "none"
        case .image: pendingKind = "image"
        case .pdf: pendingKind = "pdf"
        }
        #if DEBUG
        print("[SOURCE] ARCHIVE START pending=\(pendingKind) treatmentId=\(treatmentId.uuidString)")
        #endif
        switch pending {
        case .none:
            #if DEBUG
            print("[SOURCE] ARCHIVE SKIP pending=none treatmentId=\(treatmentId.uuidString)")
            #endif
            return
        case .image(let data):
            let dest = folder.appendingPathComponent("\(treatmentId.uuidString).jpg")
            removeFiles(for: treatmentId)
            guard let jpeg = jpegDataForArchive(data), !jpeg.isEmpty else {
                #if DEBUG
                print("[SOURCE] ARCHIVE FAILURE dest=\(dest.lastPathComponent) error=empty-jpeg")
                #endif
                return
            }
            writeFile(jpeg, to: dest)
        case .pdf(let source):
            let dest = folder.appendingPathComponent("\(treatmentId.uuidString).pdf")
            removeFiles(for: treatmentId)
            copyPDF(from: source, to: dest)
        }
    }

    private static func removeFiles(for treatmentId: UUID) {
        let jpeg = folder.appendingPathComponent("\(treatmentId.uuidString).jpg")
        let pdf = folder.appendingPathComponent("\(treatmentId.uuidString).pdf")
        try? FileManager.default.removeItem(at: jpeg)
        try? FileManager.default.removeItem(at: pdf)
    }

    private static func copyPDF(from source: URL, to dest: URL) {
        #if DEBUG
        print("[SOURCE] ARCHIVE dest=\(dest.lastPathComponent)")
        #endif
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            #if DEBUG
            print("[SOURCE] ARCHIVE SUCCESS dest=\(dest.lastPathComponent)")
            #endif
        } catch {
            do {
                let data = try Data(contentsOf: source)
                try data.write(to: dest, options: .atomic)
                #if DEBUG
                print("[SOURCE] ARCHIVE SUCCESS dest=\(dest.lastPathComponent) via-data")
                #endif
            } catch {
                #if DEBUG
                print(
                    "[SOURCE] ARCHIVE FAILURE dest=\(dest.lastPathComponent) source=\(source.lastPathComponent) "
                    + "error=\(error.localizedDescription)"
                )
                #endif
            }
        }
    }

    private static func usableFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    private static func jpegDataForArchive(_ data: Data) -> Data? {
        let owned = Data(data)
        if let image = UIImage(data: owned), let jpeg = PrescriptionReader.jpeg(from: image) {
            return jpeg
        }
        return owned.isEmpty ? nil : owned
    }

    private static func writeFile(_ data: Data, to dest: URL) {
        #if DEBUG
        print("[SOURCE] ARCHIVE dest=\(dest.lastPathComponent)")
        #endif
        do {
            try data.write(to: dest, options: .atomic)
            #if DEBUG
            print("[SOURCE] ARCHIVE SUCCESS dest=\(dest.lastPathComponent)")
            #endif
        } catch {
            #if DEBUG
            print("[SOURCE] ARCHIVE FAILURE dest=\(dest.lastPathComponent) error=\(error.localizedDescription)")
            #endif
        }
    }
}

extension PendingPrescriptionImport {
    var consumesPhotoPDFQuota: Bool {
        switch self {
        case .none: false
        case .image, .pdf: true
        }
    }
}
