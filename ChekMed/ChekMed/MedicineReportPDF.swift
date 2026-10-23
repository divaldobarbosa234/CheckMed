#if DEBUG
import Darwin
#endif
import PDFKit
import SwiftUI
import UIKit

enum ReportTheme: String, CaseIterable, Identifiable {
    case creamPhil, mintClinical, softNavy, warmSand

    var id: String { rawValue }

    var background: UIColor {
        switch self {
        case .creamPhil: UIColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1)
        case .mintClinical: UIColor(red: 0.90, green: 0.96, blue: 0.93, alpha: 1)
        case .softNavy: UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)
        case .warmSand: UIColor(red: 0.97, green: 0.93, blue: 0.88, alpha: 1)
        }
    }

    var accent: UIColor {
        switch self {
        case .creamPhil: UIColor(red: 0.95, green: 0.78, blue: 0.20, alpha: 1)
        case .mintClinical: UIColor(red: 0.37, green: 0.66, blue: 0.42, alpha: 1)
        case .softNavy: UIColor(red: 0.22, green: 0.35, blue: 0.55, alpha: 1)
        case .warmSand: UIColor(red: 0.78, green: 0.48, blue: 0.28, alpha: 1)
        }
    }

    var ink: UIColor { UIColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1) }

    var backgroundColor: Color { Color(uiColor: background) }
    var accentColor: Color { Color(uiColor: accent) }
    var inkColor: Color { Color(uiColor: ink) }

    func title(_ session: SessionStore) -> String {
        switch self {
        case .creamPhil: session.t(.reportThemeCream)
        case .mintClinical: session.t(.reportThemeMint)
        case .softNavy: session.t(.reportThemeNavy)
        case .warmSand: session.t(.reportThemeSand)
        }
    }
}

struct MedicineReportDocument: Sendable {
    var patientName: String
    var generatedAt: Date
    var medicines: [CheckMedStore.MedicineSummary]
    var takenCount: Int
    var missedCount: Int
    var unrecordedDueCount: Int
    var plannedCount: Int
    var refillDates: [String]
}

/// Presentation counts from `AdherenceSnapshot`. Does not invent DoseLog statuses.
enum MedicineReportAdherence {
    struct Counts: Equatable, Sendable {
        var takenCount: Int
        var missedCount: Int
        var unrecordedDueCount: Int
        var plannedCount: Int
        var percent: Int
    }

    /// `plannedCount` is due logs only (`scheduledAt <= now`). Taken is confirmed taken + taken late.
    /// Missed is canonical missed-like. Remainder is due and neither — not labeled skipped or pending.
    static func counts(from snapshot: AdherenceSnapshot) -> Counts {
        let taken = max(0, snapshot.takenCount)
        let missed = max(0, snapshot.missedCount)
        let planned = max(0, snapshot.plannedCount)
        let unrecordedDue = max(0, planned - taken - missed)
        let percent = planned == 0
            ? 0
            : Int((Double(taken) / Double(planned) * 100).rounded())
        return Counts(
            takenCount: taken,
            missedCount: missed,
            unrecordedDueCount: unrecordedDue,
            plannedCount: planned,
            percent: percent
        )
    }

    /// Bound extra profile name, or the account preferred name when viewing primary.
    /// Returns nil instead of placeholders (`there` / `friend` / email).
    static func patientName(session: SessionStore, family: FamilyStore) -> String? {
        resolvedPatientName(
            isViewingExtra: family.isViewingExtra,
            extraName: family.extra?.name,
            primaryEligible: session.hasPreferredName,
            primaryName: session.displayName
        )
    }

    static func resolvedPatientName(
        isViewingExtra: Bool,
        extraName: String?,
        primaryEligible: Bool,
        primaryName: String
    ) -> String? {
        if isViewingExtra {
            let name = extraName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        }
        guard primaryEligible else { return nil }
        let name = primaryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func shouldPresentShare(pdfData: Data, writeSucceeded: Bool, fileExists: Bool) -> Bool {
        writeSucceeded && fileExists && !pdfData.isEmpty
    }
}

enum MedicineReportPDF {
    static func build(document: MedicineReportDocument, theme: ReportTheme, session: SessionStore) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        df.locale = session.locale.foundationLocale
        let dateText = df.string(from: document.generatedAt)
        let percent: Int = document.plannedCount == 0
            ? 0
            : Int((Double(document.takenCount) / Double(document.plannedCount) * 100).rounded())

        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            theme.background.setFill()
            cg.fill(page)

            var y: CGFloat = 28
            let left: CGFloat = 40
            let contentW = page.width - 80

            func drawText(
                _ text: String,
                font: UIFont,
                color: UIColor = theme.ink,
                x: CGFloat = left,
                width: CGFloat? = nil,
                align: NSTextAlignment = .left
            ) -> CGFloat {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = align
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ]
                let w = width ?? (page.width - x - 40)
                let size = (text as NSString).boundingRect(
                    with: CGSize(width: w, height: 800),
                    options: [.usesLineFragmentOrigin],
                    attributes: attrs,
                    context: nil
                )
                (text as NSString).draw(in: CGRect(x: x, y: y, width: w, height: ceil(size.height) + 2), withAttributes: attrs)
                return ceil(size.height)
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > page.height - 48 {
                    context.beginPage()
                    theme.background.setFill()
                    cg.fill(page)
                    y = 36
                }
            }

            // Brand row
            let brandGreen = UIColor(red: 0.27, green: 0.72, blue: 0.31, alpha: 1)
            let crossRect = CGRect(x: left, y: y + 2, width: 16, height: 16)
            brandGreen.setFill()
            cg.fill(CGRect(x: crossRect.midX - 2, y: crossRect.minY, width: 4, height: 16))
            cg.fill(CGRect(x: crossRect.minX, y: crossRect.midY - 2, width: 16, height: 4))
            _ = drawText(session.t(.reportBrandTitle), font: .systemFont(ofSize: 14, weight: .heavy), x: left + 22)
            _ = drawText(dateText, font: .systemFont(ofSize: 11, weight: .medium), color: theme.ink.withAlphaComponent(0.7), x: page.width - 220, width: 180, align: .right)
            y += 28

            // Title + Phil
            let titleH = drawText(session.t(.reportHeadline), font: .systemFont(ofSize: 26, weight: .black), width: contentW - 110)
            y += 4
            _ = drawText(document.patientName, font: .systemFont(ofSize: 13, weight: .bold), width: contentW - 110)
            if let phil = UIImage(named: "phil_doctor_2d") ?? UIImage(named: "phil_doctor") {
                let philSize = CGSize(width: 88, height: 88)
                let philRect = CGRect(x: page.width - 40 - philSize.width, y: y - titleH - 8, width: philSize.width, height: philSize.height)
                phil.draw(in: philRect)
            }
            y += 28

