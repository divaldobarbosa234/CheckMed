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
            bubble: session.t(.scanBubbleSync)
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
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(TodayPathStore.self) private var path
    @State private var showFinishConfirm = false
    @State private var pendingDeleteMedicine: CheckMedStore.MedicineSummary?

    private var medicines: [CheckMedStore.MedicineSummary] { treatments.medicineSummaries() }
    private var medicineCount: Int { treatments.storedMedicineCount }
    private var remainingSlots: Int {
        entitlements.freeMedicineSlotsRemaining(existingCount: medicineCount)
    }
    private var incompleteMedicineNames: [String] {
        treatments.incompleteMedicineNamesForActivePlan()
    }

    private let pillTints: [Color] = [
        CheckMedTheme.flowDot,
        CheckMedTheme.cheek,
        Color(hex: 0x5FA86B),
        Color(hex: 0x9B7ED9),
        CheckMedTheme.current,
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                philBanner
                if medicines.isEmpty {
                    Text(session.t(.noTreatmentInProgressHeadline))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(medicines.enumerated()), id: \.element.id) { index, med in
                            medicineCard(med, tint: pillTints[index % pillTints.count])
                        }
                    }
                }
                if !entitlements.isSuper, medicineCount > 0 {
                    freeSlotsBanner
                }
                CheckMedButton(title: session.t(.homeScan), action: attemptAdd)
                    .padding(.top, 2)
                moreSection
                if !medicines.isEmpty {
                    CheckMedButton(title: session.t(.completeTreatment), style: .ghost) {
                        showFinishConfirm = true
                    }
                }
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.tabTreatments))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            treatments.pruneDuplicateAndFreeCap(isSuper: entitlements.isSuper)
        }
        .sheet(isPresented: $showFinishConfirm) {
            FinishTreatmentConfirmSheet(
                missingMedicineNames: incompleteMedicineNames,
                onScanNew: {
                    finishTreatment(then: .addPrescription)
                },
                onSeeReport: {
                    finishTreatment(then: .journeyReport)
                },
                onCancel: {
                    showFinishConfirm = false
                }
            )
            .environment(session)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            session.t(.deleteRecipeConfirm),
            isPresented: Binding(
                get: { pendingDeleteMedicine != nil },
                set: { if !$0 { pendingDeleteMedicine = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(session.t(.deleteRecipeYes), role: .destructive) {
                if let med = pendingDeleteMedicine {
                    confirmDeleteRecipe(med)
                }
            }
            Button(session.t(.cancel), role: .cancel) {
                pendingDeleteMedicine = nil
            }
        }
    }

    private func finishTreatment(then route: AppRoute) {
        // Mark completed — keep medicines/logs for journey history. Never soft-delete here.
        treatments.completeAllActiveTreatments()
        path.reload()
        ReminderScheduler.shared.reschedule()
        showFinishConfirm = false
        // Defer navigation so the sheet can dismiss before pushing the report / scan route.
        DispatchQueue.main.async {
            go(route)
        }
    }

    private var freeSlotsBanner: some View {
        let text: String = remainingSlots > 0
            ? session.t(.treatmentsSlotsLeft, medicineCount, remainingSlots)
            : session.t(.treatmentsSlotsFull)
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: remainingSlots > 0 ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CheckMedTheme.primaryShadow)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if remainingSlots == 0 {
                    Button(session.t(.treatmentsTrySuper)) {
                        entitlements.presentPaywall()
                    }
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.mintWash)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CheckMedTheme.primary.opacity(0.18), lineWidth: 1)
        )
    }

    private func attemptAdd() {
        if !entitlements.isSuper, remainingSlots <= 0 {
            entitlements.presentPaywall()
            return
        }
        go(.addPrescription)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Image(systemName: "pills.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CheckMedTheme.onPrimary)
                .frame(width: 36, height: 36)
                .background(CheckMedTheme.primary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(session.t(.tabTreatments))
                    .font(.system(.title, design: .rounded).weight(.black))
                Text(session.t(.treatmentsSubhead))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Spacer()
            Button { go(.settings) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(CheckMedTheme.surface, in: Circle())
                    .overlay(Circle().stroke(CheckMedTheme.hairline, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.profileSettings))
        }
    }

    private var philBanner: some View {
        ZStack {
            LinearGradient(
                colors: [CheckMedTheme.mintWash, CheckMedTheme.primary.opacity(0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(alignment: .bottom, spacing: 8) {
                PhilDoctor2DImage(size: 112)
                    .offset(y: 6)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Phil")
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                    Text(session.t(.treatmentsPhilBubble))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CheckMedTheme.surface.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 138)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func medicineCard(_ med: CheckMedStore.MedicineSummary, tint: Color) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                go(.medicationDetail(med.id))
            } label: {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 12) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 50, height: 50)
                            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        Text(med.name)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 44)
                    }
                    Rectangle()
                        .fill(CheckMedTheme.hairline)
                        .frame(height: 1)
                    HStack(spacing: 4) {
                        meta(icon: "pills", text: med.doseLabel)
                        meta(icon: "sun.max.fill", text: session.t(.timesPerDayFormat, med.timesPerDay))
                        meta(icon: "clock.fill", text: med.frequency)
                        meta(icon: "calendar", text: med.duration)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [CheckMedTheme.surface, tint.opacity(0.055)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.25)
                )
                .shadow(color: CheckMedTheme.navy.opacity(0.045), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(med.name)

            Menu {
                Button(role: .destructive) {
                    pendingDeleteMedicine = med
                } label: {
                    Label(session.t(.deleteRecipe), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(CheckMedTheme.surface.opacity(0.94), in: Circle())
            }
            .padding(10)
            .accessibilityLabel(session.t(.deleteRecipe))
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeleteMedicine = med
            } label: {
                Label(session.t(.deleteRecipe), systemImage: "trash")
            }
        }
    }

    /// Confirmed delete of *this* recipe only, then Scan. Other actives stay until the user deletes them.
    private func confirmDeleteRecipe(_ med: CheckMedStore.MedicineSummary) {
        pendingDeleteMedicine = nil
        treatments.deleteMedicine(id: med.id)
        path.reload()
        go(.addPrescription)
    }

    private func meta(icon: String, text: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CheckMedTheme.muted)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : text)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity)
    }

    private var moreSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(CheckMedTheme.hairline)
                    .frame(height: 1)
                Text(session.t(.treatmentsYourMeds))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize()
                Rectangle()
                    .fill(CheckMedTheme.hairline)
                    .frame(height: 1)
            }
            Button(action: attemptAdd) {
                HStack(spacing: 12) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                        .frame(width: 42, height: 42)
                        .background(CheckMedTheme.mintWash, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.t(.treatmentsNeedMore))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                        Text(session.t(.treatmentsNeedMoreBody))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [CheckMedTheme.surface, CheckMedTheme.mintWash],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.treatmentsNeedMore))
        }
    }
}

