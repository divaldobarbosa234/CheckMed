import SwiftUI

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
                let items = CheckMedDemo.todayDoses.filter { $0.period == period.key }
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
                        ForEach(items, id: \.time) { dose in
                            Text("\(dose.time) · \(dose.name)")
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
}

struct UpcomingScreen: View {
    var body: some View {
        ScreenScaffold(title: "Upcoming", bubble: "Next up is evening Amoxicillin — I'll sit with you until then.") {
            CardBlock(kicker: "Next dose", title: "20:00 · Amoxicillin 500mg")
            CardBlock(kicker: "Later today", title: "Ibuprofen 400mg · as needed")
            CardBlock(kicker: "Tomorrow", title: "Same plan · 08:00 / 20:00 Amoxicillin")
            CardBlock(kicker: "Upcoming treatments", title: "Antibiotic course ends Aug 30")
        }
    }
}

struct DailySummaryScreen: View {
    var body: some View {
        ScreenScaffold(
            title: "Daily summary",
            philSize: 128,
            bubble: "Phil: That's a full day. Your 6-day streak is still glowing."
        ) {
            Text("You did it!")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            Text("3/3 doses today")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.primaryShadow)
            SafetyCaption().frame(maxWidth: .infinity)
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

    var body: some View {
        ScreenScaffold(
            title: "Treatment overview",
            kicker: "Treatment",
            bubble: "7 days · 80%. Started Aug 24 · Ends Aug 30."
        ) {
            Text("Antibiotic Treatment")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CheckMedTheme.locked)
                    Capsule()
                        .fill(CheckMedTheme.primary)
                        .frame(width: geo.size.width * 0.8)
                }
            }
            .frame(height: 12)
            CheckMedButton(title: "My medicines", style: .secondary) { go(.medicationList) }
            CheckMedButton(title: "Timeline", style: .secondary) { go(.treatmentTimeline) }
            CheckMedButton(title: "Edit treatment", style: .ghost) { go(.editTreatment) }
            CheckMedButton(title: "Medication library", style: .ghost) { go(.myMedicines) }
        }
    }
}

