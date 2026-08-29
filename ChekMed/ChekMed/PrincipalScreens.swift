import SwiftUI
import UserNotifications

// MARK: - 02 Home (07–09)

struct TodayTreatmentScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var periods: [(key: String, label: String)] {
        [
            ("Morning", session.t(.morning)),
            ("Afternoon", session.t(.afternoon)),
            ("Evening", session.t(.evening)),
            ("Night", session.t(.night)),
        ]
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.homeTodaysTreatment),
            kicker: session.t(.homeTodaysTreatment),
            bubble: "Phil: Morning's done. Evening is still open whenever you're ready."
        ) {
            Text(session.t(.todayGlance))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            ForEach(periods, id: \.key) { period in
                let items = path.nodes.filter { node in
                    period.key == Self.period(for: node.time)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(period.label)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                    if items.isEmpty {
                        Text(session.t(.todayNothing))
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    } else {
                        ForEach(items) { dose in
                            Text("\(dose.time) · \(dose.medicine)")
                                .font(.system(.body, design: .rounded).weight(.bold))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if path.current != nil {
                Text(session.t(.takenStaysFree))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                HStack {
                    CheckMedButton(title: session.t(.taken)) { path.takeCurrent() }
                    CheckMedButton(title: session.t(.skip), style: .secondary) { path.skipCurrent() }
                }
            }
            CheckMedButton(title: session.t(.homeUpcoming), style: .secondary) { go(.upcoming) }
            CheckMedButton(title: session.t(.todayBackHome), style: .ghost) { dismiss() }
            SafetyCaption().frame(maxWidth: .infinity)
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
}

struct UpcomingScreen: View {
    @Environment(TodayPathStore.self) private var path
    @Environment(SessionStore.self) private var session

    private var remaining: [DoseNode] {
        path.nodes.filter { $0.status == .current || $0.status == .locked }
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.homeUpcoming),
            bubble: remaining.first.map { "Next up is \($0.medicine) at \($0.time)." }
                ?? session.t(.todayNothing)
        ) {
            if remaining.isEmpty {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                ForEach(remaining) { node in
                    CardBlock(kicker: node.time, title: "\(node.medicine) · \(node.detail)")
                }
            }
        }
    }
}

struct DailySummaryScreen: View {
    @Environment(TodayPathStore.self) private var path
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScreenScaffold(
            title: session.t(.homeSummary),
            philSize: 128,
            bubble: path.pathComplete
                ? "Phil: That's a full day. I'm proud of you."
                : "Phil: We'll keep going together."
        ) {
            Text(path.pathComplete ? "You did it!" : session.t(.homeToday))
                .font(.system(.title2, design: .rounded).weight(.heavy))
            Text("\(path.takenCount)/\(max(path.total, 1)) \(session.t(.taken).lowercased())")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.primaryShadow)
            if path.skippedCount > 0 {
                Text("\(path.skippedCount) \(session.t(.skipped).lowercased())")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            ForEach(path.nodes) { node in
                Text("\(node.time) · \(node.medicine) · \(statusLabel(for: node.status))")
                    .font(.system(.body, design: .rounded).weight(.bold))
            }
            SafetyCaption().frame(maxWidth: .infinity)
        }
    }

    private func statusLabel(for status: PathStatus) -> String {
        switch status {
        case .done: session.t(.logged)
        case .skipped: session.t(.skipped)
        case .current: session.t(.homeNextDose)
        case .locked: session.t(.locked)
        }
    }
}

// MARK: - 03 Prescription intelligence (10–15)

struct AddPrescriptionScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScreenScaffold(
            title: session.t(.scanAddTitle),
            kicker: session.t(.scanKicker),
            philSize: 128,
            bubble: session.canSync
                ? session.t(.scanBubbleSync)
                : session.t(.scanBubbleGuest)
        ) {
            CheckMedButton(title: session.t(.scanTakePhoto)) { go(.cameraScanner) }
            CheckMedButton(title: session.t(.scanChoosePhotos), style: .secondary) { go(.cameraScanner) }
            CheckMedButton(title: session.t(.scanImportPDF), style: .secondary) { go(.scanning) }
            CheckMedButton(title: session.t(.scanImportFile), style: .ghost) { go(.scanning) }
            Text(session.t(.scanLaterDigital))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            SafetyCaption().frame(maxWidth: .infinity)
        }
    }
}