private struct FinishTreatmentConfirmSheet: View {
    @Environment(SessionStore.self) private var session
    let missingMedicineNames: [String]
    let onScanNew: () -> Void
    let onSeeReport: () -> Void
    let onCancel: () -> Void

    private var missingListLabel: String {
        missingMedicineNames.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(session.t(.finishTreatmentConfirmTitle))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                    Text(session.t(.finishTreatmentConfirmBody))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !missingMedicineNames.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(session.t(.finishTreatmentMissWarning, missingListLabel))
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(missingMedicineNames, id: \.self) { name in
                                HStack(spacing: 10) {
                                    Image(systemName: "pills.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(CheckMedTheme.danger)
                                    Text(name)
                                        .font(.system(.body, design: .rounded).weight(.heavy))
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .background(CheckMedTheme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CheckMedTheme.mintWash.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(CheckMedTheme.danger.opacity(0.28), lineWidth: 1.5)
                        )
                    }

                    CheckMedButton(title: session.t(.finishTreatmentScanNew), action: onScanNew)
                    CheckMedButton(title: session.t(.finishTreatmentSeeReport), style: .secondary, action: onSeeReport)
                    CheckMedButton(title: session.t(.cancel), style: .ghost, action: onCancel)
                }
                .padding(20)
            }
            .background(CheckMedTheme.background)
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
                            .stroke(CheckMedTheme.hairline, lineWidth: 2)
                    )
                }
            }
        }
    }
}

struct MedicationDetailScreen: View {
    var go: (AppRoute) -> Void
    var medicineId: UUID? = nil
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @Environment(TodayPathStore.self) private var path
    @State private var showDeleteRecipeConfirm = false

