import Foundation

/// Roles for dates on a scanned prescription. Never treat `prescriptionDate` as treatment start.
enum ScanDateRole {
    /// Printed on the Rx (`Fecha:`). Metadata only.
    case prescriptionDate
    /// Instant the user scanned / uploaded.
    case scanDate
    /// When CheckMed starts the course. Default today or user-chosen — never `prescriptionDate`.
    case treatmentStartDate
    /// Last day of the course (`duration` / user range).
    case treatmentEndDate
}

/// If an LLM extractor is wired later, send this. OCR/Document AI stay text-only.
enum PrescriptionAIPrompt {
    static let extractOnlyExplicit = """
    Extract ONLY medicines explicitly present on the prescription. Never invent.
    One object per distinct table row (Medicamento | Dosis | Indicaciones).
    Each object must include evidence sourceText copied from the document.
    Never autocomplete, fuzzy-match, or expand a name to a brand \
    (Amoxicilina stays Amoxicilina — never Amoxidal).
    """
}

enum ScanLog {
    static func document(_ message: String) { print("[SCAN] document \(message)") }
    static func ocr(_ message: String) { print("[SCAN] OCR \(message)") }
    static func raw(_ drafts: [OnboardingPrescriptionDraft]) {
        print("[SCAN] RAW count=\(drafts.count) \(summarize(drafts))")
    }
    static func validated(_ drafts: [OnboardingPrescriptionDraft]) {
        print("[SCAN] VALIDATED MEDICINES: \(drafts.count) — \(names(drafts))")
    }
    static func deduplicated(_ drafts: [OnboardingPrescriptionDraft]) {
        print("[SCAN] DEDUPLICATED count=\(drafts.count) \(summarize(drafts))")
    }
    static func confirmed(_ drafts: [OnboardingPrescriptionDraft]) {
        print("[SCAN] CONFIRMED count=\(drafts.count) \(summarize(drafts))")
    }
    static func saved(_ drafts: [OnboardingPrescriptionDraft]) {
        print("[SCAN] SAVED count=\(drafts.count) \(summarize(drafts))")
    }

    static func med(_ message: String) { print("[MED] \(message)") }
    static func dose(_ message: String) { print("[DOSE] \(message)") }

    private static func names(_ drafts: [OnboardingPrescriptionDraft]) -> String {
        drafts.map(\.medicine).joined(separator: ", ")
    }

    private static func summarize(_ drafts: [OnboardingPrescriptionDraft]) -> String {
        drafts.map {
            "[\($0.medicine) src=\($0.sourceText.isEmpty ? "MISSING" : "ok")]"
        }.joined(separator: " ")
    }
}

/// PDF/photo → table/OCR → evidence → distinct objects. Nothing is persisted here.
enum ScanPipeline {
    static func medicines(from extraction: PrescriptionExtraction) -> [OnboardingPrescriptionDraft] {
        let scanDate = Date()
        ScanLog.document("engine=\(extraction.engine) rawChars=\(extraction.rawText.count) scanDate=\(iso(scanDate))")
        let preview = extraction.rawText.replacingOccurrences(of: "\n", with: " / ")
        ScanLog.ocr(String(preview.prefix(400)))

        let prescriptionDate = PrescriptionParser.findPrescriptionDate(in: extraction.rawText)
        if let prescriptionDate {
            ScanLog.document("prescriptionDate=\(iso(prescriptionDate)) (printed Rx date)")
        } else {
            ScanLog.document("prescriptionDate=nil (printed date missing or unreliable)")
        }

        var raw = extraction.drafts.isEmpty ? [extraction.draft] : extraction.drafts
        raw = raw.filter(\.hasMedicineName)
        if raw.isEmpty {
            raw = PrescriptionParser.parseAll(extraction.rawText, limit: 12)
        }
        for index in raw.indices {
            raw[index].scanDate = scanDate
            raw[index].prescriptionDate = prescriptionDate
            raw[index].treatmentStartDate = nil
            raw[index].sanitizeScheduleFields()
        }
        ScanLog.raw(raw)

        let validated = raw.filter { hasEvidence($0) && PrescriptionParser.keepsAsMedicine($0) }
        ScanLog.validated(validated)

        let deduped = validated.dedupedDistinctMedicines()
        ScanLog.deduplicated(deduped)
        return deduped
    }