struct CameraScannerScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScreenScaffold(
            title: session.t(.scanCameraTitle),
            philSize: 72,
            bubble: session.t(.scanCameraBubble)
        ) {
            Text(session.t(.scanKeepFrame))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.ink, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                .frame(height: 220)
                .overlay {
                    Text(session.t(.scanViewfinder))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            CheckMedButton(title: session.t(.scanCapture)) { go(.scanning) }
        }
    }
}

struct ScanningScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScreenScaffold(
            title: session.t(.scanScanningTitle),
            philSize: 140,
            bubble: session.t(.scanScanningBubble)
        ) {
            ProgressView()
                .frame(maxWidth: .infinity)
            Text(session.t(.scanScanningBody))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            CheckMedButton(title: session.t(.continueButton)) { go(.extractionResults) }
        }
    }
}

struct ExtractionResultsScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(
            title: "Extraction results",
            kicker: "Prescription detected",
            bubble: "Littmann · structured extraction"
        ) {
            Text("What we read")
                .font(.system(.title3, design: .rounded).weight(.heavy))
            FactBlock(label: "Doctor", value: "Dr. Rivera")
            FactBlock(label: "Date", value: "24 Aug 2026")
            FactBlock(label: "Patient", value: "Alex")
            FactBlock(label: "Medicine", value: "Amoxicillin 500mg")
            CheckMedButton(title: "Review") { go(.verifyPrescription) }
            SafetyCaption().frame(maxWidth: .infinity)
        }
    }
}

struct VerifyPrescriptionScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(
            title: "Verify prescription",
            kicker: "Verify with Littmann",
            bubble: "Please confirm this matches the paper. CheckMed does not add or invent doses."
        ) {
            Text("Is this correct?")
                .font(.system(.title3, design: .rounded).weight(.heavy))
            VStack(alignment: .leading, spacing: 8) {
                Text("From the prescription record")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(CheckMedTheme.muted)
                Text("AMOXICILLIN 500mg")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                Text("1 capsule · 3× daily · 7 days")
                    .font(.system(.body, design: .rounded).weight(.bold))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CheckMedTheme.ink, lineWidth: 2)
            )
            CheckMedButton(title: "Yes, save") { go(.prescriptionSaved) }
            CheckMedButton(title: "Edit", style: .secondary) { go(.editTreatment) }
            SafetyCaption().frame(maxWidth: .infinity)
        }
    }
}

struct PrescriptionSavedScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(
            title: "Prescription saved",
            philSize: 140,
            bubble: "Perfect! I've got it."
        ) {
            Text("First treatment stays free. Super never locks this editor.")
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            CheckMedButton(title: "Build my treatment plan") { go(.treatmentOverview) }
        }
    }
}

// MARK: - 04 Treatment (16–21)

struct TreatmentOverviewScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    private var medicines: [CheckMedStore.MedicineSummary] { treatments.medicineSummaries() }

    var body: some View {
        ScreenScaffold(
            title: session.t(.tabTreatments),
            kicker: session.t(.tabTreatments),
            bubble: medicines.isEmpty
                ? "Phil: Add a prescription and I'll keep the plan here with you."
                : "Phil: Here's what we're organizing together."
        ) {
            if medicines.isEmpty {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                CheckMedButton(title: session.t(.homeScan)) { go(.addPrescription) }
            } else {
                ForEach(medicines) { med in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(med.name)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                        Text("\(med.doseLabel) · \(med.frequency) · \(med.duration)")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
                    )
                }
                CheckMedButton(title: session.t(.homeScan), style: .secondary) { go(.addPrescription) }
                CheckMedButton(title: session.t(.profileMedicines), style: .ghost) { go(.medicationList) }
            }
        }
    }
}