    private var medicine: CheckMedStore.MedicineSummary? {
        let all = treatments.medicineSummaries()
        if let medicineId { return all.first { $0.id == medicineId } }
        return all.first
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.profileMedicines),
            bubble: session.t(.planOnlyBubble)
        ) {
            if let medicine {
                Text(medicine.name)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                FactBlock(label: session.t(.manualDose), value: medicine.doseLabel)
                FactBlock(label: session.t(.manualFrequency), value: medicine.frequency)
                FactBlock(label: session.t(.manualDuration), value: medicine.duration)
                CheckMedButton(title: session.t(.deleteRecipe), style: .ghost) {
                    showDeleteRecipeConfirm = true
                }
            } else {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
            }
            Text(session.t(.planOnlyDisclaimer))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
            CheckMedButton(title: session.t(.howYouTakeIt)) { go(.howToTake) }
        }
        .confirmationDialog(
            session.t(.deleteRecipeConfirm),
            isPresented: $showDeleteRecipeConfirm,
            titleVisibility: .visible
        ) {
            Button(session.t(.deleteRecipeYes), role: .destructive) {
                guard let medicine else { return }
                treatments.deleteMedicine(id: medicine.id)
                path.reload()
                go(.addPrescription)
            }
            Button(session.t(.cancel), role: .cancel) {}
        }
    }
}

