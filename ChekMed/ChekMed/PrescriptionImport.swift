import Foundation
import PDFKit
import UIKit
import Vision

enum SuperLimits {
    static let freePrescriptions = 3
    static let freePhotoPDFItems = 1
    static let superPhotoPDFItems = 5
}

enum ImportUsage {
    private static func photoKey(_ ownerId: UUID?) -> String {
        "checkmed.photoPDFCount.\(ownerId?.uuidString ?? "local")"
    }

    static func photoPDFCount(ownerId: UUID?) -> Int {
        UserDefaults.standard.integer(forKey: photoKey(ownerId))
    }

    static func incrementPhotoPDF(ownerId: UUID?) {
        let key = photoKey(ownerId)
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}

extension EntitlementStore {
    func allowsNewPrescription(existingCount: Int) -> Bool {
        if existingCount == 0 { return true }
        if isSuper { return true }
        return existingCount < SuperLimits.freePrescriptions
    }

    func allowsPhotoPDF(usedCount: Int, existingTreatments: Int) -> Bool {
        if existingTreatments == 0 { return true }
        let cap = isSuper ? SuperLimits.superPhotoPDFItems : SuperLimits.freePhotoPDFItems
        return usedCount < cap
    }

    @discardableResult
    func gatePrescriptionAdd(
        method: OnboardingAddMethod,
        existingCount: Int,
        photoPDFUsed: Int
    ) -> Bool {
        if !allowsNewPrescription(existingCount: existingCount) {
            presentPaywall()
            return false
        }
        if method == .photo || method == .pdf {
            if !allowsPhotoPDF(usedCount: photoPDFUsed, existingTreatments: existingCount) {
                presentPaywall()
                return false
            }
        }
        return true
    }
}

enum PrescriptionReader {
    static func draft(fromImageData data: Data) async -> OnboardingPrescriptionDraft {
        let extraction = await PrescriptionExtractorChain.extract(fromImageData: data)
        return extraction.draft
    }

    static func draft(fromPDF url: URL) async -> OnboardingPrescriptionDraft {
        let extraction = await PrescriptionExtractorChain.extract(fromPDF: url)
        return extraction.draft
    }