struct MedicationListScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    private var medicines: [CheckMedStore.MedicineSummary] { treatments.medicineSummaries() }

    var body: some View {
        ScreenScaffold(title: session.t(.profileMedicines), kicker: session.t(.profileLibrary)) {
            Text(session.t(.profileMedicines))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            if medicines.isEmpty {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                ForEach(medicines) { med in
                    HStack(spacing: 12) {
                        PhilView(size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(med.name)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.ink)
                            Text("\(med.doseLabel) · \(med.frequency) · \(med.duration)")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
                    )
                }
            }
        }
    }
}

struct MedicationDetailScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(title: "Medication detail", bubble: "Littmann Phil explains the record — not new medical advice.") {
            Text("Amoxicillin 500mg")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            FactBlock(label: "What it is", value: "Penicillin-class antibiotic (from the medication record).")
            FactBlock(label: "Why taking", value: "As written on this 7-day prescription.")
            FactBlock(label: "Dosage", value: "1 capsule")
            FactBlock(label: "Schedule", value: "3× daily")
            FactBlock(label: "Duration", value: "7 days (Aug 24–30)")
            SourceNote()
            CheckMedButton(title: "How to take it") { go(.howToTake) }
            CheckMedButton(title: "Full explanation", style: .secondary) { go(.medicineExplanation) }
        }
    }
}

struct HowToTakeScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(title: "How to take it", bubble: "Visual from your saved plan. If the label differs, follow the prescription.") {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. 1 capsule")
                Text("2. With water")
                Text("3. Every 8 hours")
            }
            .font(.system(.title3, design: .rounded).weight(.heavy))
            CheckMedButton(title: "Back", style: .ghost) { go(.medicationDetail) }
        }
    }
}

struct TreatmentTimelineScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    var body: some View {
        let cells = treatments.dayStatuses()
        ScreenScaffold(title: session.t(.progressCalendar)) {
            if cells.isEmpty {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    HStack {
                        Text("\(cell.day)")
                            .font(.system(.body, design: .rounded).weight(.heavy))
                        Spacer()
                        Text(timelineNote(cell.kind))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    .padding(12)
                    .background(cell.kind == "today" ? CheckMedTheme.belly : CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            CheckMedButton(title: session.t(.tabTreatments), style: .ghost) { go(.treatmentOverview) }
        }
    }

    private func timelineNote(_ kind: String) -> String {
        switch kind {
        case "done": session.t(.logged)
        case "miss": session.t(.skipped)
        case "today": session.t(.homeToday)
        default: session.t(.homeUpcoming)
        }
    }
}

struct EditTreatmentScreen: View {
    var go: (AppRoute) -> Void
    @State private var dose = "1 capsule"
    @State private var frequency = "3× daily"
    @State private var times = "08:00 · 14:00 · 20:00"
    @State private var duration = "7 days"
    @State private var instructions = "With water"

    var body: some View {
        ScreenScaffold(
            title: "Edit treatment",
            bubble: "Changing times does not change the prescribed amount. CheckMed will never suggest doubling a missed dose."
        ) {
            field("Dose", text: $dose)
            field("Frequency", text: $frequency)
            field("Time", text: $times)
            field("Duration", text: $duration)
            field("Instructions", text: $instructions)
            Text("First treatment editor stays free.")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            CheckMedButton(title: "Save") { go(.verifyPrescription) }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            TextField(title, text: text)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
        }
    }
}

// MARK: - 05 Medication experience (22–27)

struct NextDoseScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path
    @Environment(SessionStore.self) private var session

    private var next: DoseNode? {
        path.nodes.first { $0.status == .current || $0.status == .locked }
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.homeNextDose),
            kicker: session.t(.homeNextDose),
            philSize: 128,
            bubble: next.map { "\($0.time) · \($0.medicine)" } ?? session.t(.todayNothing)
        ) {
            Text(next?.medicine ?? session.t(.todayNothing))
                .font(.system(.title2, design: .rounded).weight(.heavy))
            if let next {
                VoiceReadButton(text: session.t(.notificationDoseBody, next.medicine, next.detail, next.time))
                CheckMedButton(title: session.t(.homeAlarm), style: .secondary) { go(.medicationAlarm) }
            }
        }
    }
}