    /// A medicine object is kept only when its name actually appears in `sourceText`.
    static func hasEvidence(_ draft: OnboardingPrescriptionDraft) -> Bool {
        let source = draft.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let medicine = draft.medicine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !medicine.isEmpty else { return false }
        let token = medicine.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? medicine
        guard token.count >= 3 else { return false }
        let foldedSource = MedicationCatalogEntry.fold(source)
        let foldedToken = MedicationCatalogEntry.fold(token)
        return foldedSource.contains(foldedToken)
    }

    /// Today, or the user-chosen range start. Never the printed prescription date.
    static func resolvedTreatmentStart(
        draft: OnboardingPrescriptionDraft,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        if let bounds = PlanDuration.bounds(from: draft.duration, calendar: calendar) {
            if let rx = draft.prescriptionDate, calendar.isDate(bounds.start, inSameDayAs: rx) {
                ScanLog.med("ignored prescriptionDate as treatmentStartDate rx=\(iso(rx)) → today")
                return today
            }
            return calendar.startOfDay(for: bounds.start)
        }
        if let explicit = draft.treatmentStartDate {
            if let rx = draft.prescriptionDate, calendar.isDate(explicit, inSameDayAs: rx) {
                ScanLog.med("ignored prescriptionDate as treatmentStartDate rx=\(iso(rx)) → today")
                return today
            }
            return calendar.startOfDay(for: explicit)
        }
        return today
    }

    static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// Warning-only age. Never used as treatment start or for DoseLog generation.
    static let oldPrescriptionThresholdDays = 90

    /// `nil` when the printed date is missing/unreliable or not older than the threshold.
    static func oldPrescriptionDateToWarn(
        in drafts: [OnboardingPrescriptionDraft],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let date = drafts.compactMap(\.prescriptionDate).first else { return nil }
        let rxDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -oldPrescriptionThresholdDays, to: today) else {
            return nil
        }
        return rxDay < cutoff ? date : nil
    }

    static func displayPrescriptionDate(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#if DEBUG
enum PrescriptionDateContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func day(_ date: Date?, calendar: Calendar = .current) -> String? {
            guard let date else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
            return String(format: "%04d-%02d-%02d", y, m, d)
        }

        let withBirth = """
        Paciente: Ana Teste
        Data de nascimento: 10/05/1980
        Data: 15/03/2025
        1) Amoxicilina 500 mg
        """
        expect(
            day(PrescriptionParser.findPrescriptionDate(in: withBirth)) == "2025-03-15",
            "birth date must not discard the printed Rx date"
        )
        expect(
            day(PrescriptionParser.findPrescriptionDate(in: """
            Nascimento: 10/05/1990
            Data da receita: 06/09/2025
            """)) == "2025-09-06",
            "Portuguese Rx date must win over birth date"
        )
        expect(
            PrescriptionParser.findPrescriptionDate(in: "Nascimento: 10/05/1990") == nil,
            "birth date only must stay unknown"
        )

        expect(
            day(PrescriptionParser.findPrescriptionDate(in: "Data da receita: 12/11/2025\nAmoxicilina 500 mg")) == "2025-11-12",
            "Portuguese data da receita must parse"
        )

        expect(
            day(PrescriptionParser.findPrescriptionDate(in: "Fecha: 2025-09-06\nLosartana 50 mg")) == "2025-09-06",
            "ISO printed date must parse"
        )

        expect(
            day(PrescriptionParser.findPrescriptionDate(in: "Fecha: 15 de septiembre de 2025\nMetformina 850 mg")) == "2025-09-15",
            "written-month printed date must parse"
        )

        expect(
            PrescriptionParser.findPrescriptionDate(in: "Amoxicilina 500 mg\n3x ao dia\n7 dias") == nil,
            "undated prescription must stay unknown"
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22))!

        func draft(on isoDay: String) -> OnboardingPrescriptionDraft {
            var item = OnboardingPrescriptionDraft.empty
            item.medicine = "Amoxicilina"
            item.prescriptionDate = dayDate(isoDay, calendar: calendar)
            return item
        }

        expect(
            ScanPipeline.oldPrescriptionDateToWarn(in: [draft(on: "2025-09-06")], now: now, calendar: calendar) != nil,
            "last-year printed date must warn"
        )
        expect(
            ScanPipeline.oldPrescriptionDateToWarn(in: [draft(on: "2026-09-06")], now: now, calendar: calendar) == nil,
            "current-year printed date must not warn"
        )
        expect(
            ScanPipeline.oldPrescriptionDateToWarn(in: [OnboardingPrescriptionDraft.empty], now: now, calendar: calendar) == nil,
            "unknown date must not warn"
        )
        return failures
    }

    private static func dayDate(_ iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
#endif

