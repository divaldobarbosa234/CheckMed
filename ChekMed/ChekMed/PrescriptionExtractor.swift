import Foundation
import UIKit
import Vision

/// Image → medicine candidates. Low-confidence hits never auto-save; the user confirms on the edit screen.
protocol PrescriptionExtracting: Sendable {
    func extractMedicines(fromImageData data: Data) async -> PrescriptionExtraction
}

struct PrescriptionExtraction: Sendable, Equatable {
    var rawText: String
    var draft: OnboardingPrescriptionDraft
    var candidates: [String]
    var engine: String
    var confidence: Confidence

    enum Confidence: String, Sendable {
        case none
        case low
        case high
    }

    static let empty = PrescriptionExtraction(
        rawText: "",
        draft: .empty,
        candidates: [],
        engine: "none",
        confidence: .none
    )

    var shouldPrefillMedicine: Bool {
        confidence == .high && !draft.medicine.isEmpty
    }
}

enum PrescriptionExtractorChain {
    /// Document AI (if configured) → Cloud Vision DOCUMENT_TEXT_DETECTION → on-device Vision.
    /// Cloud is skipped when keys/credentials are empty. Parser + catalog never invent INNs from scrawl.
    static func extract(fromImageData data: Data) async -> PrescriptionExtraction {
        let jpeg = PrescriptionReader.downsampledJPEG(from: data)
        if GoogleCloudOCR.documentAIConfig() != nil,
           let text = await GoogleCloudOCR.documentAIText(data: jpeg, mimeType: "image/jpeg") {
            return VisionPrescriptionExtractor.extraction(from: text, engine: "google.documentai")
        }
        if let key = GoogleCloudOCR.visionAPIKey(),
           let text = await GoogleCloudOCR.visionDocumentText(jpeg: jpeg, apiKey: key) {
            return VisionPrescriptionExtractor.extraction(from: text, engine: "google.vision.document_text")
        }
        if let azure = OptionalCloudHandwritingExtractor.azureIfConfigured() {
            let remote = await azure.extractMedicines(fromImageData: jpeg)
            if !remote.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return remote
            }
        }
        return await VisionPrescriptionExtractor().extractMedicines(fromImageData: jpeg)
    }

    static func extract(fromPDF url: URL) async -> PrescriptionExtraction {
        let pdfData = (try? Data(contentsOf: url)) ?? Data()
        if GoogleCloudOCR.documentAIConfig() != nil, !pdfData.isEmpty,
           let text = await GoogleCloudOCR.documentAIText(data: pdfData, mimeType: "application/pdf") {
            return VisionPrescriptionExtractor.extraction(from: text, engine: "google.documentai")
        }
        if let key = GoogleCloudOCR.visionAPIKey(),
           let jpeg = PrescriptionReader.jpegPages(fromPDF: url),
           let text = await GoogleCloudOCR.visionDocumentText(jpeg: jpeg, apiKey: key) {
            return VisionPrescriptionExtractor.extraction(from: text, engine: "google.vision.document_text")
        }
        let text = await PrescriptionReader.pdfText(from: url)
        return VisionPrescriptionExtractor.extraction(from: text, engine: "pdf+vision")
    }
}

struct VisionPrescriptionExtractor: PrescriptionExtracting {
    func extractMedicines(fromImageData data: Data) async -> PrescriptionExtraction {
        let text = await PrescriptionReader.recognizeText(from: data)
        return Self.extraction(from: text, engine: "vision.accurate")
    }

    static func extraction(from text: String, engine: String) -> PrescriptionExtraction {
        let parsed = PrescriptionParser.parse(text)
        let catalogHits = MedicationCatalog.wholeWordHits(in: text)
        if parsed.hasMedicineName {
            return PrescriptionExtraction(
                rawText: text,
                draft: parsed,
                candidates: unique([parsed.medicine] + catalogHits),
                engine: engine,
                confidence: .high
            )
        }
        if let first = catalogHits.first {
            var draft = OnboardingPrescriptionDraft.empty
            draft.medicine = first
            draft.dose = parsed.dose
            draft.frequency = parsed.frequency
            draft.duration = parsed.duration
            return PrescriptionExtraction(
                rawText: text,
                draft: draft,
                candidates: catalogHits,
                engine: engine + "+catalog-token",
                confidence: .low
            )
        }
        return PrescriptionExtraction(
            rawText: text,
            draft: .empty,
            candidates: [],
            engine: engine,
            confidence: .none
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}

/// Optional Azure Document Intelligence when those keys are in Info.plist. Google OCR lives in `GoogleCloudOCR`.
struct OptionalCloudHandwritingExtractor: PrescriptionExtracting {
    var endpoint: String
    var key: String

    static func azureIfConfigured() -> OptionalCloudHandwritingExtractor? {
        guard let endpoint = SecretPlist.nonEmpty("AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT"),
              let key = SecretPlist.nonEmpty("AZURE_DOCUMENT_INTELLIGENCE_KEY")
        else { return nil }
        return OptionalCloudHandwritingExtractor(endpoint: endpoint, key: key)
    }

    func extractMedicines(fromImageData data: Data) async -> PrescriptionExtraction {
        let jpeg = PrescriptionReader.downsampledJPEG(from: data)
        guard let text = await Self.azureRead(jpeg: jpeg, endpoint: endpoint, key: key) else {
            return .empty
        }
        return VisionPrescriptionExtractor.extraction(from: text, engine: "azure.document_intelligence")
    }

    /// Azure prebuilt-read. Endpoint example: `https://{resource}.cognitiveservices.azure.com`.
    private static func azureRead(jpeg: Data, endpoint: String, key: String) async -> String? {
        let base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/formrecognizer/documentModels/prebuilt-read:analyze?api-version=2024-11-30") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg
        request.timeoutInterval = 20
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let operation = http.value(forHTTPHeaderField: "Operation-Location"),
              let pollURL = URL(string: operation)
        else { return nil }
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            var poll = URLRequest(url: pollURL)
            poll.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            guard let (data, _) = try? await URLSession.shared.data(for: poll),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let status = (json["status"] as? String)?.lowercased()
            if status == "failed" { return nil }
            guard status == "succeeded" else { continue }
            if let analyze = json["analyzeResult"] as? [String: Any],
               let content = analyze["content"] as? String {
                return content
            }
            return nil
        }
        return nil
    }
}

enum PrescriptionExtractionNotes {
    /// Keys in Secrets.xcconfig → Info.plist. Empty keys keep on-device Vision. Never invent INNs from scrawl; user confirms.
    /// GOOGLE_CLOUD_VISION_API_KEY (Cloud Vision, not iOS OAuth). Document AI: GOOGLE_CLOUD_PROJECT_ID,
    /// GOOGLE_DOCUMENT_AI_LOCATION, GOOGLE_DOCUMENT_AI_PROCESSOR_ID, plus gitignored GoogleDocumentAI.json
    /// (GOOGLE_APPLICATION_CREDENTIALS / GOOGLE_DOCUMENT_AI_CREDENTIALS_PATH). API key for Document AI only if Google allows it.
    static let architecture = "documentai → vision.document_text → vision.accurate → user confirm"
}