struct MedicationAlarmScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(SessionStore.self) private var session
    @State private var theme = ReminderPreferences.alarmTheme

    private var next: DoseNode? {
        path.overdue ?? path.nodes.first { $0.status == .current }
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.homeAlarm),
            philSize: 140,
            bubble: path.overdue != nil ? session.t(.philMissedBubble) : session.t(.philAlarmBubble)
        ) {
            Text(next.map { "\($0.medicine) · \($0.time)" } ?? session.t(.todayNothing))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            if let next {
                VoiceReadButton(text: session.t(.notificationDoseBody, next.medicine, next.detail, next.time))
            }
            AlarmThemePicker(theme: $theme)
            Text(session.t(.takenStaysFree))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            if next != nil {
                CheckMedButton(title: session.t(.taken)) { go(.confirmMedication) }
            }
            CheckMedButton(title: session.t(.homeNextDose), style: .ghost) { go(.nextDose) }
        }
        .onAppear { theme = ReminderPreferences.alarmTheme }
    }
}

struct ConfirmMedicationScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScreenScaffold(title: session.t(.taken), philSize: 128, bubble: "Did you take it?") {
            Text(path.current.map { "\($0.medicine) · \($0.detail)" } ?? session.t(.todayNothing))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            CheckMedButton(title: session.t(.taken)) {
                path.takeCurrent()
                go(.doseCompleted)
            }
            CheckMedButton(title: session.t(.skip), style: .secondary) {
                path.skipCurrent()
                go(.nextDose)
            }
        }
    }
}

struct DoseCompletedScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScreenScaffold(
            title: session.t(.doseCompletedTitle),
            philSize: 140,
            bubble: "Nice work! Streak continues 🔥 \(path.streakDays)"
        ) {
            Text("\(path.completed)/\(max(path.total, 1))")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            CheckMedButton(title: session.t(.keepGoing)) { go(.dailySummary) }
        }
    }
}

struct MissedDoseScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path
    @Environment(SessionStore.self) private var session

    private var target: DoseNode? { path.overdue ?? path.current }

    var body: some View {
        ScreenScaffold(
            title: session.t(.missedDoseTitle),
            bubble: session.t(.philMissedBubble)
        ) {
            Text(session.t(.missedStillOpen))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            Text(target.map { "\($0.medicine) · \($0.time)" } ?? session.t(.todayNothing))
                .font(.system(.body, design: .rounded).weight(.bold))
            if let target {
                VoiceReadButton(text: session.t(.notificationMissedBody, target.medicine, target.time))
            }
            CheckMedButton(title: session.t(.missedTakeNow)) { go(.confirmMedication) }
            CheckMedButton(title: session.t(.missedSkipForNow), style: .secondary) {
                path.skipCurrent()
                go(.nextDose)
            }
            CheckMedButton(title: session.t(.homeTodaysTreatment), style: .ghost) { go(.todayTreatment) }
            Text(session.t(.missedNeverDouble))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
        }
    }
}

struct ReminderSettingsScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(EntitlementStore.self) private var entitlements
    @State private var theme = ReminderPreferences.alarmTheme
    @State private var drafts: [ReminderDraft] = []

    var body: some View {
        ScreenScaffold(title: session.t(.profileReminders), bubble: session.t(.prefsBubble)) {
            let times = treatments.reminderTimesLabel()
            Text(times.isEmpty ? session.t(.remindersNoneScheduled) : times)
                .font(.system(.title3, design: .rounded).weight(.heavy))
            if drafts.isEmpty {
                Text(session.t(.remindersNoneScheduled))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                Text(session.t(.remindersScheduled))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                ForEach(drafts.prefix(8)) { draft in
                    Text("• \(draft.time) · \(draft.medicine)")
                        .font(.system(.body, design: .rounded).weight(.bold))
                }
            }
            AlarmThemePicker(theme: $theme)
            if !entitlements.canUseVoiceReading {
                Text(session.t(.voiceLockedHint))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            CheckMedButton(title: session.t(.prefsTitle), style: .secondary) { go(.notificationPrefs) }
        }
        .onAppear {
            theme = ReminderPreferences.alarmTheme
            drafts = treatments.reminderDrafts().filter { $0.kind == .dose }
        }
    }
}