            // Adherence ring + stats
            ensureSpace(90)
            let ringCenter = CGPoint(x: left + 42, y: y + 42)
            let ringRadius: CGFloat = 36
            theme.accent.withAlphaComponent(0.22).setStroke()
            cg.setLineWidth(8)
            cg.addArc(center: ringCenter, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            cg.strokePath()
            theme.accent.setStroke()
            cg.setLineCap(.round)
            let progress = CGFloat(min(100, max(0, percent))) / 100
            cg.addArc(
                center: ringCenter,
                radius: ringRadius,
                startAngle: -.pi / 2,
                endAngle: -.pi / 2 + progress * .pi * 2,
                clockwise: false
            )
            cg.strokePath()
            let pct = "\(percent)%"
            let pctAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .heavy),
                .foregroundColor: theme.ink,
            ]
            let pctSize = (pct as NSString).size(withAttributes: pctAttrs)
            (pct as NSString).draw(
                at: CGPoint(x: ringCenter.x - pctSize.width / 2, y: ringCenter.y - pctSize.height / 2),
                withAttributes: pctAttrs
            )
            let statsX = left + 100
            let savedY = y
            y = savedY + 18
            _ = drawText(
                session.t(.reportDosesTakenShort, document.takenCount, document.plannedCount),
                font: .systemFont(ofSize: 13, weight: .bold),
                x: statsX,
                width: contentW - 100
            )
            if document.missedCount > 0 {
                y += 16
                _ = drawText(
                    session.t(.reportMissedDoses, document.missedCount),
                    font: .systemFont(ofSize: 12, weight: .semibold),
                    color: theme.ink.withAlphaComponent(0.75),
                    x: statsX,
                    width: contentW - 100
                )
            }
            if document.unrecordedDueCount > 0 {
                y += 16
                _ = drawText(
                    session.t(.reportUnrecordedDueCount, document.unrecordedDueCount),
                    font: .systemFont(ofSize: 12, weight: .semibold),
                    color: theme.ink.withAlphaComponent(0.75),
                    x: statsX,
                    width: contentW - 100
                )
            }
            y = max(y, savedY + 88)

            ensureSpace(36)
            _ = drawText(
                session.t(.reportAdherenceActiveHeading),
                font: .systemFont(ofSize: 11, weight: .heavy)
            )
            y += 14
            _ = drawText(
                session.t(.reportAdherenceActiveNote),
                font: .systemFont(ofSize: 9, weight: .semibold),
                color: theme.ink.withAlphaComponent(0.7)
            )
            y += 18

            // Medications
            ensureSpace(48)
            _ = drawText(session.t(.reportMedicationHistoryHeading), font: .systemFont(ofSize: 15, weight: .heavy))
            y += 14
            _ = drawText(
                session.t(.reportMedicationHistoryNote),
                font: .systemFont(ofSize: 9, weight: .semibold),
                color: theme.ink.withAlphaComponent(0.7)
            )
            y += 16

            for med in document.medicines {
                let lines: [(String, String)] = [
                    (session.t(.manualDose), med.doseLabel),
                    (session.t(.manualFrequency), "\(med.frequency) · \(session.t(.timesPerDayFormat, med.timesPerDay))"),
                    (session.t(.manualDuration), med.duration),
                    (session.t(.medicineReason), med.reason.isEmpty ? "—" : med.reason),
                    (session.t(.reportDoctor), med.doctorName.isEmpty ? "—" : med.doctorName),
                    (session.t(.reportHospital), med.hospitalName.isEmpty ? "—" : med.hospitalName),
                ]
                let boxH: CGFloat = 28 + CGFloat(lines.count) * 16 + 16
                ensureSpace(boxH + 12)
                let box = CGRect(x: left, y: y, width: contentW, height: boxH)
                UIColor.white.withAlphaComponent(0.55).setFill()
                let path = UIBezierPath(roundedRect: box, cornerRadius: 12)
                path.fill()
                theme.accent.withAlphaComponent(0.35).setStroke()
                path.lineWidth = 1.5
                path.stroke()

                var innerY = y + 12
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .heavy),
                    .foregroundColor: theme.ink,
                ]
                (med.name as NSString).draw(at: CGPoint(x: left + 14, y: innerY), withAttributes: nameAttrs)
                innerY += 22
                for (label, value) in lines {
                    let row = "\(label): \(value)"
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: theme.ink.withAlphaComponent(0.85),
                    ]
                    (row as NSString).draw(at: CGPoint(x: left + 14, y: innerY), withAttributes: attrs)
                    innerY += 16
                }
                y += boxH + 12
            }

            // Refill history table
            ensureSpace(70)
            _ = drawText(session.t(.reportRefillHistory), font: .systemFont(ofSize: 15, weight: .heavy))
            y += 20
            let headerH: CGFloat = 24
            let header = CGRect(x: left, y: y, width: contentW, height: headerH)
            theme.accent.setFill()
            UIBezierPath(roundedRect: header, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 8, height: 8)).fill()
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
                .foregroundColor: UIColor.white,
            ]
            (session.t(.manualDose) as NSString).draw(at: CGPoint(x: left + 10, y: y + 5), withAttributes: headerAttrs)
            (session.t(.reportDateColumn) as NSString).draw(at: CGPoint(x: left + 220, y: y + 5), withAttributes: headerAttrs)
            (session.t(.reportStatusColumn) as NSString).draw(at: CGPoint(x: left + 380, y: y + 5), withAttributes: headerAttrs)
            y += headerH

            let rows: [(String, String, String)] = document.medicines.prefix(4).map { med in
                let date: String
                if let refill = med.lastRefillAt {
                    let short = DateFormatter()
                    short.dateStyle = .medium
                    short.locale = session.locale.foundationLocale
                    date = short.string(from: refill)
                } else {
                    date = "—"
                }
                return ("\(med.doseLabel) \(med.name)", date, med.treatmentStatus.capitalized)
            }
            let rowAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: theme.ink,
            ]
            if rows.isEmpty {
                ensureSpace(28)
                UIColor.white.withAlphaComponent(0.45).setFill()
                cg.fill(CGRect(x: left, y: y, width: contentW, height: 28))
                ("—" as NSString).draw(at: CGPoint(x: left + 10, y: y + 8), withAttributes: rowAttrs)
                y += 28
            } else {
                for (i, row) in rows.enumerated() {
                    ensureSpace(26)
                    let rowRect = CGRect(x: left, y: y, width: contentW, height: 26)
                    (i % 2 == 0 ? UIColor.white.withAlphaComponent(0.4) : UIColor.white.withAlphaComponent(0.2)).setFill()
                    cg.fill(rowRect)
                    (row.0 as NSString).draw(in: CGRect(x: left + 10, y: y + 6, width: 200, height: 14), withAttributes: rowAttrs)
                    (row.1 as NSString).draw(at: CGPoint(x: left + 220, y: y + 6), withAttributes: rowAttrs)
                    (row.2 as NSString).draw(at: CGPoint(x: left + 380, y: y + 6), withAttributes: rowAttrs)
                    y += 26
                }
            }

            y += 18
            ensureSpace(70)
            _ = drawText(
                session.t(.reportPercentDueNote),
                font: .systemFont(ofSize: 9, weight: .semibold),
                color: UIColor.darkGray
            )
            y += 12
            _ = drawText(
                session.t(.adherenceRecordNote),
                font: .systemFont(ofSize: 9, weight: .semibold),
                color: UIColor.darkGray
            )
            y += 12
            _ = drawText(
                session.t(.journeyNotAdvice),
                font: .systemFont(ofSize: 9, weight: .semibold),
                color: UIColor.darkGray
            )
            y += 14
            _ = drawText(
                session.t(.refillDisclaimer),
                font: .systemFont(ofSize: 8, weight: .medium),
                color: UIColor.darkGray
            )
        }
    }
}