struct HowToTakeScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    private var medicine: CheckMedStore.MedicineSummary? { treatments.medicineSummaries().first }

    var body: some View {
        ScreenScaffold(
            title: session.t(.howYouTakeIt),
            philSize: 72,
            bubble: session.t(.planOnlyBubble)
        ) {
            if let medicine {
                Text(medicine.name)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(medicine.doseLabel) · \(medicine.frequency)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.t(.refillForm))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(CheckMedTheme.muted)
                    .padding(.top, 4)
                VStack(spacing: 8) {
                    ForEach(MedicineForm.allCases) { form in
                        formChoice(form, medicine: medicine)
                    }
                }
            } else {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Text(session.t(.planOnlyDisclaimer))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func formChoice(_ form: MedicineForm, medicine: CheckMedStore.MedicineSummary) -> some View {
        let selected = medicine.form == form
        return Button {
            guard medicine.form != form else { return }
            treatments.updateMedicineStock(id: medicine.id, form: form)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: form.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                    .frame(width: 28)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(formTitle(form))
                        .font(.system(.body, design: .rounded).weight(selected ? .heavy : .semibold))
                        .foregroundStyle(CheckMedTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if selected {
                        Text(formHint(form))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? CheckMedTheme.mintWash : CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selected ? CheckMedTheme.primaryShadow : CheckMedTheme.hairline,
                        lineWidth: selected ? 2.5 : 1.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
        .accessibilityLabel(formTitle(form))
        .accessibilityValue(selected ? formHint(form) : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func formHint(_ form: MedicineForm) -> String {
        switch form {
        case .tablet: session.t(.formTabletHint)
        case .capsule: session.t(.formCapsuleHint)
        case .syrup: session.t(.formSyrupHint)
        case .drops: session.t(.formDropsHint)
        case .powder: session.t(.formPowderHint)
        case .other: session.t(.formOtherHint)
        }
    }

    private func formTitle(_ form: MedicineForm) -> String {
        switch form {
        case .tablet: session.t(.formTablet)
        case .capsule: session.t(.formCapsule)
        case .syrup: session.t(.formSyrup)
        case .drops: session.t(.formDrops)
        case .powder: session.t(.formPowder)
        case .other: session.t(.formOther)
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
    @Environment(SessionStore.self) private var session

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
            Text(session.t(.takenStaysFree))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            if next != nil {
                CheckMedButton(title: session.t(.taken)) { go(.confirmMedication) }
            }
            CheckMedButton(title: session.t(.homeNextDose), style: .ghost) { go(.nextDose) }
        }
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
    @Environment(CheckMedStore.self) private var treatments

    private var snapshot: GamificationSnapshot {
        let stats = treatments.adherence()
        return Gamification.snapshot(
            nodes: path.nodes,
            currentStreak: stats.streakDays,
            longestStreak: stats.longestStreakDays,
            hasActiveTreatment: treatments.activeMedicineCount > 0,
            todayTaken: stats.todayTaken,
            todayScheduled: stats.todayTotal,
            todayMissed: stats.todayMissedCount
        )
    }

    var body: some View {
        ScreenScaffold(
            title: session.t(.doseCompletedTitle),
            philSize: 140,
            bubble: completedBubble
        ) {
            if snapshot.hasScheduledDoses {
                Text(session.t(.challengeProgress, snapshot.takenCount, snapshot.requiredCount))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
            }
            Text(session.t(.streakCurrent, snapshot.currentStreak))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            CheckMedButton(title: session.t(.keepGoing)) { go(.dailySummary) }
        }
        .onAppear {
            let owner = session.planOwnerId
            let profile = session.planProfileId
            GamificationMemory.markDoneSignature(ownerId: owner, profileId: profile, signature: snapshot.doneSignature)
            if snapshot.isComplete {
                let stamp = {
                    let comps = session.foundationCalendar.dateComponents([.year, .month, .day], from: Date())
                    return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
                }()
                GamificationMemory.markComplete(ownerId: owner, profileId: profile, dayStamp: stamp)
                if case .milestone(let day) = snapshot.coach {
                    GamificationMemory.markMilestone(ownerId: owner, profileId: profile, day: day)
                }
            }
        }
    }

    private var completedBubble: String {
        if snapshot.isComplete {
            return session.t(.philChallengeComplete)
        }
        if let name = path.nodes.last(where: { $0.status == .done })?.medicine {
            return session.t(.philNiceTook, name)
        }
        return session.t(.youDidIt)
    }
}

struct MissedDoseScreen: View {
    var go: (AppRoute) -> Void
    @Environment(TodayPathStore.self) private var path
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments

    private var unresolved: [CheckMedStore.UnresolvedDose] { treatments.unresolvedDosesForSummary() }

    var body: some View {
        ScreenScaffold(
            title: unresolved.count > 1 ? session.t(.missedYouMissedSeveral) : session.t(.missedYouMissedOne),
            bubble: session.t(.philMissedBubble)
        ) {
            MissedDoseList(doses: unresolved) {
                path.reload()
                go(.todayTreatment)
            }
            CheckMedButton(title: session.t(.homeTodaysTreatment), style: .ghost) { go(.todayTreatment) }
        }
    }
}

struct MissedDoseList: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(TodayPathStore.self) private var path
    var doses: [CheckMedStore.UnresolvedDose]
    var onChanged: () -> Void
    var onConfirmedTaken: ((UUID, Bool) -> Void)? = nil

    var body: some View {
        if doses.isEmpty {
            Text(session.t(.todayNothing))
                .font(.system(.body, design: .rounded).weight(.bold))
        } else {
            ForEach(doses) { dose in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(dose.medicine) · \(dose.doseLabel)")
                        .font(.system(.body, design: .rounded).weight(.heavy))
                    Text(dose.time)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                    HStack {
                        CheckMedButton(title: session.t(.missedTookItLater)) {
                            let wasMissedLike = dose.status.isMissedLike
                            let revisionBefore = treatments.revision
                            treatments.applyDoseAction(id: dose.id, action: .confirmTaken)
                            MissedDoseAcknowledgement.acknowledge(dose.id)
                            ReminderScheduler.shared.handleTakenSideEffects(logId: dose.id)
                            let succeeded = treatments.revision != revisionBefore
                            onChanged()
                            if succeeded {
                                path.persistFeelingRequest(logId: dose.id, medicine: dose.medicine)
                                onConfirmedTaken?(dose.id, wasMissedLike)
                            }
                        }
                        CheckMedButton(title: session.t(.missedDidNotTake), style: .secondary) {
                            treatments.applyDoseAction(id: dose.id, action: .didNotTake)
                            MissedDoseAcknowledgement.acknowledge(dose.id)
                            ReminderScheduler.shared.reschedule()
                            onChanged()
                        }
                    }
                }
                .padding(12)
                .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        Text(session.t(.missedDoseDisclaimer))
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.safety)
        Text(session.t(.missedNeverDouble))
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.safety)
    }
}

struct ReminderSettingsScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(EntitlementStore.self) private var entitlements
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
            if !entitlements.canUseVoiceReading {
                Text(session.t(.voiceLockedHint))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            CheckMedButton(title: session.t(.prefsTitle), style: .secondary) { go(.notificationPrefs) }
        }
        .onAppear {
            drafts = treatments.reminderDrafts().filter { $0.kind == .dose }
        }
    }
}

// MARK: - 07 Progress (32–35)

struct NoTreatmentInProgressScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            PhilView(size: 148, mood: .idle, smiling: true)
                .padding(.bottom, 20)
            Text(session.t(.noTreatmentInProgressHeadline))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(CheckMedTheme.ink)
            Text(session.t(.noTreatmentInProgressBody))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Spacer(minLength: 24)
            VStack(spacing: 12) {
                CheckMedButton(title: session.t(.scanAddTitle)) {
                    go(.addPrescription)
                }
                CheckMedButton(title: session.t(.todayBackHome), style: .secondary) {
                    session.showHomeTab()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.progressTitle))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.t(.noTreatmentInProgressHeadline))
    }
}