// MARK: - 06 Medication knowledge (28–31)

struct MedicineExplanationScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(
            title: "Medicine explanation",
            kicker: "Littmann · medication record",
            bubble: "What is Amoxicillin 500mg?"
        ) {
            Text(CheckMedDemo.classLabel)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(CheckMedTheme.belly, in: Capsule())
            FactBlock(label: "What it does", value: CheckMedDemo.whatItDoes)
            FactBlock(label: "Why prescribed", value: CheckMedDemo.whyPrescribed)
            FactBlock(label: "How normally taken", value: CheckMedDemo.howTaken)
            SourceNote()
            CheckMedButton(title: "Side effects", style: .secondary) { go(.sideEffects) }
            CheckMedButton(title: "Warnings", style: .secondary) { go(.warningsInteractions) }
        }
    }
}

struct SideEffectsScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(title: "Side effects", kicker: "Littmann · safety information") {
            Text("Common").font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(CheckMedTheme.muted)
            ForEach(CheckMedDemo.common, id: \.self) { Text("• \($0)").font(.system(.body, design: .rounded).weight(.bold)) }
            Text("Less common").font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(CheckMedTheme.muted)
            ForEach(CheckMedDemo.lessCommon, id: \.self) { Text("• \($0)").font(.system(.body, design: .rounded).weight(.bold)) }
            Text("Seek medical attention")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.danger)
            ForEach(CheckMedDemo.serious, id: \.self) {
                Text("• \($0)")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.danger)
            }
            SourceNote()
            CheckMedButton(title: "Back", style: .ghost) { go(.medicineExplanation) }
        }
    }
}

struct WarningsScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(title: "Warnings & interactions", kicker: "Littmann · safety information") {
            FactBlock(label: "Interactions", value: CheckMedDemo.interactions)
            FactBlock(label: "Allergies", value: CheckMedDemo.allergies)
            FactBlock(label: "Contraindications", value: CheckMedDemo.contraindications)
            FactBlock(label: "Food / alcohol", value: CheckMedDemo.food)
            SourceNote()
            CheckMedButton(title: "Questions for your doctor", style: .secondary) { go(.questionsForDoctor) }
        }
    }
}

struct QuestionsForDoctorScreen: View {
    @State private var question = "How long until I should feel better?"

    var body: some View {
        ScreenScaffold(
            title: "Questions for doctor",
            bubble: "Phil: Want to remember something for your next appointment?"
        ) {
            Text("Add a question")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            TextField("Your question", text: $question)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
            Text("• \(question.isEmpty ? "Your question will show here" : question)")
                .font(.system(.body, design: .rounded).weight(.bold))
        }
    }
}

// MARK: - 07 Progress (32–35)

