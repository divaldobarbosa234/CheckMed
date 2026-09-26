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
    func freeMedicineSlotsRemaining(existingCount: Int) -> Int {
        if isSuper { return max(0, 12 - existingCount) }
        return max(0, SuperLimits.freePrescriptions - existingCount)
    }

    func allowsNewPrescription(existingCount: Int) -> Bool {
        if isSuper { return true }
        if existingCount == 0 { return true }
        return existingCount < SuperLimits.freePrescriptions
    }

    /// Photo/PDF: gate after validated distinct medicine objects (never a hardcoded N).
    func needsScanSlotLimit(detectedCount: Int, existingCount: Int) -> Bool {
        guard !isSuper else { return false }
        return detectedCount > freeMedicineSlotsRemaining(existingCount: existingCount)
    }

    func allowsPhotoPDF(usedCount: Int, existingMedicines: Int) -> Bool {
        if isSuper { return usedCount < SuperLimits.superPhotoPDFItems }
        // Free plan: keep scanning while medicine slots remain.
        return existingMedicines < SuperLimits.freePrescriptions
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
            if !allowsPhotoPDF(usedCount: photoPDFUsed, existingMedicines: existingCount) {
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
        let medicines = ScanPipeline.medicines(from: extraction)
        if medicines.isEmpty { return [.empty] }
        return medicines
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
            images.append(UIImage(cgImage: bestOrientedCGImage(cgImage)))
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
        return bestOrientedOCR(cgImage)
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
            ocrText += bestOrientedOCR(image)
            ocrText += "\n"
        }
        return (text + "\n" + ocrText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func rasterize(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        let swapped = rotation == 90 || rotation == 270
        let drawWidth = swapped ? bounds.height : bounds.width
        let drawHeight = swapped ? bounds.width : bounds.height
        let longest = max(drawWidth, drawHeight)
        let scale = longest > 0 ? min(2.2, 1600 / longest) : 1
        let size = CGSize(width: max(1, drawWidth * scale), height: max(1, drawHeight * scale))
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
            if rotation != 0 {
                context.cgContext.translateBy(x: drawWidth / 2, y: drawHeight / 2)
                context.cgContext.rotate(by: -CGFloat(rotation) * .pi / 180)
                context.cgContext.translateBy(x: -bounds.width / 2, y: -bounds.height / 2)
            }
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

    /// Try 0° and 180° (and 90/270 if both look inverted). Pick the span with table headers + drug+strength hits.
    nonisolated private static func bestOrientedOCR(_ image: CGImage) -> String {
        bestOriented(image).text
    }

    nonisolated private static func bestOrientedCGImage(_ image: CGImage) -> CGImage {
        bestOriented(image).image
    }

    nonisolated private static func bestOriented(_ image: CGImage) -> (image: CGImage, text: String) {
        let text0 = ocr(image)
        var bestImage = image
        var bestText = text0
        var bestScore = ocrOrientationScore(text0)
        if let rotated = rotate(image, degrees: 180) {
            let text = ocr(rotated)
            let score = ocrOrientationScore(text)
            if score > bestScore {
                bestScore = score
                bestText = text
                bestImage = rotated
            }
        }
        if bestScore < 8 {
            for degrees in [90, 270] {
                guard let rotated = rotate(image, degrees: degrees) else { continue }
                let text = ocr(rotated)
                let score = ocrOrientationScore(text)
                if score > bestScore {
                    bestScore = score
                    bestText = text
                    bestImage = rotated
                }
            }
        }
        return (bestImage, bestText)
    }

    nonisolated private static func ocrOrientationScore(_ text: String) -> Int {
        let folded = MedicationCatalogEntry.fold(text)
        guard folded.count >= 8 else { return 0 }
        var score = 0
        let headers = ["medicamento", "dosis", "indicacion", "indicaciones", "medicine", "dose", "receta", "receita", "ordonnance"]
        for header in headers where folded.contains(header) {
            score += 6
        }
        score += PrescriptionParser.strengthHits(in: text).count * 8
        score += MedicationCatalog.wholeWordHits(in: text).count * 2
        return score
    }

    nonisolated private static func rotate(_ image: CGImage, degrees: Int) -> CGImage? {
        let turn = ((degrees % 360) + 360) % 360
        if turn == 0 { return image }
        let swapped = turn == 90 || turn == 270
        let size = swapped
            ? CGSize(width: image.height, height: image.width)
            : CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: CGFloat(turn) * .pi / 180)
            let rect = CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height))
            context.cgContext.draw(image, in: rect)
        }
        return rendered.cgImage
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
        "si", "if", "cuando", "quando", "warning", "aviso",
        "medicamento", "medicamentos", "dosis", "dosi", "indicaciones", "indicacion",
        "observaciones", "observacoes", "nacimiento", "nascimento", "colegiado",
        "tratamiento", "tratamento", "antibiotico", "antibiótico", "sintomas", "síntomas",
        "finalizar", "contacto", "contacte", "receta", "médica", "medica",
    ]

    private static let boilerplateSnippets = [
        "sintomas persist", "síntomas persist", "symptoms persist",
        "sintomas persistem", "empeoran", "worsen", "piorarem",
        "consulte", "consultar al", "contact your", "see your doctor",
        "según prescripci", "conforme prescri", "as directed",
        "si los sintomas", "si los síntomas", "if symptoms",
        "quando os sintomas", "si les symptômes",
        "keep out of reach", "mantener fuera", "manter fora",
        "this prescription", "esta receta", "esta receita", "cette ordonnance",
        "no sustituye", "does not replace", "não substitui",
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
        let globalDoctor = findDoctorName(in: cleaned)
        let globalDoctorId = findDoctorId(in: cleaned)
        let globalHospital = findHospital(in: cleaned)
        let globalNotes = findDoctorNotes(in: cleaned)
        let globalPackage = findPackageAmount(in: cleaned)
        var drafts: [OnboardingPrescriptionDraft] = []
        var seen = Set<String>()

        func enrich(_ draft: OnboardingPrescriptionDraft) -> OnboardingPrescriptionDraft {
            var next = draft
            next.doctorName = globalDoctor
            next.doctorId = globalDoctorId
            next.hospitalName = globalHospital
            next.doctorNotes = globalNotes
            if next.packageAmount.isEmpty {
                next.packageAmount = globalPackage.amount
                next.packageUnit = globalPackage.unit
            }
            next.form = MedicineForm.infer(from: next.dose, medicineName: next.medicine).rawValue
            if next.sourceText.isEmpty {
                next.sourceText = next.medicine
            }
            return next
        }

        let tableRows = parseMedicationTable(lines: lines, fallback: cleaned)
        if !tableRows.isEmpty {
            for row in tableRows {
                let key = distinctObjectKey(row)
                guard keepsAsMedicine(row), seen.insert(key).inserted else { continue }
                drafts.append(enrich(row))
                if drafts.count >= limit { return drafts }
            }
            if !drafts.isEmpty { return drafts }
        }

        for (index, line) in lines.enumerated() {
            let nearby = nearbyText(lines: lines, index: index)
            for hit in strengthHits(in: line) {
                let key = distinctObjectKey(
                    OnboardingPrescriptionDraft(
                        medicine: "\(hit.name) \(hit.strength)",
                        dose: "",
                        frequency: "",
                        duration: "",
                        timesPerDay: ""
                    )
                )
                guard PrescriptionParser.keepsAsMedicineName(hit.name), seen.insert(key).inserted else { continue }
                drafts.append(
                    enrich(
                        OnboardingPrescriptionDraft(
                            medicine: "\(hit.name) \(hit.strength)",
                            dose: nonempty(findDose(in: nearby), globalDose),
                            frequency: nonempty(findFrequency(in: nearby), globalFrequency),
                            duration: nonempty(findDuration(in: nearby), globalDuration),
                            timesPerDay: nonempty(
                                findTimesPerDay(in: nearby),
                                findTimesPerDay(in: cleaned)
                            ),
                            sourceText: nearby
                        )
                    )
                )
                if drafts.count >= limit { return drafts }
            }
        }

        if drafts.count < limit {
            for (index, line) in lines.enumerated() {
                guard let item = numberedItem(in: line) else { continue }
                let follow = index + 1 < lines.count ? lines[index + 1] : ""
                let nearby = nearbyText(lines: lines, index: index)
                let strength = strengthHits(in: item).first?.strength
                    ?? strengthHits(in: follow).first?.strength
                    ?? ""
                let name = strengthHits(in: item).first?.name ?? item
                let medicine = strength.isEmpty ? name : "\(name) \(strength)"
                let key = canonicalMedicineKey(medicine)
                guard keepsAsMedicineName(name), seen.insert(key).inserted else { continue }
                drafts.append(
                    enrich(
                        OnboardingPrescriptionDraft(
                            medicine: medicine,
                            dose: nonempty(findDose(in: nearby), globalDose),
                            frequency: nonempty(findFrequency(in: nearby), globalFrequency),
                            duration: nonempty(findDuration(in: nearby), globalDuration),
                            timesPerDay: nonempty(
                                findTimesPerDay(in: nearby),
                                findTimesPerDay(in: cleaned)
                            ),
                            sourceText: nearby
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
                    let key = canonicalMedicineKey(name)
                    guard keepsAsMedicineName(name), seen.insert(key).inserted else { continue }
                    drafts.append(
                        enrich(
                            OnboardingPrescriptionDraft(
                                medicine: name,
                                dose: globalDose,
                                frequency: globalFrequency,
                                duration: globalDuration,
                                timesPerDay: findTimesPerDay(in: cleaned),
                                sourceText: String(cleaned[nameRange])
                            )
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
                let key = canonicalMedicineKey(line)
                let catalogExact = MedicationCatalog.wholeWordHits(in: line).contains {
                    MedicationCatalogEntry.fold($0) == MedicationCatalogEntry.fold(line.split(separator: " ").first.map(String.init) ?? line)
                }
                guard isPlausibleName(line), catalogExact, seen.insert(key).inserted else { continue }
                drafts.append(
                    enrich(
                        OnboardingPrescriptionDraft(
                            medicine: line,
                            dose: globalDose,
                            frequency: globalFrequency,
                            duration: globalDuration,
                            timesPerDay: findTimesPerDay(in: cleaned),
                            sourceText: line
                        )
                    )
                )
                if drafts.count >= limit { return drafts }
            }
        }

        return drafts
    }

    /// Prefer Medicamento | Dosis | Indicaciones rows. One object per distinct row.
    private static func parseMedicationTable(lines: [String], fallback: String) -> [OnboardingPrescriptionDraft] {
        guard let headerIndex = lines.firstIndex(where: isMedicationTableHeader) else { return [] }
        var rows: [OnboardingPrescriptionDraft] = []
        var index = headerIndex + 1
        while index < lines.count {
            let line = lines[index]
            if isTableStop(line) { break }
            if isMedicationTableHeader(line) {
                index += 1
                continue
            }
            let nearby = nearbyText(lines: lines, index: index)
            if let hit = strengthHits(in: line).first, keepsAsMedicineName(hit.name) {
                let follow = index + 1 < lines.count ? lines[index + 1] : ""
                let span = [line, follow].filter { !$0.isEmpty }.joined(separator: "\n")
                rows.append(
                    OnboardingPrescriptionDraft(
                        medicine: "\(hit.name) \(hit.strength)",
                        dose: nonempty(findDose(in: nearby), findDose(in: fallback)),
                        frequency: nonempty(findFrequency(in: nearby), findFrequency(in: fallback)),
                        duration: nonempty(findDuration(in: nearby), findDuration(in: fallback)),
                        timesPerDay: nonempty(findTimesPerDay(in: nearby), findTimesPerDay(in: fallback)),
                        sourceText: span
                    )
                )
                index += 1
                continue
            }
            index += 1
        }
        return rows
    }

    private static func isMedicationTableHeader(_ line: String) -> Bool {
        let folded = MedicationCatalogEntry.fold(line)
        let hasMedicine = folded.contains("medicamento") || folded.contains("medicine") || folded.contains("medicament")
        let hasDose = folded.contains("dosis") || folded.contains("dose") || folded.contains("posolog")
        return hasMedicine && hasDose
    }

    private static func isTableStop(_ line: String) -> Bool {
        let folded = MedicationCatalogEntry.fold(line)
        let stops = [
            "observacion", "observacao", "fecha de nacimiento", "nombre del paciente",
            "nome do paciente", "receta medica", "receita medica", "firma", "assinatura",
        ]
        return stops.contains(where: { folded.contains($0) })
    }

    /// Printed Rx date only. Never PDF metadata, file dates, scan time, or today.
    /// Returns `nil` when the date is missing or not reliable.
    static func findPrescriptionDate(in raw: String) -> Date? {
        let calendar = Calendar.current
        for capture in allGroup1Matches(labeledNumericDatePattern, in: raw) {
            if isBirthDateContext(raw, around: capture.range) { continue }
            if let date = parsePrintedDate(capture.text), isPlausiblePrescriptionDate(date, calendar: calendar) {
                return date
            }
        }
        for capture in allGroup1Matches(labeledMonthNameDatePattern, in: raw) {
            if isBirthDateContext(raw, around: capture.range) { continue }
            if let date = parseMonthNameDate(capture.text), isPlausiblePrescriptionDate(date, calendar: calendar) {
                return date
            }
        }
        let headerLimit = raw.index(raw.startIndex, offsetBy: min(raw.count, 900), limitedBy: raw.endIndex) ?? raw.endIndex
        for capture in allGroup1Matches(numericDateTokenPattern, in: raw) {
            if capture.range.lowerBound >= headerLimit { break }
            if isBirthDateContext(raw, around: capture.range) { continue }
            if let date = parsePrintedDate(capture.text), isPlausiblePrescriptionDate(date, calendar: calendar) {
                return date
            }
        }
        return nil
    }

    private static let labeledNumericDatePattern =
        #"(?i)(?:fecha|date|data|rx|issued|emitida|emiss[aã]o|expedici[oó]n|ordonnance)(?:\s+(?:de|da|do|of|the|la|le|du))?(?:\s+(?:la|the|le|l['’]))?(?:\s+(?:receta|receita|prescription|prescripci[oó]n|prescri[cç][aã]o|ordonnance|issue|emiss[aã]o|expedici[oó]n))?(?:\s+m[eé]dica)?\s*[:\-]?\s*(\d{1,2}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{2,4}|\d{4}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{1,2})"#

    private static let labeledMonthNameDatePattern =
        #"(?i)(?:fecha|date|data|rx|issued|emitida|emiss[aã]o|expedici[oó]n|ordonnance)(?:\s+(?:de|da|do|of|the|la|le|du))?(?:\s+(?:la|the|le))?(?:\s+(?:receta|receita|prescription|prescripci[oó]n|prescri[cç][aã]o|ordonnance))?(?:\s+m[eé]dica)?\s*[:\-]?\s*((?:\d{1,2}\s+de\s+)?[A-Za-zÀ-ÿ.]{3,12}\s+\d{1,2},?\s*(?:de\s+)?\d{2,4}|\d{1,2}\s+de\s+[A-Za-zÀ-ÿ.]{3,12}\s+(?:de\s+)?\d{2,4})"#

    private static let numericDateTokenPattern =
        #"(\d{1,2}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{2,4}|\d{4}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{1,2})"#

    /// Birth labels apply only to the date on the same line. A DOB above must not discard a later Rx date.
    private static func isBirthDateContext(_ raw: String, around range: Range<String.Index>) -> Bool {
        let lineStart = raw[..<range.lowerBound].lastIndex(of: "\n").map { raw.index(after: $0) } ?? raw.startIndex
        let lineEnd = raw[range.upperBound...].firstIndex(of: "\n") ?? raw.endIndex
        let window = raw[lineStart..<lineEnd].folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let markers = [
            "nacimiento", "nascimento", "birth", "nasc.", "dob",
            "date of birth", "data de nascimento", "fecha de nacimiento",
            "data de nasc", "fecha de nac",
        ]
        return markers.contains(where: { window.contains($0) })
    }

    private static func isPlausiblePrescriptionDate(_ date: Date, calendar: Calendar) -> Bool {
        let year = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: Date())
        return year >= 1970 && year <= currentYear + 1
    }

    private static func parsePrintedDate(_ text: String) -> Date? {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: ".", with: "/")
        let parts = cleaned.split(separator: "/").map(String.init)
        guard parts.count == 3,
              let first = Int(parts[0]), let second = Int(parts[1]), let third = Int(parts[2])
        else { return nil }
        let day: Int
        let month: Int
        var year: Int
        if parts[0].count == 4 {
            year = first
            month = second
            day = third
        } else {
            day = first
            month = second
            year = third
            if year < 100 { year += 2000 }
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        return Calendar.current.date(from: components)
    }

    private static func parseMonthNameDate(_ text: String) -> Date? {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let tokens = folded
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard tokens.count >= 3 else { return nil }
        var day: Int?
        var month: Int?
        var year: Int?
        for token in tokens where token != "de" && token != "of" && token != "del" {
            if month == nil, let parsedMonth = monthNumber(from: token) {
                month = parsedMonth
                continue
            }
            if let value = Int(token) {
                if token.count == 4 || value > 31 {
                    year = value < 100 ? value + 2000 : value
                } else if day == nil {
                    day = value
                }
            }
        }
        guard let day, let month, var year else { return nil }
        if year < 100 { year += 2000 }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        return Calendar.current.date(from: components)
    }

    private static func monthNumber(from token: String) -> Int? {
        let key = token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let names: [[String]] = [
            ["january", "jan", "enero", "ene", "janeiro", "janvier"],
            ["february", "feb", "febrero", "fevereiro", "fev", "fevrier"],
            ["march", "mar", "marzo", "marco", "mars"],
            ["april", "apr", "abril", "abr", "avril"],
            ["may", "mayo", "maio", "mai"],
            ["june", "jun", "junio", "junho", "juin"],
            ["july", "jul", "julio", "julho", "juillet"],
            ["august", "aug", "agosto", "ago", "aout"],
            ["september", "sep", "sept", "septiembre", "setembro", "set", "septembre"],
            ["october", "oct", "octubre", "outubro", "out", "octobre"],
            ["november", "nov", "noviembre", "novembro", "novembre"],
            ["december", "dec", "diciembre", "dezembro", "dez", "decembre"],
        ]
        for (index, aliases) in names.enumerated() where aliases.contains(key) {
            return index + 1
        }
        return nil
    }

    private struct RegexCapture {
        var text: String
        var range: Range<String.Index>
    }

    private static func allGroup1Matches(_ pattern: String, in raw: String) -> [RegexCapture] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(raw.startIndex..., in: raw)
        return regex.matches(in: raw, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: raw),
                  let full = Range(match.range(at: 0), in: raw)
            else { return nil }
            let text = String(raw[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RegexCapture(text: text, range: full)
        }
    }

    /// Normalized name + strength + form. Does not fuzzy-merge brands.
    static func distinctObjectKey(_ draft: OnboardingPrescriptionDraft) -> String {
        let folded = MedicationCatalogEntry.fold(draft.medicine)
        let strength = strengthHits(in: draft.medicine).first?.strength
            ?? draft.medicine.lowercased().split(whereSeparator: { $0.isNumber || $0 == "." || $0 == "," }).joined()
        let form = draft.form.isEmpty
            ? MedicineForm.infer(from: draft.dose, medicineName: draft.medicine).rawValue
            : draft.form
        return "\(folded)|\(strength)|\(form.lowercased())"
    }

    private static func numberedItem(in line: String) -> String? {
        let pattern = #"^\s*(?:\d+\s*[\)\.\-:]+|[\-•*])\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: line)
        else { return nil }
        let item = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return item.isEmpty ? nil : item
    }

    private static func nearbyText(lines: [String], index: Int) -> String {
        let end = min(lines.count, index + 3)
        return lines[index..<end].joined(separator: "\n")
    }

    private static func nonempty(_ preferred: String, _ fallback: String) -> String {
        preferred.isEmpty ? fallback : preferred
    }

    struct StrengthHit {
        var name: String
        var strength: String
    }

    static func strengthHits(in line: String) -> [StrengthHit] {
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
        if let times = firstGroup(
            #"(?i)\b(\d+)\s*[x×]\s*(?:daily|a day|ao dia|por dia|al día|al dia|par jour|die)?\b"#,
            in: raw
        ), let count = Int(times), (1...4).contains(count) {
            return "\(count)"
        }
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
        let intervalPatterns = [
            #"(?i)\b((?:every|cada|todas as|toutes les)\s+\d+\s+(?:hours?|horas?|heures?))\b"#,
            #"(?i)\b(as needed|quando necessário|quando necessario|si besoin|según necesidad|segun necesidad|prn)\b"#,
        ]
        for pattern in intervalPatterns {
            if let match = firstGroup(pattern, in: raw) {
                return intervalOnly(match)
            }
        }
        return ""
    }

    static func intervalOnly(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let interval = #"(?i)((?:every|cada|todas as|toutes les)\s+\d+\s*(?:h|hours?|horas?|heures?)|(?:as needed|quando necessário|quando necessario|si besoin|según necesidad|segun necesidad|prn))"#
        if let match = firstGroup(interval, in: trimmed) {
            return match.replacingOccurrences(of: "  ", with: " ")
        }
        var cleaned = trimmed
        let dropTimes = [
            #"(?i)\d+\s*[x×]\s*(?:daily|a day|ao dia|por dia|al día|al dia|par jour|die)"#,
            #"(?i)(?:once|twice|one time|two times|three times|four times)\s+(?:daily|a day)"#,
            #"(?i)(?:uma|duas|três|tres|quatro)\s+vezes?\s+(?:ao dia|por dia|al día|al dia)"#,
            #"(?i)\b(?:daily|a day)\b"#,
        ]
        for pattern in dropTimes {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: " "
                )
            }
        }
        cleaned = cleaned.replacingOccurrences(of: "·", with: " ")
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalMedicineKey(_ name: String) -> String {
        var folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        folded = folded.replacingOccurrences(
            of: #"\d+([.,]\d+)?\s*(mg|mcg|µg|ug|g|ml|ui|iu|%|mg/ml)"#,
            with: " ",
            options: .regularExpression
        )
        folded = folded.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func findDuration(in raw: String) -> String {
        let pattern = #"(?i)\b(?:for|durante|pendant|por)?\s*(\d+\s*(?:day|days|dia|dias|días|dias|jour|jours|week|weeks|semana|semanas|semaine|semaines))\b"#
        if let match = firstGroup(pattern, in: raw) {
            return match.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    private static func findDoctorName(in raw: String) -> String {
        let patterns = [
            #"(?i)\b(?:dr\.?|dra\.?|doctor|doutor|doutora|médico|medico|docteur)\s*[:\-]?\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\.\- ]{2,50})"#,
            #"(?i)\b(?:prescriber|prescritor|prescriptor)\s*[:\-]\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\.\- ]{2,50})"#,
        ]
        for pattern in patterns {
            if let match = firstGroup(pattern, in: raw) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func findDoctorId(in raw: String) -> String {
        let patterns = [
            #"(?i)\b(?:CRM|CRP|NPI|license|licença|licencia|n[ºo°]?)\s*[:\-]?\s*([A-Z0-9\-\./]{4,20})"#,
        ]
        for pattern in patterns {
            if let match = firstGroup(pattern, in: raw) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func findHospital(in raw: String) -> String {
        let patterns = [
            #"(?i)\b(?:hospital|clínica|clinica|clinic|centro médico|centre médical)\s*[:\-]?\s*([A-Za-zÀ-ÿ0-9][A-Za-zÀ-ÿ0-9'’\.\- ]{2,60})"#,
        ]
        for pattern in patterns {
            if let match = firstGroup(pattern, in: raw) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func findDoctorNotes(in raw: String) -> String {
        let patterns = [
            #"(?i)\b(?:orientação|orientacao|instructions?|indicaciones|posologie|sig)\s*[:\-]\s*(.{8,160})"#,
        ]
        for pattern in patterns {
            if let match = firstGroup(pattern, in: raw) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func findPackageAmount(in raw: String) -> (amount: String, unit: String) {
        let pattern = #"(?i)\b(\d+(?:[.,]\d+)?)\s*(ml|g|mg|comprimidos?|cápsulas?|capsulas?|tablets?|capsules?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges > 2,
              let amountRange = Range(match.range(at: 1), in: raw),
              let unitRange = Range(match.range(at: 2), in: raw)
        else { return ("", "") }
        let amount = String(raw[amountRange])
        let unitRaw = String(raw[unitRange]).lowercased()
        let unit = MedicineUnit.parse(unitRaw)?.rawValue ?? unitRaw
        return (amount, unit)
    }

    static func keepsAsMedicine(_ draft: OnboardingPrescriptionDraft) -> Bool {
        draft.hasMedicineName && keepsAsMedicineName(draft.medicine)
    }

    static func keepsAsMedicineName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlausibleName(trimmed), !isBoilerplate(trimmed) else { return false }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count > 5 { return false }
        if trimmed.count > 42 { return false }
        if strengthHits(in: trimmed).isEmpty,
           !looksLikeDrugToken(trimmed),
           MedicationCatalog.wholeWordHits(in: trimmed).isEmpty,
           words.count > 3 {
            return false
        }
        return true
    }

    private static func isBoilerplate(_ name: String) -> Bool {
        let folded = MedicationCatalogEntry.fold(name)
        if boilerplateSnippets.contains(where: { folded.contains($0) }) { return true }
        let starters = ["si ", "if ", "cuando ", "quando ", "cuando los ", "si los ", "if the "]
        return starters.contains(where: { folded.hasPrefix($0) })
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