struct ProgressDashboardScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments

    private var stats: AdherenceSnapshot { treatments.adherence() }
    private var hasUpcomingScheduledDose: Bool {
        treatments.todayNodes().contains { $0.status == .current || $0.status == .locked }
    }
    private var weekFraction: CGFloat {
        guard let percent = stats.weekPercent else { return 0 }
        return CGFloat(percent) / 100
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                philBanner
                weekCard
                if treatments.activeMedicineCount > 0 {
                    JourneyGamificationCard(
                        snapshot: Gamification.snapshot(
                            nodes: treatments.todayNodes(),
                            currentStreak: stats.streakDays,
                            longestStreak: stats.longestStreakDays,
                            hasActiveTreatment: true,
                            todayTaken: stats.todayTaken,
                            todayScheduled: stats.todayTotal,
                            todayMissed: stats.todayMissedCount
                        ),
                        history: treatments.dayStatuses()
                    )
                }
                quickActions
                backHome
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.progressHeadline))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CheckMed")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.muted)
                Text(session.t(.progressHeadline))
                    .font(.system(.title, design: .rounded).weight(.black))
                Text(session.t(.progressSubhead))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Spacer()
            Button { go(.settings) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(CheckMedTheme.surface, in: Circle())
                    .overlay(Circle().stroke(CheckMedTheme.hairline, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.profileSettings))
        }
    }

    private var philBanner: some View {
        ZStack {
            LinearGradient(
                colors: [CheckMedTheme.mintWash, CheckMedTheme.blueWash],
                startPoint: .leading,
                endPoint: .trailing
            )
            Circle()
                .fill(CheckMedTheme.primary.opacity(0.10))
                .frame(width: 170, height: 170)
                .offset(x: -95, y: 18)
            HStack(alignment: .bottom, spacing: 0) {
                PhilDoctor2DImage(size: 146)
                    .offset(y: 11)
                Text(session.t(.progressPhilBubble))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckMedTheme.surface.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: CheckMedTheme.navy.opacity(0.08), radius: 12, y: 5)
                    .padding(.trailing, 10)
                    .padding(.bottom, 12)
            }
        }
        .frame(minHeight: 178)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.t(.progressWeekTitle))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    Text(session.t(.progressKeepGoing))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("🔥")
                    Text("\(stats.streakDays) \(session.t(.homeStreak))")
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(CheckMedTheme.belly, in: Capsule())
            }
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(CheckMedTheme.hairline, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: weekFraction)
                        .stroke(CheckMedTheme.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(stats.weekPercent ?? 0)%")
                        .font(.system(.title2, design: .rounded).weight(.black))
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.t(.progressDosesTaken, stats.weekTaken, stats.weekPlanned))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    HStack(spacing: 6) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(hasUpcomingScheduledDose ? session.t(.progressNextSoon) : session.t(.todayNothing))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                    }
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CheckMedTheme.belly, in: Capsule())
                }
                Spacer(minLength: 0)
                Button { go(.treatmentOverview) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "pills.fill")
                            .foregroundStyle(CheckMedTheme.primaryShadow)
                        Text("\(stats.treatmentCount)")
                            .font(.system(.title3, design: .rounded).weight(.black))
                        Text(session.t(.progressTreatmentsLabel))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.center)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    .padding(10)
                    .frame(width: 88)
                    .background(CheckMedTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
        .shadow(color: CheckMedTheme.navy.opacity(0.06), radius: 14, y: 6)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.progressQuickActions))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                actionCard(
                    title: session.t(.progressCalendar),
                    hint: session.t(.progressCalendarHint),
                    icon: "calendar",
                    tint: Color(hex: 0x5FA86B)
                ) { go(.adherence) }
                actionCard(
                    title: session.t(.progressHistory),
                    hint: session.t(.progressHistoryHint),
                    icon: "clock.fill",
                    tint: CheckMedTheme.flowDot
                ) { go(.treatmentHistory) }
                actionCard(
                    title: session.t(.journeyTreeTitle),
                    hint: session.t(.progressJourneyHint),
                    icon: "chart.line.uptrend.xyaxis",
                    tint: Color(hex: 0x9B7ED9)
                ) { go(.journeyTree) }
                actionCard(
                    title: session.t(.reportHeadline),
                    hint: session.t(.reportProgressHint),
                    icon: "doc.richtext",
                    tint: CheckMedTheme.primaryShadow
                ) { go(.medicineReport) }
                actionCard(
                    title: session.t(.refillHeadline),
                    hint: session.t(.refillTipBodyGeneric),
                    icon: "battery.75percent",
                    tint: CheckMedTheme.current
                ) { go(.refillStock) }
            }
            Button {
                go(.pharmacySearch())
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CheckMedTheme.onPrimary)
                        .frame(width: 40, height: 40)
                        .background(CheckMedTheme.primaryShadow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.t(.pharmacyTitle))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                        Text(session.t(.pharmacyProgressHint))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                    Text(session.t(.paywallSuper))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.superAccent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func actionCard(title: String, hint: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(hint)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(tint, in: Circle())
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [CheckMedTheme.surface, tint.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
            )
            .shadow(color: CheckMedTheme.navy.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var backHome: some View {
        Button {
            session.showHomeTab()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.t(.backToDashboard))
                        .font(.system(.body, design: .rounded).weight(.heavy))
                    Text(session.t(.progressBackHint))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(CheckMedTheme.onPrimary)
            .padding(16)
            .background(CheckMedTheme.primary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AdherenceScreen: View {
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session

    private var cells: [(day: Int, kind: String)] { treatments.dayStatuses() }
    private var stats: AdherenceSnapshot { treatments.adherence() }

    var body: some View {
        ScreenScaffold(title: session.t(.progressCalendar)) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    Text("\(cell.day)")
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .frame(width: 36, height: 36)
                        .background(cellColor(cell.kind), in: Circle())
                        .foregroundStyle(cell.kind == "soon" ? CheckMedTheme.muted : CheckMedTheme.ink)
                }
            }
            if stats.hasHistory {
                Text("\(stats.takenCount)/\(stats.plannedCount) \(session.t(.progressDosesLabel))")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                Text(session.t(.adherenceTakenLate, stats.takenLateCount))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                Text(session.t(.adherenceMissedCount, stats.missedCount))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                if let percent = stats.percent {
                    Text("\(percent)%")
                        .font(.system(.title2, design: .rounded).weight(.black))
                }
            }
            Text(session.t(.adherenceRecordNote))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
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

    private struct TreatmentGroup: Identifiable {
        var id: UUID
        var medicines: [CheckMedStore.MedicineSummary]
        var startDate: Date?
        var endDate: Date?
        var isCurrent: Bool
        var isPast: Bool
    }

    private struct HistorySnapshot {
        var groups: [TreatmentGroup]
        var currentGroups: [TreatmentGroup]
        var historyGroups: [TreatmentGroup]
    }

    var body: some View {
        let snapshot = historySnapshot()
        ScreenScaffold(title: session.t(.progressHistory), bubble: session.t(.progressEmptyBody)) {
            if snapshot.groups.isEmpty {
                Text(session.t(.todayNothing))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                if !snapshot.currentGroups.isEmpty {
                    sectionLabel(session.t(.currentTreatmentHeadline))
                    ForEach(snapshot.currentGroups) { group in
                        treatmentGroupBlock(group)
                    }
                }
                if !snapshot.historyGroups.isEmpty {
                    sectionLabel(session.t(.treatmentHistorySection))
                    ForEach(snapshot.historyGroups) { group in
                        treatmentGroupBlock(group)
                    }
                }
            }
            CheckMedButton(title: session.t(.homeScan), style: .secondary) { go(.addPrescription) }
        }
    }

    /// One `reportMedicineSummaries()` and one `journeyReports()` per body evaluation.
    private func historySnapshot() -> HistorySnapshot {
        let summaries = treatments.reportMedicineSummaries()
        let reportsById = Dictionary(
            uniqueKeysWithValues: treatments.journeyReports().map { ($0.treatmentId, $0) }
        )
        var order: [UUID] = []
        var byId: [UUID: [CheckMedStore.MedicineSummary]] = [:]
        for summary in summaries {
            if byId[summary.treatmentId] == nil {
                order.append(summary.treatmentId)
            }
            byId[summary.treatmentId, default: []].append(summary)
        }
        let groups: [TreatmentGroup] = order.compactMap { treatmentId in
            guard let medicines = byId[treatmentId], !medicines.isEmpty else { return nil }
            let report = reportsById[treatmentId]
            let kind = report.map {
                treatments.journeyKind(status: $0.treatmentStatus, startDate: $0.startDate, endDate: $0.endDate)
            } ?? nil
            let isCurrent: Bool
            let isPast: Bool
            if let kind {
                isCurrent = kind == .current
                isPast = kind == .past
            } else {
                isCurrent = treatments.isCurrentOnJourneyHistory(treatmentId: treatmentId)
                isPast = treatments.isPastOnJourneyHistory(treatmentId: treatmentId)
            }
            return TreatmentGroup(
                id: treatmentId,
                medicines: medicines,
                startDate: report?.startDate,
                endDate: report?.endDate,
                isCurrent: isCurrent,
                isPast: isPast
            )
        }
        return HistorySnapshot(
            groups: groups,
            currentGroups: groups.filter(\.isCurrent),
            historyGroups: groups.filter(\.isPast)
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .foregroundStyle(CheckMedTheme.muted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func treatmentGroupBlock(_ group: TreatmentGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.medicines.map(\.name).joined(separator: " · "))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            Text(
                group.isCurrent
                    ? session.t(.treatmentStatusActive)
                    : session.t(.treatmentStatusCompleted)
            )
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .foregroundStyle(CheckMedTheme.muted)
            if let dates = dateLine(for: group) {
                Text(dates)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            ForEach(group.medicines) { med in
                CardBlock(kicker: med.frequency, title: "\(med.name) · \(med.doseLabel)")
            }
        }
    }

    private func dateLine(for group: TreatmentGroup) -> String? {
        guard let startDate = group.startDate else { return nil }
        let start = formatted(startDate)
        if let end = group.endDate {
            return "\(start) – \(formatted(end))"
        }
        return "\(session.t(.progressTreatmentStarted)) · \(start)"
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = session.foundationCalendar
        formatter.locale = session.locale.foundationLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMMMy")
        return formatter.string(from: date)
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
            CheckMedButton(title: session.t(.journeyTitle), style: .secondary) { go(.journeyReport) }
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
            Toggle(session.t(.advanceHourToggle), isOn: Binding(
                get: { entitlements.canUseAdvanceReminder && ReminderPreferences.advanceHourEnabled },
                set: { value in
                    if entitlements.canUseAdvanceReminder {
                        ReminderPreferences.advanceHourEnabled = value
                        ReminderScheduler.shared.reschedule()
                    } else {
                        entitlements.presentPaywall()
                    }
                }
            ))
            .font(.system(.body, design: .rounded).weight(.bold))
            if !entitlements.canUseAdvanceReminder {
                Text(session.t(.advanceHourLocked))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Toggle(session.t(.winBackToggle), isOn: Binding(
                get: { ReminderPreferences.winBackEnabled },
                set: { value in
                    ReminderPreferences.winBackEnabled = value
                    ReminderScheduler.shared.reschedule()
                }
            ))
            .font(.system(.body, design: .rounded).weight(.bold))
            Stepper(
                "\(session.t(.prefsGraceMinutes)): \(ReminderPreferences.confirmationGraceMinutes)",
                value: Binding(
                    get: { ReminderPreferences.confirmationGraceMinutes },
                    set: {
                        ReminderPreferences.confirmationGraceMinutes = $0
                        ReminderScheduler.shared.reschedule()
                    }
                ),
                in: 10...180,
                step: 5
            )
            .font(.system(.body, design: .rounded).weight(.bold))
            Stepper(
                "\(session.t(.prefsSnoozeMinutes)): \(ReminderPreferences.snoozeMinutes)",
                value: Binding(
                    get: { ReminderPreferences.snoozeMinutes },
                    set: {
                        ReminderPreferences.snoozeMinutes = $0
                        ReminderScheduler.shared.reschedule()
                    }
                ),
                in: 5...30,
                step: 1
            )
            .font(.system(.body, design: .rounded).weight(.bold))
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            quietHours = ReminderPreferences.quietHoursEnabled
            voiceReminders = entitlements.canUseVoiceReading && ReminderPreferences.voiceRemindersEnabled
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
            // Appearance stays locked to the pastel light theme.
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