struct ProgressDashboardScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CheckMedStore.self) private var treatments

    private var stats: AdherenceSnapshot { treatments.adherence() }

    var body: some View {
        ScreenScaffold(
            title: session.t(.progressTitle),
            philSize: 120,
            bubble: stats.hasHistory
                ? "Phil: Progress is a streak of small wins — not perfection."
                : session.t(.progressEmptyBubble)
        ) {
            Text(stats.hasHistory ? session.t(.progressOnARoll) : session.t(.progressEmptyBody))
                .font(.system(.title2, design: .rounded).weight(.heavy))
            Text("🔥 \(stats.streakDays)")
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.streak)
            if stats.hasHistory {
                HStack {
                    stat(stats.percent.map { "\($0)%" } ?? "—", session.t(.progressTakenAsPlanned))
                    stat("\(stats.takenCount)/\(stats.plannedCount)", session.t(.progressDosesLabel))
                    stat("\(stats.treatmentCount)", session.t(.progressTreatmentsLabel))
                }
            } else {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            CheckMedButton(title: session.t(.backToDashboard)) {
                session.showHomeTab()
            }
            CheckMedButton(title: session.t(.progressCalendar), style: .secondary) { go(.adherence) }
            CheckMedButton(title: session.t(.progressHistory), style: .secondary) { go(.treatmentHistory) }
            Button {
                if !entitlements.isSuper {
                    entitlements.presentPaywall()
                } else {
                    go(.treatmentHistory)
                }
            } label: {
                HStack {
                    Text(session.t(.longerFilters))
                        .font(.system(.body, design: .rounded).weight(.bold))
                    Spacer()
                    Text(entitlements.isSuper ? "Week · Month" : session.t(.paywallSuper))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(entitlements.isSuper ? CheckMedTheme.superAccent : CheckMedTheme.muted)
                }
                .padding(16)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.black))
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AdherenceScreen: View {
    @Environment(CheckMedStore.self) private var treatments

    private var cells: [(day: Int, kind: String)] { treatments.dayStatuses() }

    var body: some View {
        ScreenScaffold(title: "Adherence") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    Text("\(cell.day)")
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .frame(width: 36, height: 36)
                        .background(cellColor(cell.kind), in: Circle())
                        .foregroundStyle(cell.kind == "soon" ? CheckMedTheme.muted : CheckMedTheme.ink)
                }
            }
            Text("Green completed · Gray still open · Light upcoming")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
    }

    private func cellColor(_ kind: String) -> Color {
        switch kind {
        case "done": CheckMedTheme.primary.opacity(0.85)
        case "miss": CheckMedTheme.locked
        case "today": CheckMedTheme.current.opacity(0.45)
        default: CheckMedTheme.locked.opacity(0.5)
        }
    }
}

struct TreatmentHistoryScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    private var medicines: [CheckMedStore.MedicineSummary] { treatments.medicineSummaries() }

    var body: some View {
        ScreenScaffold(title: session.t(.progressHistory), bubble: session.t(.progressEmptyBody)) {
            if medicines.isEmpty {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                ForEach(medicines) { med in
                    CardBlock(kicker: med.treatmentTitle, title: "\(med.name) · \(med.frequency)")
                }
            }
            CheckMedButton(title: session.t(.homeScan), style: .secondary) { go(.addPrescription) }
        }
    }
}

struct TreatmentCompleteScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    private var stats: AdherenceSnapshot { treatments.adherence() }

    var body: some View {
        ScreenScaffold(
            title: session.t(.progressTitle),
            philSize: 140,
            bubble: stats.hasHistory
                ? "Phil: You finished the course. That's something to be proud of."
                : session.t(.progressEmptyBubble)
        ) {
            Text(stats.hasHistory ? session.t(.progressOnARoll) : session.t(.progressEmptyBody))
                .font(.system(.title2, design: .rounded).weight(.heavy))
            if stats.hasHistory {
                Text("\(stats.takenCount)/\(stats.plannedCount) \(session.t(.progressDosesLabel))")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            CheckMedButton(title: session.t(.progressTitle)) { go(.progressDashboard) }
        }
    }
}

// MARK: - 08 Medication library (36–37)