struct MedicationListScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(title: "Medication list", kicker: "MY MEDICINES") {
            Text("Active now")
                .font(.system(.title3, design: .rounded).weight(.heavy))
            ForEach(CheckMedDemo.medicines, id: \.name) { med in
                Button {
                    go(.medicationDetail)
                } label: {
                    HStack(spacing: 12) {
                        PhilView(size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(med.name)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.ink)
                            Text("\(med.schedule) · \(med.duration)")
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
                .buttonStyle(.plain)
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

    var body: some View {
        ScreenScaffold(title: "Treatment timeline") {
            ForEach(CheckMedDemo.timelineDays, id: \.date) { day in
                HStack {
                    Text(day.date)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                    Spacer()
                    Text(day.note)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                .padding(12)
                .background(day.status == "today" ? CheckMedTheme.belly : CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            CheckMedButton(title: "Overview", style: .ghost) { go(.treatmentOverview) }
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

    var body: some View {
        ScreenScaffold(title: "Next dose", kicker: "NEXT DOSE", philSize: 128, bubble: "20:00 · in 32 minutes") {
            Text("Amoxicillin 500mg")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            CheckMedButton(title: "View details") { go(.medicationDetail) }
            CheckMedButton(title: "Preview alarm", style: .secondary) { go(.medicationAlarm) }
        }
    }
}

struct MedicationAlarmScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(
            title: "Medication alarm",
            philSize: 140,
            bubble: "It's medicine time!"
        ) {
            Text("Amoxicillin 500mg · 20:00")
                .font(.system(.title3, design: .rounded).weight(.heavy))
            Text("Alarm placeholder — real notifications land later. Taken stays free.")
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            CheckMedButton(title: "Take now") { go(.confirmMedication) }
            CheckMedButton(title: "Snooze", style: .ghost) { go(.nextDose) }
        }
    }
}

struct ConfirmMedicationScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path

    var body: some View {
        ScreenScaffold(title: "Confirm medication", philSize: 128, bubble: "Did you take it?") {
            Text("Amoxicillin 500mg · 1 capsule")
                .font(.system(.title3, design: .rounded).weight(.heavy))
            CheckMedButton(title: "Yes, I took it") {
                path.takeCurrent()
                go(.doseCompleted)
            }
            CheckMedButton(title: "Not yet", style: .secondary) { go(.missedDose) }
        }
    }
}

struct DoseCompletedScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(
            title: "Dose completed",
            philSize: 140,
            bubble: "Nice work! Streak continues 🔥 \(CheckMedDemo.streakDays)"
        ) {
            Text("3/3 today")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            CheckMedButton(title: "Keep going") { go(.dailySummary) }
        }
    }
}

struct MissedDoseScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path

    var body: some View {
        ScreenScaffold(
            title: "Missed dose",
            bubble: "Phil is here — no shame. Let's just see what the plan says."
        ) {
            Text("This dose is still open")
                .font(.system(.title3, design: .rounded).weight(.heavy))
            Text("Amoxicillin 500mg · 14:00 window")
                .font(.system(.body, design: .rounded).weight(.bold))
            CheckMedButton(title: "Take now") { go(.confirmMedication) }
            CheckMedButton(title: "Skip for now", style: .secondary) {
                path.skipCurrent()
                go(.nextDose)
            }
            CheckMedButton(title: "View instructions", style: .ghost) { go(.howToTake) }
            Text("CheckMed never tells you to double a dose. Follow the prescription, or ask your clinician or pharmacist.")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
        }
    }
}

struct ReminderSettingsScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(title: "Reminder settings", bubble: "Reminders · Amoxicillin") {
            ForEach(
                ["Notifications on", "08:00 · 14:00 · 20:00", "Sound · Chime", "Haptics on", "Quiet hours 22:30–07:00"],
                id: \.self
            ) { item in
                Text("• \(item)")
                    .font(.system(.body, design: .rounded).weight(.bold))
            }
            CheckMedButton(title: "All preferences", style: .secondary) { go(.notificationPrefs) }
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
    @Environment(EntitlementStore.self) private var entitlements

    var body: some View {
        ScreenScaffold(
            title: "Progress dashboard",
            philSize: 120,
            bubble: "Phil: Progress is a streak of small wins — not perfection."
        ) {
            Text("You're on a roll")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            Text("🔥 \(CheckMedDemo.streakDays) DAYS")
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.streak)
            HStack {
                stat("87%", "taken as planned")
                stat("18/21", "doses")
                stat("🏆 2", "treatments")
            }
            CheckMedButton(title: "Calendar", style: .secondary) { go(.adherence) }
            CheckMedButton(title: "Treatment history", style: .secondary) { go(.treatmentHistory) }
            Button {
                if !entitlements.isSuper {
                    entitlements.presentPaywall()
                } else {
                    go(.treatmentHistory)
                }
            } label: {
                HStack {
                    Text("Longer filters")
                        .font(.system(.body, design: .rounded).weight(.bold))
                    Spacer()
                    Text(entitlements.isSuper ? "Week · Month" : "Super")
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
    private let cells = ["done", "done", "done", "miss", "done", "done", "today", "soon", "soon", "soon", "soon", "soon", "soon", "soon"]

    var body: some View {
        ScreenScaffold(title: "Adherence") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, kind in
                    Text("\(index + 17)")
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .frame(width: 36, height: 36)
                        .background(cellColor(kind), in: Circle())
                        .foregroundStyle(kind == "soon" ? CheckMedTheme.muted : CheckMedTheme.ink)
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

    var body: some View {
        ScreenScaffold(title: "Treatment history", bubble: "Taken days count for the streak. Skip does not break it.") {
            CardBlock(kicker: "ACTIVE", title: "Antibiotic · Aug 2026")
            CardBlock(kicker: "COMPLETED", title: "Pain plan · Jul 2026")
            CheckMedButton(title: "Preview completion", style: .secondary) { go(.treatmentComplete) }
        }
    }
}

struct TreatmentCompleteScreen: View {
    var go: (AppRoute) -> Void

    var body: some View {
        ScreenScaffold(
            title: "Treatment complete",
            philSize: 140,
            bubble: "Phil: You finished the course. That's something to be proud of."
        ) {
            Text("Treatment complete!")
                .font(.system(.title2, design: .rounded).weight(.heavy))
            Text("7 days · 21 doses · 19 completed")
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            CheckMedButton(title: "View summary") { go(.progressDashboard) }
        }
    }
}

// MARK: - 08 Medication library (36–37)

struct MyMedicinesScreen: View {
    var go: (AppRoute) -> Void
    @State private var query = ""

    var body: some View {
        ScreenScaffold(title: "My medicines") {
            TextField("Search", text: $query)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.locked, lineWidth: 2))
            HStack {
                Text("Active")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(CheckMedTheme.primary, in: Capsule())
                    .foregroundStyle(.white)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                Text("Completed").font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(CheckMedTheme.muted)
                Text("Archived").font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(CheckMedTheme.muted)
            }
            ForEach(CheckMedDemo.medicines.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }, id: \.name) { med in
                Button { go(.medicineHistory) } label: {
                    HStack {
                        PhilView(size: 52)
                        VStack(alignment: .leading) {
                            Text(med.name)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.ink)
                            Text(med.status)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MedicineHistoryScreen: View {
    var body: some View {
        ScreenScaffold(title: "Medicine history", bubble: "Doses and prescriptions stay on the record — you can show this to a clinician.") {
            Text("Amoxicillin history")
                .font(.system(.title3, design: .rounded).weight(.heavy))
            CardBlock(kicker: "Current", title: "Aug 24–30 · 3× daily")
            CardBlock(kicker: "Previous", title: "Mar 2026 · 5-day course")
        }
    }
}

// MARK: - 09 Profile extras (39–40)

struct NotificationPrefsScreen: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScreenScaffold(title: session.t(.prefsTitle), bubble: session.t(.prefsBubble)) {
            ForEach(L10n.prefsItems(session.locale), id: \.self) { item in
                Text("• \(item)")
                    .font(.system(.body, design: .rounded).weight(.bold))
            }
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