    static func recognizeText(from data: Data) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: recognizeTextSync(from: data))
            }
        }
    }

    static func pdfText(from url: URL) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: pdfTextSync(from: url))
            }
        }
    }

    nonisolated static func downsampledJPEG(from data: Data, maxDimension: CGFloat = 1600) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return jpeg(from: image, maxDimension: maxDimension) ?? data
    }

    nonisolated static func jpegPages(fromPDF url: URL, maxPages: Int = 3) -> Data? {
        guard let document = PDFDocument(url: url) else { return nil }
        let limit = min(document.pageCount, maxPages)
        for index in 0..<limit {
            guard let page = document.page(at: index),
                  let cgImage = rasterize(page)
            else { continue }
            let image = UIImage(cgImage: cgImage)
            if let jpeg = jpeg(from: image) { return jpeg }
        }
        return nil
    }

    nonisolated static func jpeg(from image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let size = image.size
        guard size.width > 1, size.height > 1 else {
            return image.jpegData(compressionQuality: 0.82)
        }
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let newSize = CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }

    nonisolated private static func recognizeTextSync(from data: Data) -> String {
        let compact = downsampledJPEG(from: data)
        guard let image = UIImage(data: compact), let cgImage = image.cgImage else { return "" }
        return ocr(cgImage)
    }

    nonisolated private static func pdfTextSync(from url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var text = ""
        let pageCount = min(document.pageCount, 6)
        for index in 0..<pageCount {
            if let page = document.page(at: index), let pageText = page.string, !pageText.isEmpty {
                text += pageText
                text += "\n"
            }
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 24 {
            return text
        }
        var ocrText = ""
        let rasterLimit = min(document.pageCount, 3)
        for index in 0..<rasterLimit {
            guard let page = document.page(at: index), let image = rasterize(page) else { continue }
            ocrText += ocr(image)
            ocrText += "\n"
        }
        return (text + "\n" + ocrText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func rasterize(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let longest = max(bounds.width, bounds.height)
        let scale = longest > 0 ? min(2.2, 1600 / longest) : 1
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
        return image.cgImage
    }

    nonisolated private static func ocr(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.012
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

enum PrescriptionParser {
    private static let stopNames: Set<String> = [
        "patient", "paciente", "doente", "name", "nome", "nombre", "nom",
        "doctor", "doutor", "médico", "medico", "docteur", "physician", "prescriber",
        "date", "data", "fecha", "pharmacy", "farmácia", "farmacia", "pharmacie",
        "address", "endereço", "endereco", "dirección", "adresse",
        "signature", "assinatura", "firma", "refill", "quantity", "quantidade", "cantidad", "quantité",
        "instructions", "instruções", "instrucciones", "take", "tomar", "prendre",
        "tablet", "tablets", "capsule", "capsules", "comprimido", "comprimidos",
        "morning", "afternoon", "evening", "night", "manhã", "tarde", "noite",
        "prescription", "receita", "receta", "ordonnance", "rx", "qty", "sig",
        "hospital", "clinic", "clínica", "clinica", "phone", "telefone", "teléfono",
        "age", "idade", "edad", "âge", "sex", "sexo", "gender", "gênero",
        "weight", "peso", "dr",
    ]

    static func parse(_ raw: String) -> OnboardingPrescriptionDraft {
        let cleaned = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let medicine = findMedicine(in: lines, raw: cleaned) else {
            return .empty
        }
        return OnboardingPrescriptionDraft(
            medicine: medicine,
            dose: findDose(in: cleaned),
            frequency: findFrequency(in: cleaned),
            duration: findDuration(in: cleaned)
        )
    }

    private static func findMedicine(in lines: [String], raw: String) -> String? {
        let strength = try? NSRegularExpression(
            pattern: #"(?i)\b([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\-]{2,}(?:\s+[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\-]{2,}){0,3})\s+(\d+(?:[.,]\d+)?\s*(?:mg|mcg|µg|ug|g|ml|ui|iu|%))\b"#
        )
        for line in lines {
            guard let strength, let match = strength.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let doseRange = Range(match.range(at: 2), in: line)
            else { continue }
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
            let dose = String(line[doseRange]).replacingOccurrences(of: " ", with: "")
            if isPlausibleName(name) {
                return "\(name) \(dose.lowercased())"
            }
        }

        let labeled = try? NSRegularExpression(
            pattern: #"(?i)\b(?:medicine|medication|medicamento|médicament|drug|rx)\s*[:\-]\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\- ]{2,40})"#
        )
        if let labeled, let match = labeled.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let range = Range(match.range(at: 1), in: raw) {
            let name = String(raw[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlausibleName(name) { return name }
        }

        for line in lines where line.count >= 5 && line.count <= 48 {
            let words = line.split(separator: " ").map(String.init)
            guard words.count <= 4, words.allSatisfy({ $0.first?.isLetter == true }) else { continue }
            if isPlausibleName(line), looksLikeDrugToken(line) {
                return line
            }
        }
        return nil
    }

    private static func findDose(in raw: String) -> String {
        let pattern = #"(?i)\b(\d+(?:[.,]\d+)?\s*(?:capsule|capsules|tablet|tablets|pill|pills|comprimido|comprimidos|cápsula|capsula|gélule|gelule|ml|puff|puffs|drop|drops|gota|gotas))\b"#
        if let match = firstGroup(pattern, in: raw) {
            return match.replacingOccurrences(of: "  ", with: " ")
        }
        return ""
    }

    private static func findFrequency(in raw: String) -> String {
        let patterns = [
            #"(?i)\b(\d+\s*[x×]\s*(?:daily|a day|ao dia|por dia|al día|al dia|par jour|die))\b"#,
            #"(?i)\b((?:once|twice|one time|two times|three times|four times|1 time|2 times|3 times|4 times)\s+(?:daily|a day))\b"#,
            #"(?i)\b((?:uma|duas|três|tres|quatro)\s+vezes?\s+(?:ao dia|por dia|al día|al dia|par jour))\b"#,
            #"(?i)\b(every\s+\d+\s+hours?|cada\s+\d+\s+horas?|todas as\s+\d+\s+horas?|toutes les\s+\d+\s+heures?)\b"#,
            #"(?i)\b(as needed|quando necessário|quando necessario|si besoin|según necesidad|segun necesidad|prn)\b"#,
            #"(?i)\b(bid|tid|qid|qd)\b"#,
        ]
        for pattern in patterns {
            if let match = firstGroup(pattern, in: raw) {
                return normalizeFrequency(match)
            }
        }
        return ""
    }

    private static func findDuration(in raw: String) -> String {
        let pattern = #"(?i)\b(?:for|durante|pendant|por)?\s*(\d+\s*(?:day|days|dia|dias|días|dias|jour|jours|week|weeks|semana|semanas|semaine|semaines))\b"#
        if let match = firstGroup(pattern, in: raw) {
            return match.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    private static func normalizeFrequency(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("tid") || lower.contains("3") { return value }
        if lower.contains("qid") || lower.contains("4") { return value }
        if lower.contains("bid") || lower.contains("2") { return value }
        return value
    }

    private static func isPlausibleName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        let first = trimmed.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        if stopNames.contains(first) { return false }
        if stopNames.contains(trimmed.lowercased()) { return false }
        let letters = trimmed.filter(\.isLetter)
        return letters.count >= 3
    }

    private static func looksLikeDrugToken(_ name: String) -> Bool {
        let lower = name.lowercased()
        let suffixes = [
            "cillin", "mycin", "cycline", "prazole", "olol", "pril", "sartan",
            "statin", "azole", "dipine", "tidine", "xaban", "parin", "mab",
            "nazol", "vir", "caine", "formin", "gliptin", "gliflozin",
        ]
        if suffixes.contains(where: { lower.contains($0) }) { return true }
        return false
    }

    private static func firstGroup(_ pattern: String, in raw: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: raw)
        else { return nil }
        return String(raw[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
