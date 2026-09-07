import CryptoKit
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
        (await drafts(fromImageData: data)).first ?? .empty
    }

    static func draft(fromPDF url: URL) async -> OnboardingPrescriptionDraft {
        (await drafts(fromPDF: url)).first ?? .empty
    }

    static func drafts(fromImageData data: Data) async -> [OnboardingPrescriptionDraft] {
        if let cached = OCRDraftCache.drafts(for: data) { return cached }
        let extraction = await PrescriptionExtractorChain.extract(fromImageData: data)
        let result = normalized(extraction)
        OCRDraftCache.store(result, for: data)
        return result
    }

    static func drafts(fromPDF url: URL) async -> [OnboardingPrescriptionDraft] {
        let key = (try? Data(contentsOf: url)) ?? Data(url.absoluteString.utf8)
        if let cached = OCRDraftCache.drafts(for: key) { return cached }
        let extraction = await PrescriptionExtractorChain.extract(fromPDF: url)
        let result = normalized(extraction)
        OCRDraftCache.store(result, for: key)
        return result
    }

    private static func normalized(_ extraction: PrescriptionExtraction) -> [OnboardingPrescriptionDraft] {
        if !extraction.drafts.isEmpty { return extraction.drafts }
        if extraction.draft.hasMedicineName { return [extraction.draft] }
        return [.empty]
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
        var images: [UIImage] = []
        for index in 0..<limit {
            guard let page = document.page(at: index),
                  let cgImage = rasterize(page)
            else { continue }
            images.append(UIImage(cgImage: cgImage))
        }
        guard let first = images.first else { return nil }
        if images.count == 1 { return jpeg(from: first) }
        let width = images.map(\.size.width).max() ?? first.size.width
        let height = images.reduce(0) { $0 + $1.size.height }
        let size = CGSize(width: max(1, width), height: max(1, height))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let stacked = renderer.image { _ in
            var y: CGFloat = 0
            for image in images {
                image.draw(in: CGRect(x: 0, y: y, width: image.size.width, height: image.size.height))
                y += image.size.height
            }
        }
        return jpeg(from: stacked, maxDimension: 2400)
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
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = ["pt-BR", "en-US", "es-ES", "fr-FR"]
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

/// Same photo/PDF bytes always yield the same confirm list in this session.
private enum OCRDraftCache {
    private static let lock = NSLock()
    private static var draftsByDigest: [String: [OnboardingPrescriptionDraft]] = [:]

    static func drafts(for data: Data) -> [OnboardingPrescriptionDraft]? {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        lock.lock()
        defer { lock.unlock() }
        return draftsByDigest[digest]
    }

    static func store(_ drafts: [OnboardingPrescriptionDraft], for data: Data) {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        lock.lock()
        draftsByDigest[digest] = drafts
        lock.unlock()
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
        parseAll(raw, limit: 1).first ?? .empty
    }

    static func parseAll(_ raw: String, limit: Int = 12) -> [OnboardingPrescriptionDraft] {
        let cleaned = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let globalDose = findDose(in: cleaned)
        let globalFrequency = findFrequency(in: cleaned)
        let globalDuration = findDuration(in: cleaned)
        var drafts: [OnboardingPrescriptionDraft] = []
        var seen = Set<String>()

        for (index, line) in lines.enumerated() {
            let nearby = nearbyText(lines: lines, index: index)
            for hit in strengthHits(in: line) {
                let key = hit.name.lowercased()
                guard seen.insert(key).inserted else { continue }
                drafts.append(
                    OnboardingPrescriptionDraft(
                        medicine: "\(hit.name) \(hit.strength)",
                        dose: nonempty(findDose(in: nearby), globalDose),
                        frequency: nonempty(findFrequency(in: nearby), globalFrequency),
                        duration: nonempty(findDuration(in: nearby), globalDuration),
                        timesPerDay: nonempty(
                            findTimesPerDay(in: nearby),
                            findTimesPerDay(in: cleaned)
                        )
                    )
                )
                if drafts.count >= limit { return drafts }
            }
        }

        if drafts.isEmpty {
            let labeled = try? NSRegularExpression(
                pattern: #"(?i)\b(?:medicine|medication|medicamento|médicament|drug|rx)\s*[:\-]\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\- ]{2,40})"#
            )
            if let labeled {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                for match in labeled.matches(in: cleaned, range: range) {
                    guard match.numberOfRanges > 1,
                          let nameRange = Range(match.range(at: 1), in: cleaned)
                    else { continue }
                    let name = String(cleaned[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = name.lowercased()
                    guard isPlausibleName(name), seen.insert(key).inserted else { continue }
                    drafts.append(
                        OnboardingPrescriptionDraft(
                            medicine: name,
                            dose: globalDose,
                            frequency: globalFrequency,
                            duration: globalDuration,
                            timesPerDay: findTimesPerDay(in: cleaned)
                        )
                    )
                    if drafts.count >= limit { return drafts }
                }
            }
        }

        if drafts.isEmpty {
            for line in lines where line.count >= 5 && line.count <= 48 {
                let words = line.split(separator: " ").map(String.init)
                guard words.count <= 4, words.allSatisfy({ $0.first?.isLetter == true }) else { continue }
                let key = line.lowercased()
                guard isPlausibleName(line), looksLikeDrugToken(line), seen.insert(key).inserted else { continue }
                drafts.append(
                    OnboardingPrescriptionDraft(
                        medicine: line,
                        dose: globalDose,
                        frequency: globalFrequency,
                        duration: globalDuration,
                        timesPerDay: findTimesPerDay(in: cleaned)
                    )
                )
                if drafts.count >= limit { return drafts }
            }
        }

        return drafts
    }

    private static func nearbyText(lines: [String], index: Int) -> String {
        let end = min(lines.count, index + 3)
        return lines[index..<end].joined(separator: "\n")
    }

    private static func nonempty(_ preferred: String, _ fallback: String) -> String {
        preferred.isEmpty ? fallback : preferred
    }

    private struct StrengthHit {
        var name: String
        var strength: String
    }

    private static func strengthHits(in line: String) -> [StrengthHit] {
        let strength = try? NSRegularExpression(
            pattern: #"(?i)\b([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\-]{2,}(?:\s+[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\-]{2,}){0,3})\s+(\d+(?:[.,]\d+)?\s*(?:mg|mcg|µg|ug|g|ml|ui|iu|%|miligramos?|milligrams?))\b"#
        )
        guard let strength else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return strength.matches(in: line, range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let nameRange = Range(match.range(at: 1), in: line),
                  let doseRange = Range(match.range(at: 2), in: line)
            else { return nil }
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
            let dose = String(line[doseRange]).replacingOccurrences(of: " ", with: "")
            guard isPlausibleName(name) else { return nil }
            return StrengthHit(name: name, strength: dose.lowercased())
        }
    }

    private static func findTimesPerDay(in raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("qid") || lower.contains("4 times") || lower.contains("quatro vez") {
            return "4"
        }
        if lower.contains("tid") || lower.contains("3 times") || lower.contains("três vez")
            || lower.contains("tres vez") || lower.contains("trois fois") {
            return "3"
        }
        if lower.contains("bid") || lower.contains("twice") || lower.contains("2 times")
            || lower.contains("duas vez") || lower.contains("deux fois") {
            return "2"
        }
        if lower.contains("once") || lower.contains("qd") || lower.contains("1 time")
            || lower.contains("uma vez") || lower.contains("una vez") || lower.contains("une fois") {
            return "1"
        }
        let hoursPattern = #"(?i)(?:every|cada|todas as|toutes les)\s+(\d+)\s+(?:hours?|horas?|heures?)"#
        if let hoursText = firstGroup(hoursPattern, in: raw), let hours = Int(hoursText) {
            if hours <= 6 { return "4" }
            if hours <= 8 { return "3" }
            if hours <= 12 { return "2" }
            return "1"
        }
        return ""
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
