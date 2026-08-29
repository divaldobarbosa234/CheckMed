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
                onURL(destination)
            } catch {
                onURL(url)
            }
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
}

extension PendingPrescriptionImport {
    var consumesPhotoPDFQuota: Bool {
        switch self {
        case .none: false
        case .image, .pdf: true
        }
    }
}