// MARK: - My Medical Report

struct MedicineReportScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showDownloadPaywall = false
    @State private var showThemePicker = false
    @State private var previewSource: CheckMedStore.PrescriptionSourceItem?
    @State private var exportIssue: ReportExportIssue?

    private struct ReportSnapshot {
        var medicines: [CheckMedStore.MedicineSummary]
        var currentMedicines: [CheckMedStore.MedicineSummary]
        var history: [CheckMedStore.PrescriptionHistoryItem]
        var sources: [CheckMedStore.PrescriptionSourceItem]
        var adherence: AdherenceSnapshot
        var hasReportData: Bool { !medicines.isEmpty }
        var hasNotes: Bool {
            medicines.contains {
                !$0.doctorNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private func buildSnapshot() -> ReportSnapshot {
        ReportPerf.measure("reportSnapshot") {
            let medicines = treatments.reportMedicineSummaries()
            return ReportSnapshot(
                medicines: medicines,
                currentMedicines: medicines.filter { treatments.isCurrentOnJourneyHistory(treatmentId: $0.treatmentId) },
                history: treatments.reportPrescriptionHistory(),
                sources: treatments.reportPrescriptionSources(),
                adherence: treatments.adherence()
            )
        }
    }

    private var canExportPDF: Bool { entitlements.isSuper }

    var body: some View {
        let _ = ReportPerf.reportBody()
        let snap = buildSnapshot()
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                reportNavigation
                reportHero
                if snap.hasReportData {
                    reportScopeNote
                    completenessCard(snap)
                    currentMedicationsCard(snap)
                    historyCard(snap)
                    scheduleCard(snap)
                    notesCard(snap)
                    sourcesCard(snap)
                    exportActions
                } else {
                    emptyState
                }
                Text(session.t(.journeyNotAdvice))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.safety)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(CheckMedTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .sheet(isPresented: $showDownloadPaywall) {
            ReportDownloadPaywallSheet(
                onStartTrial: {
                    showDownloadPaywall = false
                    entitlements.presentPaywall()
                },
                onLater: { showDownloadPaywall = false }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showThemePicker) {
            ReportPDFThemePicker(
                patientName: MedicineReportAdherence.patientName(session: session, family: family) ?? "",
                medicines: snap.medicines,
                adherence: snap.adherence
            ) { theme in
                showThemePicker = false
                exportPDF(theme: theme)
            }
        }
        .sheet(item: $previewSource) { item in
            PrescriptionSourcePreview(item: item)
        }
        .alert(session.t(exportIssue?.titleKey ?? .reportExportFailed), isPresented: Binding(
            get: { exportIssue != nil },
            set: { if !$0 { exportIssue = nil } }
        )) {
            Button(session.t(.ok), role: .cancel) { exportIssue = nil }
        }
        .onAppear {
            ReportPerf.log("REPORT ONAPPEAR")
            ReportPerf.log("REPORT TASK absent (MedicineReportScreen has no .task)")
            ReportPerf.ready()
            #if DEBUG
            if ProcessInfo.processInfo.environment["CHECKMED_DEBUG_REPORT_EXPORT_CONTRACTS"] == "1" {
                let failures = MedicineReportExportContractChecks.failures()
                print("MedicineReportExport failures:", failures)
                assert(failures.isEmpty, "MEDICINE REPORT EXPORT FAILURE: \(failures.joined(separator: "; "))")
            }
            #endif
        }
    }

    private var reportNavigation: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CheckMedTheme.ink)
                    .frame(width: 48, height: 48)
                    .background(CheckMedTheme.surface, in: Circle())
                    .shadow(color: CheckMedTheme.navy.opacity(0.08), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            Text(session.t(.reportsHubTitle))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            Spacer()
        }
        .padding(.top, 8)
    }

    private var reportHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.t(.reportHeadline))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(CheckMedTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.t(.reportSubhead))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reportScopeNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.t(.reportAdherenceActiveHeading))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink)
            Text(session.t(.reportAdherenceActiveNote))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.t(.reportEmptyHeadline))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            Text(session.t(.reportEmptyBody))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            CheckMedButton(title: session.t(.homeScan), action: { go(.addPrescription) })
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private func completenessCard(_ snap: ReportSnapshot) -> some View {
        let items: [(Bool, String)] = [
            (!snap.currentMedicines.isEmpty, session.t(.reportCurrentMedications)),
            (!snap.history.isEmpty, session.t(.reportPrescriptionHistory)),
            (snap.medicines.contains { !$0.doctorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, session.t(.reportDoctor)),
            (snap.medicines.contains { !$0.scheduleTimes.isEmpty }, session.t(.reportMedicationSchedule)),
            (snap.hasNotes, session.t(.reportNotesSection)),
            (!snap.sources.isEmpty, session.t(.reportSources)),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text(session.t(.reportBuilding))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            Text(session.t(.reportCompleteYourReport))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Image(systemName: item.0 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.0 ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                    Text(item.1)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                    Spacer()
                    if !item.0 {
                        Text(session.t(.reportMissingSection))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private func currentMedicationsCard(_ snap: ReportSnapshot) -> some View {
        reportSection(title: session.t(.reportCurrentMedications)) {
            if snap.currentMedicines.isEmpty {
                missingCopy
            } else {
                ForEach(snap.currentMedicines) { med in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(med.name)
                            .font(.system(.body, design: .rounded).weight(.heavy))
                        fact(session.t(.manualDose), med.doseLabel)
                        fact(session.t(.manualFrequency), med.frequency.isEmpty ? session.t(.reportMissingSection) : med.frequency)
                        fact(session.t(.manualDuration), med.duration.isEmpty ? session.t(.reportMissingSection) : med.duration)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func historyCard(_ snap: ReportSnapshot) -> some View {
        reportSection(title: session.t(.reportPrescriptionHistory)) {
            if snap.history.isEmpty {
                missingCopy
            } else {
                ForEach(snap.history) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.medicines.joined(separator: " · "))
                            .font(.system(.body, design: .rounded).weight(.heavy))
                        Text(formattedDate(item.date))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                        if item.doctorName.isEmpty {
                            Text(session.t(.reportDoctor) + " · " + session.t(.reportMissingSection))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                        } else {
                            Text(session.t(.reportDoctor) + ": " + item.doctorName)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        Text(session.t(.reportMedicinesDetected) + ": " + item.medicines.joined(separator: ", "))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func scheduleCard(_ snap: ReportSnapshot) -> some View {
        let periods: [(key: String, label: String)] = [
            ("Morning", session.t(.morning)),
            ("Afternoon", session.t(.afternoon)),
            ("Evening", session.t(.evening)),
            ("Night", session.t(.night)),
        ]
        return reportSection(title: session.t(.reportMedicationSchedule)) {
            if snap.currentMedicines.allSatisfy(\.scheduleTimes.isEmpty) {
                missingCopy
            } else {
                ForEach(periods, id: \.key) { period in
                    let rows = scheduleRows(snap.currentMedicines, in: period.key)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(period.label)
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.primaryShadow)
                            .textCase(.uppercase)
                        if rows.isEmpty {
                            Text(session.t(.todayNothing))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                        } else {
                            ForEach(rows, id: \.self) { row in
                                Text(row)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func notesCard(_ snap: ReportSnapshot) -> some View {
        reportSection(title: session.t(.reportNotesSection)) {
            if !snap.hasNotes {
                missingCopy
            } else {
                ForEach(snap.currentMedicines + snap.medicines.filter { med in
                    !snap.currentMedicines.contains(where: { $0.id == med.id })
                }) { med in
                    let notes = [med.reason, med.doctorNotes]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(med.name)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                            ForEach(notes, id: \.self) { note in
                                Text(note)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func sourcesCard(_ snap: ReportSnapshot) -> some View {
        reportSection(title: session.t(.reportSources)) {
            if snap.sources.isEmpty {
                missingCopy
            } else {
                ForEach(snap.sources) { item in
                    Button {
                        previewSource = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.isPDF ? "doc.richtext.fill" : "photo.fill")
                                .foregroundStyle(CheckMedTheme.primaryShadow)
                                .frame(width: 36, height: 36)
                                .background(CheckMedTheme.mintWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(.body, design: .rounded).weight(.heavy))
                                    .foregroundStyle(CheckMedTheme.ink)
                                Text(formattedDate(item.date))
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundStyle(CheckMedTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var exportActions: some View {
        VStack(spacing: 10) {
            CheckMedButton(title: session.t(.reportEdit), style: .secondary) {
                go(.medicineReportEdit)
            }
            CheckMedButton(title: session.t(.reportDownloadPDF)) {
                attemptTakeOutside()
            }
            CheckMedButton(title: session.t(.reportShareWithDoctor), style: .ghost) {
                attemptTakeOutside()
            }
        }
    }

    private var missingCopy: some View {
        Text(session.t(.reportMissingSection))
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(CheckMedTheme.muted)
    }

    private func reportSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.heavy))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private func fact(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value.isEmpty ? session.t(.reportMissingSection) : value)")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(CheckMedTheme.muted)
    }

    private func scheduleRows(_ currentMedicines: [CheckMedStore.MedicineSummary], in period: String) -> [String] {
        currentMedicines.flatMap { med in
            med.scheduleTimes.filter { Self.period(for: $0) == period }.map { "\($0) · \(med.name)" }
        }
    }

    private static func period(for time: String) -> String {
        let hour = Int(time.split(separator: ":").first ?? "") ?? 0
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.locale = session.locale.foundationLocale
        return df.string(from: date)
    }

    private func attemptTakeOutside() {
        guard canExportPDF else {
            showDownloadPaywall = true
            return
        }
        guard !treatments.reportMedicineSummaries().isEmpty else { return }
        guard MedicineReportAdherence.patientName(session: session, family: family) != nil else {
            exportIssue = .patientNameMissing
            return
        }
        showThemePicker = true
    }

    private func exportPDF(theme: ReportTheme) {
        shareURL = nil
        showShare = false
        guard let patientName = MedicineReportAdherence.patientName(session: session, family: family) else {
            exportIssue = .patientNameMissing
            return
        }
        let live = treatments.reportMedicineSummaries()
        guard !live.isEmpty else { return }
        let counts = MedicineReportAdherence.counts(from: treatments.adherence())
        let doc = MedicineReportDocument(
            patientName: patientName,
            generatedAt: Date(),
            medicines: live,
            takenCount: counts.takenCount,
            missedCount: counts.missedCount,
            unrecordedDueCount: counts.unrecordedDueCount,
            plannedCount: counts.plannedCount,
            refillDates: live.compactMap { med in
                guard let date = med.lastRefillAt else { return nil }
                let df = DateFormatter()
                df.dateStyle = .medium
                df.locale = session.locale.foundationLocale
                return "\(med.name): \(df.string(from: date))"
            }
        )
        let data = MedicineReportPDF.build(document: doc, theme: theme, session: session)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Conny-Cooper-Medical-Report-\(theme.rawValue).pdf")
        do {
            try data.write(to: url, options: .atomic)
            let exists = FileManager.default.fileExists(atPath: url.path)
            guard MedicineReportAdherence.shouldPresentShare(pdfData: data, writeSucceeded: true, fileExists: exists) else {
                exportIssue = .writeFailed
                return
            }
            shareURL = url
            showShare = true
        } catch {
            exportIssue = .writeFailed
        }
    }
}

private enum ReportExportIssue: Identifiable {
    case writeFailed
    case patientNameMissing

    var id: String {
        switch self {
        case .writeFailed: "writeFailed"
        case .patientNameMissing: "patientNameMissing"
        }
    }

    var titleKey: L10n.Key {
        switch self {
        case .writeFailed: .reportExportFailed
        case .patientNameMissing: .reportPatientNameRequired
        }
    }
}

private struct ReportDownloadPaywallSheet: View {
    @Environment(SessionStore.self) private var session
    var onStartTrial: () -> Void
    var onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session.t(.reportDownloadPaywallTitle))
                .font(.system(.title2, design: .rounded).weight(.black))
            Text(session.t(.reportDownloadPaywallBody))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            Spacer(minLength: 0)
            CheckMedButton(title: session.t(.scanLimitStartTrial), action: onStartTrial)
            CheckMedButton(title: session.t(.reportMaybeLater), style: .ghost, action: onLater)
        }
        .padding(24)
        .background(CheckMedTheme.background)
    }
}

private struct ReportPDFThemePicker: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let patientName: String
    let medicines: [CheckMedStore.MedicineSummary]
    let adherence: AdherenceSnapshot
    var onPick: (ReportTheme) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(session.t(.reportChooseTheme))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    let counts = MedicineReportAdherence.counts(from: adherence)
                    ForEach(ReportTheme.allCases) { theme in
                        Button {
                            onPick(theme)
                        } label: {
                            ReportThemeCoverView(
                                theme: theme,
                                patientName: patientName,
                                medicines: medicines,
                                percent: counts.percent,
                                taken: counts.takenCount,
                                planned: counts.plannedCount,
                                missed: counts.missedCount,
                                unrecordedDue: counts.unrecordedDueCount
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(CheckMedTheme.background)
            .navigationTitle(session.t(.reportDownloadPDF))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.t(.cancel)) { dismiss() }
                }
            }
        }
    }
}

private struct PrescriptionSourcePreview: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: CheckMedStore.PrescriptionSourceItem

    var body: some View {
        NavigationStack {
            let _ = ReportPerf.log("PrescriptionSourcePreview body")
            Group {
                if item.isPDF {
                    let _ = ReportPerf.log("START PDFDocument/PDFView")
                    PDFKitRepresentedView(url: item.url)
                        .onAppear { ReportPerf.log("END PDFDocument/PDFView (view appeared)") }
                } else {
                    let image = ReportPerf.measure("UIImage(contentsOfFile:)") {
                        UIImage(contentsOfFile: item.url.path)
                    }
                    if let image {
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
                }
            }
            .background(CheckMedTheme.background)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.t(.done)) { dismiss() }
                }
            }
        }
    }
}

struct ReportBookstoreCard: View {
    @Environment(SessionStore.self) private var session
    let theme: ReportTheme
    let patientName: String
    let medicines: [CheckMedStore.MedicineSummary]
    let adherence: AdherenceSnapshot
    let canExport: Bool
    var onDownload: () -> Void
    var onEdit: () -> Void

    private var counts: MedicineReportAdherence.Counts {
        MedicineReportAdherence.counts(from: adherence)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(theme.title(session))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
                .textCase(.uppercase)
                .tracking(0.4)

            ReportThemeCoverView(
                theme: theme,
                patientName: patientName,
                medicines: medicines,
                percent: counts.percent,
                taken: counts.takenCount,
                planned: counts.plannedCount,
                missed: counts.missedCount,
                unrecordedDue: counts.unrecordedDueCount
            )
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 6)

            HStack(spacing: 10) {
                Button(action: onDownload) {
                    HStack(spacing: 6) {
                        Image(systemName: canExport ? "arrow.down.circle.fill" : "lock.fill")
                        Text(session.t(.reportDownload))
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(CheckMedTheme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(canExport ? "" : session.t(.reportExportLockedHint))

                Button(action: onEdit) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text(session.t(.reportEdit))
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(CheckMedTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ReportThemeCoverView: View {
    @Environment(SessionStore.self) private var session
    let theme: ReportTheme
    let patientName: String
    let medicines: [CheckMedStore.MedicineSummary]
    let percent: Int
    let taken: Int
    let planned: Int
    let missed: Int
    let unrecordedDue: Int

    private var dateText: String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.locale = session.locale.foundationLocale
        return df.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(CheckMedTheme.primary)
                    Text(session.t(.reportBrandTitle))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(theme.inkColor)
                }
                Spacer()
                Text(dateText)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.inkColor.opacity(0.65))
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.t(.reportHeadline))
                        .font(.system(.title3, design: .rounded).weight(.black))
                        .foregroundStyle(theme.inkColor)
                    Text(patientName)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(theme.inkColor.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image("phil_doctor_2d")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(theme.accentColor.opacity(0.25), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(100, max(0, percent))) / 100)
                        .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(percent)%")
                        .font(.system(.headline, design: .rounded).weight(.black))
                        .foregroundStyle(theme.inkColor)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.t(.reportDosesTakenShort, taken, planned))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(theme.inkColor)
                    if missed > 0 {
                        Text(session.t(.reportMissedDoses, missed))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(theme.inkColor.opacity(0.7))
                    }
                    if unrecordedDue > 0 {
                        Text(session.t(.reportUnrecordedDueCount, unrecordedDue))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(theme.inkColor.opacity(0.7))
                    }
                }
            }

            Text(session.t(.reportAdherenceActiveHeading))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(theme.inkColor)
            Text(session.t(.reportAdherenceActiveNote))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.inkColor.opacity(0.7))

            Text(session.t(.reportMedicationHistoryHeading))
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(theme.inkColor)
            Text(session.t(.reportMedicationHistoryNote))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.inkColor.opacity(0.7))

            if let med = medicines.first {
                VStack(alignment: .leading, spacing: 5) {
                    Text(med.name)
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(theme.inkColor)
                    coverFact(session.t(.manualDose), med.doseLabel)
                    coverFact(session.t(.manualFrequency), "\(med.frequency) · \(session.t(.timesPerDayFormat, med.timesPerDay))")
                    coverFact(session.t(.manualDuration), med.duration)
                    if !med.reason.isEmpty {
                        coverFact(session.t(.medicineReason), med.reason)
                    }
                    if !med.doctorName.isEmpty {
                        coverFact(session.t(.reportDoctor), med.doctorName)
                    }
                    if !med.hospitalName.isEmpty {
                        coverFact(session.t(.reportHospital), med.hospitalName)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.accentColor.opacity(0.35), lineWidth: 1)
                )
            }

            Text(session.t(.reportRefillHistory))
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(theme.inkColor)

            VStack(spacing: 0) {
                HStack {
                    Text(session.t(.manualDose))
                    Spacer()
                    Text(session.t(.reportDateColumn))
                    Spacer()
                    Text(session.t(.reportStatusColumn))
                }
                .font(.system(.caption2, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(theme.accentColor)

                ForEach(Array(medicines.prefix(2).enumerated()), id: \.element.id) { index, med in
                    HStack {
                        Text("\(med.doseLabel) \(med.name)")
                            .lineLimit(1)
                        Spacer()
                        Text(refillDate(med))
                        Spacer()
                        Text(med.treatmentStatus.capitalized)
                    }
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.inkColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(index % 2 == 0 ? Color.white.opacity(0.35) : Color.white.opacity(0.18))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(session.t(.journeyNotAdvice))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.inkColor.opacity(0.55))
        }
        .padding(16)
        .background(theme.backgroundColor)
    }

    private func coverFact(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(theme.inkColor.opacity(0.85))
    }

    private func refillDate(_ med: CheckMedStore.MedicineSummary) -> String {
        guard let date = med.lastRefillAt else { return "—" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.locale = session.locale.foundationLocale
        return df.string(from: date)
    }
}

// MARK: - Edit form

struct MedicineReportEditScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [UUID: ReportMedicineDraft] = [:]
    @State private var showMedicalConfirm = false

    private var medicines: [CheckMedStore.MedicineSummary] { treatments.reportMedicineSummaries() }

    var body: some View {
        Form {
            Section {
                Text(session.t(.reportEditSaveHint))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }

            ForEach(medicines) { med in
                Section(med.name) {
                    TextField(session.t(.manualMedicine), text: binding(med.id, \.name))
                    TextField(session.t(.manualDose), text: binding(med.id, \.doseLabel))
                    TextField(session.t(.manualFrequency), text: binding(med.id, \.frequency))
                    TextField(session.t(.manualDuration), text: binding(med.id, \.duration))
                    TextField(session.t(.reportDoctor), text: binding(med.id, \.doctorName))
                    TextField(session.t(.reportDoctorId), text: binding(med.id, \.doctorId))
                    TextField(session.t(.reportHospital), text: binding(med.id, \.hospitalName))
                    TextField(session.t(.reportDoctorNotes), text: binding(med.id, \.doctorNotes), axis: .vertical)
                        .lineLimit(3...6)
                    TextField(session.t(.medicineReason), text: binding(med.id, \.reason), axis: .vertical)
                        .lineLimit(2...4)
                }
            }
        }
        .navigationTitle(session.t(.reportFillDetails))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(session.t(.cancel)) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(session.t(.feelingSave)) {
                    if hasMedicallyImportantChanges {
                        showMedicalConfirm = true
                    } else {
                        saveAll()
                        dismiss()
                    }
                }
                .fontWeight(.bold)
            }
        }
        .alert(session.t(.confirmEditHeadline), isPresented: $showMedicalConfirm) {
            Button(session.t(.reportEditKeepEditing), role: .cancel) {}
            Button(session.t(hasDoseLabelChanges ? .reportEditConfirmDose : .confirmLooksGood)) {
                saveAll()
                dismiss()
            }
        } message: {
            Text(confirmationMessage)
        }
        .onAppear(perform: loadDrafts)
    }

    private var hasDoseLabelChanges: Bool {
        medicines.contains { med in
            guard let draft = drafts[med.id] else { return false }
            return changedField(draft.doseLabel, med.doseLabel, trim: true) != nil
        }
    }

    private var hasFrequencyChanges: Bool {
        medicines.contains { med in
            guard let draft = drafts[med.id] else { return false }
            return changedField(draft.frequency, med.frequency) != nil
        }
    }

    private var hasMedicallyImportantChanges: Bool {
        medicines.contains { med in
            guard let draft = drafts[med.id] else { return false }
            return changedField(draft.name, med.name, trim: true) != nil
                || changedField(draft.doseLabel, med.doseLabel, trim: true) != nil
                || changedField(draft.frequency, med.frequency) != nil
                || changedField(draft.duration, med.duration, trim: true) != nil
        }
    }

    private var confirmationMessage: String {
        var parts: [String] = []
        if hasDoseLabelChanges {
            parts.append(session.t(.reportEditDoseConsequence))
        }
        if hasFrequencyChanges {
            parts.append(session.t(.reportEditFrequencyConsequence))
        }
        return parts.joined(separator: "\n\n")
    }

    private func loadDrafts() {
        var next: [UUID: ReportMedicineDraft] = [:]
        for med in medicines {
            next[med.id] = ReportMedicineDraft(
                name: med.name,
                doseLabel: med.doseLabel,
                frequency: med.frequency,
                duration: med.duration,
                doctorName: med.doctorName,
                doctorId: med.doctorId,
                hospitalName: med.hospitalName,
                doctorNotes: med.doctorNotes,
                reason: med.reason
            )
        }
        drafts = next
    }

    private func binding(_ id: UUID, _ keyPath: WritableKeyPath<ReportMedicineDraft, String>) -> Binding<String> {
        Binding(
            get: { drafts[id]?[keyPath: keyPath] ?? "" },
            set: { value in
                var draft = drafts[id] ?? ReportMedicineDraft()
                draft[keyPath: keyPath] = value
                drafts[id] = draft
            }
        )
    }

    private func saveAll() {
        for med in medicines {
            guard let draft = drafts[med.id] else { continue }
            let name = changedField(draft.name, med.name, trim: true)
            let doseLabel = changedField(draft.doseLabel, med.doseLabel, trim: true)
            let frequency = changedField(draft.frequency, med.frequency)
            let duration = changedField(draft.duration, med.duration, trim: true)
            let doctorName = changedField(draft.doctorName, med.doctorName)
            let doctorId = changedField(draft.doctorId, med.doctorId)
            let hospitalName = changedField(draft.hospitalName, med.hospitalName)
            let doctorNotes = changedField(draft.doctorNotes, med.doctorNotes)
            let reason = changedField(draft.reason, med.reason)
            guard name != nil || doseLabel != nil || frequency != nil || duration != nil
                || doctorName != nil || doctorId != nil || hospitalName != nil
                || doctorNotes != nil || reason != nil
            else { continue }
            treatments.updateMedicineDetails(
                id: med.id,
                name: name,
                doseLabel: doseLabel,
                frequency: frequency,
                duration: duration,
                doctorName: doctorName,
                doctorId: doctorId,
                hospitalName: hospitalName,
                doctorNotes: doctorNotes,
                reason: reason
            )
        }
    }

    /// `nil` means unchanged versus the loaded summary, so `updateMedicineDetails` skips that field.
    private func changedField(_ draft: String, _ original: String, trim: Bool = false) -> String? {
        if trim {
            let next = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let prev = original.trimmingCharacters(in: .whitespacesAndNewlines)
            return next == prev ? nil : draft
        }
        return draft == original ? nil : draft
    }
}

private struct ReportMedicineDraft {
    var name = ""
    var doseLabel = ""
    var frequency = ""
    var duration = ""
    var doctorName = ""
    var doctorId = ""
    var hospitalName = ""
    var doctorNotes = ""
    var reason = ""
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
enum MedicineReportExportContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ ok: Bool, _ name: String) {
            if !ok { failures.append(name) }
        }
        func snap(taken: Int, late: Int, missed: Int, planned: Int, percent: Int?) -> AdherenceSnapshot {
            AdherenceSnapshot(
                streakDays: 0,
                longestStreakDays: 0,
                takenCount: taken,
                takenLateCount: late,
                missedCount: missed,
                plannedCount: planned,
                percent: percent,
                treatmentCount: 1,
                todayTaken: 0,
                todayTotal: 0,
                todayMissedCount: 0,
                hasHistory: planned > 0,
                weekTaken: 0,
                weekPlanned: 0,
                weekPercent: nil
            )
        }

        var counts = MedicineReportAdherence.counts(
            from: snap(taken: 2, late: 0, missed: 0, planned: 2, percent: 100)
        )
        expect(
            counts.takenCount == 2 && counts.missedCount == 0 && counts.unrecordedDueCount == 0 && counts.percent == 100,
            "taken: 2 of 2 due"
        )

        counts = MedicineReportAdherence.counts(
            from: snap(taken: 2, late: 1, missed: 0, planned: 2, percent: 100)
        )
        expect(
            counts.takenCount == 2 && counts.unrecordedDueCount == 0 && counts.missedCount == 0,
            "takenLate: already included in takenCount"
        )

        counts = MedicineReportAdherence.counts(
            from: snap(taken: 1, late: 0, missed: 2, planned: 3, percent: 33)
        )
        expect(
            counts.missedCount == 2 && counts.unrecordedDueCount == 0 && counts.percent == 33,
            "missed-like: not treated as remainder"
        )

        counts = MedicineReportAdherence.counts(
            from: snap(taken: 1, late: 0, missed: 0, planned: 3, percent: 33)
        )
        expect(
            counts.unrecordedDueCount == 2 && counts.missedCount == 0,
            "open due: remainder is not skipped"
        )

        counts = MedicineReportAdherence.counts(
            from: snap(taken: 1, late: 0, missed: 0, planned: 1, percent: 100)
        )
        expect(
            counts.plannedCount == 1 && counts.unrecordedDueCount == 0,
            "future scheduled doses are outside plannedCount"
        )

        counts = MedicineReportAdherence.counts(
            from: snap(taken: 0, late: 0, missed: 0, planned: 0, percent: nil)
        )
        expect(
            counts.percent == 0 && counts.takenCount == 0 && counts.unrecordedDueCount == 0,
            "no due doses"
        )

        counts = MedicineReportAdherence.counts(
            from: snap(taken: 2, late: 1, missed: 1, planned: 5, percent: 40)
        )
        expect(
            counts.takenCount == 2 && counts.missedCount == 1 && counts.unrecordedDueCount == 2 && counts.percent == 40,
            "mixed statuses"
        )

        expect(
            MedicineReportAdherence.resolvedPatientName(
                isViewingExtra: false,
                extraName: "Alex",
                primaryEligible: true,
                primaryName: "Jordan"
            ) == "Jordan",
            "primary profile identity"
        )
        expect(
            MedicineReportAdherence.resolvedPatientName(
                isViewingExtra: true,
                extraName: "Alex",
                primaryEligible: true,
                primaryName: "Jordan"
            ) == "Alex",
            "bound extra-profile identity"
        )
        expect(
            MedicineReportAdherence.resolvedPatientName(
                isViewingExtra: false,
                extraName: nil,
                primaryEligible: false,
                primaryName: "there"
            ) == nil,
            "placeholder primary name is not exported"
        )
        expect(
            MedicineReportAdherence.resolvedPatientName(
                isViewingExtra: true,
                extraName: "  ",
                primaryEligible: true,
                primaryName: "Jordan"
            ) == nil,
            "empty extra name is not exported"
        )

        let pdf = Data("pdf".utf8)
        expect(
            !MedicineReportAdherence.shouldPresentShare(pdfData: Data(), writeSucceeded: true, fileExists: true),
            "empty PDF is not shared"
        )
        expect(
            !MedicineReportAdherence.shouldPresentShare(pdfData: pdf, writeSucceeded: false, fileExists: true),
            "failed write is not shared"
        )
        expect(
            !MedicineReportAdherence.shouldPresentShare(pdfData: pdf, writeSucceeded: true, fileExists: false),
            "missing file is not shared"
        )
        expect(
            MedicineReportAdherence.shouldPresentShare(pdfData: pdf, writeSucceeded: true, fileExists: true),
            "successful write can be shared"
        )
        return failures
    }
}

/// Launch-only DEBUG runner for report export contracts + one synthetic PDF.
/// Interactive Debug and Release never set `CHECKMED_REPORT_EXPORT_CONTRACTS`.
enum MedicineReportExportContractLaunch {
    static let environmentKey = "CHECKMED_REPORT_EXPORT_CONTRACTS"
    static let simctlChildKey = "SIMCTL_CHILD_" + environmentKey
    static let pointerName = "checkmed-report-export-output.txt"

    static var isRequested: Bool {
        flagValue() == "1"
    }

    private static func flagValue() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let value = env[environmentKey], !value.isEmpty { return value }
        if let value = env[simctlChildKey], !value.isEmpty { return value }
        if let pointer = getenv(environmentKey) {
            let value = String(cString: pointer)
            if !value.isEmpty { return value }
        }
        if let pointer = getenv(simctlChildKey) {
            let value = String(cString: pointer)
            if !value.isEmpty { return value }
        }
        return nil
    }

    static var shouldIsolateProcess: Bool { isRequested }

    /// UIKit calls `didFinishLaunching` on the main thread. Do not wait for SwiftUI.
    static func runFromAppDelegate() {
        guard Thread.isMainThread else {
            writePointerAndLog(blocked: "app-delegate-not-main")
            return
        }
        MainActor.assumeIsolated {
            runAndWriteOutputs()
        }
    }

    @MainActor
    static func runAndWriteOutputs() {
        let failures = MedicineReportExportContractChecks.failures()
            + CheckMedStore.medicineDetailsUpdateContractFailures()
        let contractPass = failures.isEmpty

        let counts = MedicineReportAdherence.counts(
            from: AdherenceSnapshot(
                streakDays: 0,
                longestStreakDays: 0,
                takenCount: 2,
                takenLateCount: 1,
                missedCount: 1,
                plannedCount: 5,
                percent: 40,
                treatmentCount: 1,
                todayTaken: 0,
                todayTotal: 0,
                todayMissedCount: 0,
                hasHistory: true,
                weekTaken: 0,
                weekPlanned: 0,
                weekPercent: nil
            )
        )
        let document = MedicineReportDocument(
            patientName: "Jordan",
            generatedAt: Date(timeIntervalSince1970: 1_735_689_600),
            medicines: [syntheticMedicineSummary()],
            takenCount: counts.takenCount,
            missedCount: counts.missedCount,
            unrecordedDueCount: counts.unrecordedDueCount,
            plannedCount: counts.plannedCount,
            refillDates: []
        )

        let session = SessionStore()
        let pdfData = MedicineReportPDF.build(document: document, theme: .creamPhil, session: session)

        let fm = FileManager.default
        let outputDir = fm.temporaryDirectory.appendingPathComponent(
            "checkmed-report-export-\(UUID().uuidString)",
            isDirectory: true
        )
        var pdfPath = ""
        var reportPath = ""
        var pdfWriteOK = false
        var pdfBytes = 0
        var writeError = ""

        do {
            try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let pdfURL = outputDir.appendingPathComponent("checkmed-report-export-synthetic.pdf")
            let reportURL = outputDir.appendingPathComponent("checkmed-report-export-contracts.txt")
            guard !pdfData.isEmpty else {
                throw NSError(
                    domain: "MedicineReportExportContractLaunch",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "empty-pdf-data"]
                )
            }
            try pdfData.write(to: pdfURL, options: .atomic)
            let writtenSize = (try pdfURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            pdfBytes = writtenSize > 0 ? writtenSize : pdfData.count
            pdfWriteOK = fm.fileExists(atPath: pdfURL.path) && pdfBytes > 0
            pdfPath = pdfURL.path
            reportPath = reportURL.path

            let overallPass = contractPass && pdfWriteOK
            let body = reportBody(
                overallPass: overallPass,
                contractPass: contractPass,
                failures: failures,
                counts: counts,
                pdfWriteOK: pdfWriteOK,
                pdfBytes: pdfBytes,
                outputDir: outputDir.path,
                reportPath: reportPath,
                pdfPath: pdfPath,
                writeError: ""
            )
            try body.write(to: reportURL, atomically: true, encoding: .utf8)
            writePointer(body)
            print("[REPORT-EXPORT-CONTRACT] \(overallPass ? "PASS" : "FAIL") dir=\(outputDir.path)")
            print("[REPORT-EXPORT-CONTRACT] report=\(reportPath)")
            print("[REPORT-EXPORT-CONTRACT] pdf=\(pdfPath) bytes=\(pdfBytes)")
        } catch {
            writeError = String(describing: error)
            let overallPass = false
            let body = reportBody(
                overallPass: overallPass,
                contractPass: contractPass,
                failures: failures,
                counts: counts,
                pdfWriteOK: pdfWriteOK,
                pdfBytes: pdfBytes,
                outputDir: outputDir.path,
                reportPath: reportPath,
                pdfPath: pdfPath,
                writeError: writeError
            )
            writePointer(body)
            print("[REPORT-EXPORT-CONTRACT] FAIL writeError=\(writeError) dir=\(outputDir.path)")
        }
    }

    private static func syntheticMedicineSummary() -> CheckMedStore.MedicineSummary {
        CheckMedStore.MedicineSummary(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID(),
            treatmentId: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
            name: "Synthetic Amoxicillin",
            doseLabel: "500 mg",
            frequency: "twice daily",
            duration: "7 days",
            timesPerDay: 2,
            treatmentTitle: "Synthetic treatment",
            treatmentStatus: "active",
            form: .tablet,
            packageAmount: 14,
            packageUnit: .tablet,
            stockPercent: 1,
            quantityPerDose: 1,
            doseUnit: .tablet,
            doctorName: "Dr Synthetic",
            doctorId: "",
            hospitalName: "Synthetic Clinic",
            doctorNotes: "",
            reason: "contract fixture",
            lastRefillAt: nil,
            refillRemindEnabled: false,
            daysLeft: nil,
            scheduleTimes: ["08:00", "20:00"],
            daysOnTreatment: 3,
            missedCount: 1,
            refillDataComplete: true
        )
    }

    private static func reportBody(
        overallPass: Bool,
        contractPass: Bool,
        failures: [String],
        counts: MedicineReportAdherence.Counts,
        pdfWriteOK: Bool,
        pdfBytes: Int,
        outputDir: String,
        reportPath: String,
        pdfPath: String,
        writeError: String
    ) -> String {
        var lines = [
            "result: \(overallPass ? "PASS" : "FAIL")",
            "suite: MedicineReportExportContractChecks",
            "contractResult: \(contractPass ? "PASS" : "FAIL")",
            "failures: \(failures.count)",
            "takenCount: \(counts.takenCount)",
            "missedCount: \(counts.missedCount)",
            "unrecordedDueCount: \(counts.unrecordedDueCount)",
            "plannedCount: \(counts.plannedCount)",
            "percent: \(counts.percent)",
            "patientName: Jordan",
            "pdfWriteOK: \(pdfWriteOK)",
            "pdfBytes: \(pdfBytes)",
            "outputDir: \(outputDir)",
            "reportPath: \(reportPath)",
            "pdfPath: \(pdfPath)",
        ]
        if !writeError.isEmpty {
            lines.append("writeError: \(writeError)")
        }
        if failures.isEmpty {
            lines.append("failureNames: (none)")
        } else {
            lines.append("failureNames:")
            lines.append(contentsOf: failures.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func writePointerAndLog(blocked: String) {
        let body = [
            "result: BLOCKED",
            "suite: MedicineReportExportContractChecks",
            "blocked: \(blocked)",
        ].joined(separator: "\n")
        writePointer(body)
        print("[REPORT-EXPORT-CONTRACT] BLOCKED \(blocked)")
    }

    private static func writePointer(_ body: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[REPORT-EXPORT-CONTRACT] no Documents directory")
            return
        }
        try? body.write(
            to: docs.appendingPathComponent(pointerName),
            atomically: true,
            encoding: .utf8
        )
    }
}

struct MedicineReportExportContractHost: View {
    var body: some View {
        Text("MedicineReportExportContractChecks")
            .padding()
    }
}
#endif