struct MyMedicinesScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @State private var query = ""

    private var medicines: [CheckMedStore.MedicineSummary] {
        treatments.medicineSummaries().filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScreenScaffold(title: session.t(.profileMedicines)) {
            TextField("Search", text: $query)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.locked, lineWidth: 2))
            if medicines.isEmpty {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                ForEach(medicines) { med in
                    HStack {
                        PhilView(size: 52)
                        VStack(alignment: .leading) {
                            Text(med.name)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.ink)
                            Text("\(med.doseLabel) · \(med.frequency)")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

struct MedicineHistoryScreen: View {
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    private var medicines: [CheckMedStore.MedicineSummary] { treatments.medicineSummaries() }

    var body: some View {
        ScreenScaffold(title: session.t(.profileMedicines), bubble: session.t(.progressEmptyBody)) {
            if medicines.isEmpty {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                ForEach(medicines) { med in
                    Text(med.name)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                    CardBlock(kicker: med.frequency, title: "\(med.doseLabel) · \(med.treatmentTitle)")
                }
            }
        }
    }
}

// MARK: - 09 Profile extras (39–40)

struct NotificationPrefsScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @State private var quietHours = ReminderPreferences.quietHoursEnabled
    @State private var voiceReminders = ReminderPreferences.voiceRemindersEnabled
    @State private var theme = ReminderPreferences.alarmTheme
    @State private var authorized = false

    var body: some View {
        ScreenScaffold(title: session.t(.prefsTitle), bubble: session.t(.prefsBubble)) {
            Text(authorized ? session.t(.notifsEnable) : session.t(.remindersPermissionOff))
                .font(.system(.body, design: .rounded).weight(.bold))
            Toggle(session.t(.prefsQuietToggle), isOn: $quietHours)
                .font(.system(.body, design: .rounded).weight(.bold))
                .onChange(of: quietHours) { _, value in
                    ReminderPreferences.quietHoursEnabled = value
                    ReminderScheduler.shared.reschedule()
                }
            Toggle(session.t(.voiceRemindersToggle), isOn: $voiceReminders)
                .font(.system(.body, design: .rounded).weight(.bold))
                .disabled(!entitlements.canUseVoiceReading)
                .onChange(of: voiceReminders) { _, value in
                    if entitlements.canUseVoiceReading {
                        ReminderPreferences.voiceRemindersEnabled = value
                    } else {
                        voiceReminders = false
                        entitlements.presentPaywall()
                    }
                }
            if !entitlements.canUseVoiceReading {
                Text(session.t(.voiceLockedHint))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            AlarmThemePicker(theme: $theme)
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            quietHours = ReminderPreferences.quietHoursEnabled
            voiceReminders = entitlements.canUseVoiceReading && ReminderPreferences.voiceRemindersEnabled
            theme = ReminderPreferences.alarmTheme
        }
    }
}

struct SettingsScreen: View {
    @Environment(SessionStore.self) private var session
    var go: (AppRoute) -> Void
    @State private var nameDraft = ""

    var body: some View {
        ScreenScaffold(title: session.t(.settingsTitle), bubble: session.t(.settingsBubble)) {
            nameField
            DateOfBirthSelectField(
                date: Binding(
                    get: { session.birthDate },
                    set: { session.setBirthDate($0) }
                )
            )
            LanguageSelectField(
                locale: Binding(
                    get: { session.locale },
                    set: { session.setLocale($0) }
                )
            )
            TimeZoneSelectField(
                timeZone: Binding(
                    get: { session.timeZoneName },
                    set: { session.setTimeZoneName($0) }
                )
            )
            PronounSelectField(
                value: Binding(
                    get: { session.pronouns },
                    set: { session.setPronouns($0) }
                )
            )
            GenderSelectField(
                value: Binding(
                    get: { session.gender },
                    set: { session.setGender($0) }
                )
            )
            ForEach(L10n.settingsItems(session.locale), id: \.self) { item in
                if item == session.t(.settingsPrivacy) {
                    Button {
                        go(.privacySettings)
                    } label: {
                        settingsItemRow(item, tappable: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(session.t(.privacySettingsHint))
                } else {
                    settingsItemRow(item, tappable: false)
                }
            }
        }
        .onAppear {
            nameDraft = session.hasPreferredName ? session.displayName : ""
        }
        .onDisappear {
            session.setDisplayName(nameDraft)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.t(.preferredName))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CheckMedTheme.muted)
            TextField("Alex", text: $nameDraft)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
                .onSubmit { session.setDisplayName(nameDraft) }
        }
    }

    private func settingsItemRow(_ item: String, tappable: Bool) -> some View {
        HStack {
            Text(item)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.ink)
            Spacer()
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
