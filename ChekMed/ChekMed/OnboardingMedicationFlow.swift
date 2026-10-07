import PhotosUI
import SwiftUI
import UIKit

enum OnboardingAddMethod {
    case photo, pdf, manual
}

/// Later-add intake only. First plan (`storedMedicineCount == 0`) always seeds a new treatment.
enum LaterAddTreatmentIntent: Equatable {
    /// Append this confirmation to the CURRENT treatment.
    case addToCurrent
    /// Complete the active plan, then seed a new TreatmentRecord for this confirmation.
    case startNewTreatment
}

enum LaterAddPersistTarget: Equatable {
    case seed
    case addToActive
    case completeThenSeed
}

enum LaterAddPersist {
    static func target(
        intent: LaterAddTreatmentIntent,
        hasCurrentTreatment: Bool
    ) -> LaterAddPersistTarget {
        guard hasCurrentTreatment else { return .seed }
        switch intent {
        case .addToCurrent: return .addToActive
        case .startNewTreatment: return .completeThenSeed
        }
    }
}

#if DEBUG
enum LaterAddPersistContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        if LaterAddPersist.target(intent: .addToCurrent, hasCurrentTreatment: false) != .seed {
            failures.append("later-add: no current treatment must seed, not add")
        }
        if LaterAddPersist.target(intent: .startNewTreatment, hasCurrentTreatment: false) != .seed {
            failures.append("later-add: no current treatment must seed even if start-new is selected")
        }
        if LaterAddPersist.target(intent: .addToCurrent, hasCurrentTreatment: true) != .addToActive {
            failures.append("later-add: add-to-current must append onto the current treatment")
        }
        if LaterAddPersist.target(intent: .startNewTreatment, hasCurrentTreatment: true) != .completeThenSeed {
            failures.append("later-add: start-new must complete then seed")
        }
        return failures
    }
}
#endif

struct OnboardingPrescriptionDraft: Equatable, Sendable {
    var medicine: String
    var dose: String
    var frequency: String
    var duration: String
    var timesPerDay: String
    var doseTimes: [String] = []
    var reason: String = ""
    var form: String = ""
    var packageAmount: String = ""
    var packageUnit: String = ""
    var doctorName: String = ""
    var doctorId: String = ""
    var hospitalName: String = ""
    var doctorNotes: String = ""
    /// Exact OCR/table span that produced this object. Required before confirm.
    var sourceText: String = ""
    var prescriptionDate: Date? = nil
    var scanDate: Date = Date()
    var treatmentStartDate: Date? = nil
    var treatmentEndDate: Date? = nil

    static let empty = OnboardingPrescriptionDraft(
        medicine: "",
        dose: "",
        frequency: "",
        duration: "",
        timesPerDay: ""
    )

    var isFilled: Bool {
        !medicine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !dose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!frequency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !timesPerDay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !duration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasMedicineName: Bool {
        !medicine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Interval text only. Times per day live in `timesPerDay`, not English “daily”.
    var scheduleFrequency: String {
        PrescriptionParser.intervalOnly(frequency)
    }

    mutating func sanitizeScheduleFields() {
        frequency = PrescriptionParser.intervalOnly(frequency)
    }

    var timesCount: Int {
        if let value = Int(timesPerDay), (1...4).contains(value) { return value }
        return max(1, min(4, doseTimes.filter { !$0.isEmpty }.count))
    }

    /// Pads or trims slot count. Never overwrites a non-empty user/OCR time.
    mutating func syncDoseTimes() {
        doseTimes = Self.paddedDoseTimes(
            existing: doseTimes,
            count: timesCount,
            frequency: frequency
        )
    }

    /// Same as `syncDoseTimes`. Kept for scan/manual call sites that used to spread from the first clock.
    mutating func suggestTimesFromFirst() {
        syncDoseTimes()
    }

    var missingRequirement: L10n.Key? {
        if medicine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .manualMissingMedicine
        }
        if dose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .manualMissingDose
        }
        if frequency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && timesPerDay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .manualMissingTimesOrFrequency
        }
        if duration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .manualMissingDates
        }
        return nil
    }

    private static func paddedDoseTimes(existing: [String], count: Int, frequency: String) -> [String] {
        let slots = max(1, min(4, count))
        var next = Array(existing.prefix(slots))
        let interval = CheckMedStore.intervalHours(from: frequency, timesCount: slots)
        let first = next.first.flatMap { $0.isEmpty ? nil : $0 } ?? "08:00"
        let suggestions = CheckMedStore.spreadTimes(from: first, count: slots, intervalHours: interval)
        while next.count < slots {
            next.append(suggestions[next.count])
        }
        for index in next.indices where next[index].isEmpty {
            next[index] = suggestions[index]
        }
        return next
    }

    var compactTimesLabel: String {
        let labels = (doseTimes.isEmpty ? CheckMedStore.defaultTimes(count: timesCount) : doseTimes)
            .map(CheckMedStore.compactHourLabel)
        return labels.joined(separator: "-")
    }
}

extension [OnboardingPrescriptionDraft] {
    /// Unique named drafts from the parser — this is the scan count (never a hardcoded N).
    var uniqueNamedMedicines: [OnboardingPrescriptionDraft] {
        dedupedDistinctMedicines()
    }

    /// name + strength + form. Not an aggressive fuzzy merge (Amoxicilina ≠ Amoxidal).
    func dedupedDistinctMedicines() -> [OnboardingPrescriptionDraft] {
        var seen = Set<String>()
        var unique: [OnboardingPrescriptionDraft] = []
        for draft in self where draft.hasMedicineName {
            let key = PrescriptionParser.distinctObjectKey(draft)
            if seen.insert(key).inserted {
                unique.append(draft)
            }
        }
        return unique
    }

    func preparedDetectedMedicines() -> [OnboardingPrescriptionDraft] {
        var named = filter(\.hasMedicineName)
        for index in named.indices { named[index].sanitizeScheduleFields() }
        return named.dedupedDistinctMedicines()
    }

    func cappedForPlan(isSuper: Bool, existingCount: Int = 0) -> [OnboardingPrescriptionDraft] {
        var seen = Set<String>()
        var unique: [OnboardingPrescriptionDraft] = []
        for draft in self {
            if draft.hasMedicineName {
                let key = PrescriptionParser.canonicalMedicineKey(draft.medicine)
                if !seen.insert(key).inserted { continue }
            }
            unique.append(draft)
        }
        let room = Swift.max(0, (isSuper ? 12 : SuperLimits.freePrescriptions) - Swift.max(0, existingCount))
        if room == 0 {
            return unique.contains(where: \.hasMedicineName) ? [] : [.empty]
        }
        var named = 0
        let limited = unique.filter { draft in
            guard draft.hasMedicineName else { return named == 0 }
            named += 1
            return named <= room
        }
        return limited.isEmpty ? [.empty] : limited
    }
}

struct OnboardingAddMedicationView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(EntitlementStore.self) private var entitlements
    var onPhoto: () -> Void
    var onChoosePhotos: () -> Void = {}
    var onPDF: () -> Void
    var onManual: () -> Void
    var onBack: () -> Void
    var showsChoosePhotos: Bool = true
    var showsTreatmentIntent: Bool = false
    var treatmentIntent: Binding<LaterAddTreatmentIntent> = .constant(.addToCurrent)

    private var medicineCount: Int { treatments.storedMedicineCount }
    private var remainingSlots: Int {
        entitlements.freeMedicineSlotsRemaining(existingCount: medicineCount)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                SetupStepHeader(title: session.t(.scanAddTitle))
                PhilLibraryImage(asset: "phil_onboarding_02_photo", size: 168)
                    .padding(.top, 4)
                Text(session.t(.scanOrganizeHint))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !entitlements.isSuper, medicineCount > 0 {
                    Text(
                        remainingSlots > 0
                            ? session.t(.confirmRemainingSlots, medicineCount, remainingSlots)
                            : session.t(.confirmFreePlanFull)
                    )
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckMedTheme.mintWash)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if showsTreatmentIntent {
                    laterAddTreatmentIntentPicker
                }
                VStack(spacing: 12) {
                    CheckMedButton(title: session.t(.scanTakePhoto), action: onPhoto)
                    if showsChoosePhotos {
                        CheckMedButton(title: session.t(.scanChoosePhotos), style: .secondary, action: onChoosePhotos)
                            .keyboardShortcut("p", modifiers: [.command])
                    }
                    CheckMedButton(title: session.t(.scanUploadPDF), style: .secondary, action: onPDF)
                    CheckMedButton(title: session.t(.scanSetManually), style: .secondary, action: onManual)
                    CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
                }
                .padding(.top, 6)
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }

    private var laterAddTreatmentIntentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            intentRow(
                title: session.t(.laterAddToCurrentTreatment),
                hint: session.t(.laterAddToCurrentTreatmentHint),
                selected: treatmentIntent.wrappedValue == .addToCurrent
            ) {
                treatmentIntent.wrappedValue = .addToCurrent
            }
            intentRow(
                title: session.t(.laterStartNewTreatment),
                hint: session.t(.laterStartNewTreatmentHint),
                selected: treatmentIntent.wrappedValue == .startNewTreatment
            ) {
                treatmentIntent.wrappedValue = .startNewTreatment
            }
        }
    }

    private func intentRow(
        title: String,
        hint: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(selected ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    Text(hint)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? CheckMedTheme.primary.opacity(0.35) : CheckMedTheme.hairline, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct OnboardingCameraView: View {
    @Environment(SessionStore.self) private var session
    var onCaptured: (Data) -> Void
    var onBack: () -> Void

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var photoItem: PhotosPickerItem?

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        VStack(spacing: 16) {
            SetupStepHeader(title: session.t(.scanCameraTitle))
            PhilView(size: 72, smiling: true)
            Text(session.t(.scanCameraBubble))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            Text(session.t(.scanKeepFrame))
                .font(.system(.title3, design: .rounded).weight(.heavy))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.ink, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                .frame(height: 220)
                .overlay {
                    Text(cameraAvailable ? session.t(.scanViewfinder) : session.t(.scanCameraUnavailable))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            Spacer(minLength: 8)
            if cameraAvailable {
                CheckMedButton(title: session.t(.scanCapture)) { showCamera = true }
            }
            CheckMedButton(
                title: session.t(.scanChoosePhotos),
                style: cameraAvailable ? .secondary : .primary
            ) {
                showLibrary = true
            }
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { data in
                showCamera = false
                if let data {
                    onCaptured(data)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoItem = nil
                    onCaptured(PrescriptionReader.downsampledJPEG(from: data))
                }
            }
        }
    }
}

private enum ManualFieldInput {
    case doseLabel
    case frequency
    case packageAmount
    case doctorName
    case doctorId
    case freeText

    var keyboard: UIKeyboardType {
        switch self {
        case .packageAmount: .decimalPad
        default: .default
        }
    }

    func binding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = sanitized($0) }
        )
    }

    func sanitized(_ raw: String) -> String {
        switch self {
        case .freeText:
            return raw
        case .packageAmount:
            return Self.decimalAmount(raw)
        case .doseLabel:
            return raw.filter { $0.isLetter || $0.isNumber || " .,/-%µμ".contains($0) }
        case .frequency:
            return raw.filter { $0.isLetter || $0.isNumber || " .,/-:x×".contains($0) }
        case .doctorName:
            return raw.filter { $0.isLetter || $0 == " " || ".'’-".contains($0) }
        case .doctorId:
            return raw.filter { $0.isLetter || $0.isNumber || " -./".contains($0) }
        }
    }

    private static func decimalAmount(_ raw: String) -> String {
        var sawSeparator = false
        var out = ""
        for character in raw {
            if character.isNumber {
                out.append(character)
                continue
            }
            if character == "." || character == "," {
                guard !sawSeparator else { continue }
                sawSeparator = true
                out.append(character)
            }
        }
        return out
    }
}

private struct ManualRequirementNotice: View {
    @Environment(SessionStore.self) private var session
    let key: L10n.Key

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CheckMedTheme.beak)
                .accessibilityHidden(true)
            Text(session.t(key))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.sunshineWash)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingManualEntryView: View {
    @Environment(SessionStore.self) private var session
    @Binding var draft: OnboardingPrescriptionDraft
    var onContinue: () -> Void
    var onBack: () -> Void

    @FocusState private var focusedManualField: ManualEntryFocus?
    @State private var medicineFocused = false

    private enum ManualEntryFocus: Hashable {
        case dose, frequency, reason, doctor, doctorId, hospital, notes, package
    }

    private var keyboardOpen: Bool { medicineFocused || focusedManualField != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                MedicineNameField(
                    title: session.t(.manualMedicine),
                    text: $draft.medicine,
                    highlightIncomplete: draft.missingRequirement == .manualMissingMedicine,
                    reportsFocus: $medicineFocused
                )
                field(
                    session.t(.manualDose),
                    text: $draft.dose,
                    highlightIncomplete: draft.missingRequirement == .manualMissingDose,
                    input: .doseLabel,
                    focus: .dose
                )
                timesPerDayRow
                field(
                    session.t(.manualFrequency),
                    text: $draft.frequency,
                    highlightIncomplete: draft.missingRequirement == .manualMissingTimesOrFrequency,
                    input: .frequency,
                    focus: .frequency
                )
                DoseTimesField(
                    timesPerDay: $draft.timesPerDay,
                    frequency: $draft.frequency,
                    doseTimes: $draft.doseTimes
                )
                DurationRangeField(
                    duration: $draft.duration,
                    highlightIncomplete: draft.missingRequirement == .manualMissingDates
                )
                optionalSectionLabel
                field(session.t(.medicineReason), text: $draft.reason, optional: true, input: .freeText, focus: .reason)
                field(session.t(.reportDoctor), text: $draft.doctorName, optional: true, input: .doctorName, focus: .doctor)
                field(session.t(.reportDoctorId), text: $draft.doctorId, optional: true, input: .doctorId, focus: .doctorId)
                field(session.t(.reportHospital), text: $draft.hospitalName, optional: true, input: .freeText, focus: .hospital)
                field(session.t(.reportDoctorNotes), text: $draft.doctorNotes, optional: true, input: .freeText, focus: .notes)
                field(
                    session.t(.refillPackageAmount),
                    text: $draft.packageAmount,
                    optional: true,
                    input: .packageAmount,
                    focus: .package
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if let missing = draft.missingRequirement, !keyboardOpen {
                    ManualRequirementNotice(key: missing)
                }
                CheckMedButton(title: session.t(.continueButton), action: onContinue)
                    .disabled(!draft.isFilled)
                    .accessibilityHint(draft.missingRequirement.map { session.t($0) } ?? "")
                CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(CheckMedTheme.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(CheckMedTheme.hairline)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }

    private var header: some View {
        VStack(spacing: 8) {
            SetupStepHeader(title: session.t(.scanSetManually))
            PhilView(size: 64, smiling: true)
            Text(session.t(.scanOrganizeHint))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var optionalSectionLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(CheckMedTheme.hairline)
                .frame(height: 1)
                .padding(.top, 4)
            Text(session.t(.optionalField))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        optional: Bool = false,
        highlightIncomplete: Bool = false,
        input: ManualFieldInput = .freeText,
        focus: ManualEntryFocus? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(highlightIncomplete ? CheckMedTheme.beak : CheckMedTheme.muted)
                if optional {
                    Text(session.t(.optionalField))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            }
            TextField(title, text: input.binding(text))
                .keyboardType(input.keyboard)
                .focused($focusedManualField, equals: focus)
                .padding(12)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            highlightIncomplete ? CheckMedTheme.beak.opacity(0.7) : CheckMedTheme.hairline,
                            lineWidth: highlightIncomplete ? 2 : 1.5
                        )
                )
        }
    }

    private var timesPerDayRow: some View {
        TimesPerDayPicker(
            title: session.t(.manualTimesPerDay),
            value: $draft.timesPerDay,
            highlightIncomplete: draft.missingRequirement == .manualMissingTimesOrFrequency
        )
    }
}

struct OnboardingAnalysingView: View {
    @Environment(SessionStore.self) private var session
    var isShort: Bool
    var work: (() async -> Void)? = nil
    var onFinished: () -> Void
    var importToken: Int = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            PhilView(size: 168, mood: .celebrate, smiling: true)
            Text(session.t(.scanAnalysingTitle))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            Text(isShort ? session.t(.scanAnalysingShort) : session.t(.scanAnalysingBody))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            ProgressView()
                .tint(CheckMedTheme.primaryShadow)
                .scaleEffect(1.2)
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .task(id: importToken) {
            let started = Date()
            if let work {
                await work()
            }
            let minimum = isShort ? 0.7 : 2.0
            let remaining = minimum - Date().timeIntervalSince(started)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
        .accessibilityLabel(session.t(.scanAnalysingTitle))
    }
}

struct OnboardingConfirmView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Binding var drafts: [OnboardingPrescriptionDraft]
    var isManual: Bool
    var existingMedicineCount: Int = 0
    var source: PendingPrescriptionImport = .none
    var onConfirm: () -> Void
    var onBack: () -> Void

    @State private var page = 0
    @FocusState private var focusedField: Field?
    @State private var medicineFocused = false

    private enum Field: Hashable {
        case medicine, dose, frequency, duration, reason
        case doctor, doctorId, hospital, doctorNotes, packageAmount
    }

    private var safePage: Int {
        Swift.min(Swift.max(0, page), Swift.max(0, drafts.count - 1))
    }

    private var isOnLastMedicine: Bool {
        drafts.isEmpty || safePage >= drafts.count - 1
    }

    private var canAdvance: Bool {
        guard drafts.indices.contains(safePage) else { return false }
        return drafts[safePage].isFilled
    }

    private var firstIncompleteIndex: Int? {
        drafts.firstIndex { $0.hasMedicineName && !$0.isFilled }
    }

    private var keyboardOpen: Bool { focusedField != nil || medicineFocused }
    private var freeMedicineCap: Int { SuperLimits.freePrescriptions }
    private var remainingSlots: Int {
        entitlements.freeMedicineSlotsRemaining(existingCount: existingMedicineCount)
    }
    private var namedDraftCount: Int { drafts.filter(\.hasMedicineName).count }

    private var freePlanBanner: String? {
        guard !entitlements.isSuper else { return nil }
        // Fits remaining Free slots → Confirm as today, no upgrade copy.
        if namedDraftCount <= remainingSlots { return nil }
        if existingMedicineCount >= freeMedicineCap {
            return session.t(.confirmFreePlanFull)
        }
        if existingMedicineCount > 0, remainingSlots > 0 {
            return session.t(.confirmRemainingSlots, existingMedicineCount, remainingSlots)
        }
        return session.t(.confirmFreePlanLimit)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)
            pager
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if source.showsOriginalPreview {
                            ConfirmOriginalPrescriptionCard(source: source)
                        }
                        if !isManual, drafts.allSatisfy({ !$0.hasMedicineName }) {
                            Text(session.t(.scanOCREmptyHint))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        if let freePlanBanner {
                            Text(freePlanBanner)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.ink)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CheckMedTheme.primary.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        medicineFields(index: min(page, max(0, drafts.count - 1)))
                            .id("fields")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, field in
                    guard field != nil else { return }
                    withAnimation {
                        proxy.scrollTo("fields", anchor: .top)
                    }
                }
            }
            VStack(spacing: 6) {
                if let missing = drafts.indices.contains(safePage) ? drafts[safePage].missingRequirement : nil,
                   !keyboardOpen {
                    ManualRequirementNotice(key: missing)
                }
                CheckMedButton(title: session.t(.continueButton), action: {
                    focusedField = nil
                    advanceOrConfirm()
                })
                .disabled(!canAdvance)
                .accessibilityHint(
                    (drafts.indices.contains(safePage) ? drafts[safePage].missingRequirement : nil)
                        .map { session.t($0) } ?? ""
                )
                CheckMedButton(title: session.t(.back), style: .ghost, action: stepBack)
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .background(CheckMedTheme.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(session.t(.done)) { focusedField = nil }
            }
        }
        .onChange(of: drafts.count) { _, count in
            if page >= count { page = max(0, count - 1) }
        }
        .onAppear { sanitizeAndCapDrafts() }
        .onChange(of: entitlements.isSuper) { _, _ in
            sanitizeAndCapDrafts()
        }
    }

    private var header: some View {
        ZStack {
            Text(isManual ? session.t(.confirmManualHeadline) : session.t(.confirmEditHeadline))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 52)
            HStack {
                PhilThinkingImage(size: 40)
                    .accessibilityHidden(true)
                Spacer()
                if keyboardOpen {
                    Button(session.t(.done)) { focusedField = nil }
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                        .frame(minWidth: 44, minHeight: 44)
                } else if currentDraft.hasMedicineName {
                    Button(action: removeCurrentMedicine) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CheckMedTheme.danger)
                            .frame(width: 40, height: 40)
                            .background(CheckMedTheme.surface, in: Circle())
                            .overlay(Circle().stroke(CheckMedTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.t(.confirmRemoveMedicine))
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var currentDraft: OnboardingPrescriptionDraft {
        guard drafts.indices.contains(safePage) else { return .empty }
        return drafts[safePage]
    }

    private func advanceOrConfirm() {
        focusedField = nil
        guard canAdvance else { return }
        drafts[safePage].syncDoseTimes()
        if !isOnLastMedicine {
            withAnimation(.easeInOut(duration: 0.25)) {
                page = safePage + 1
            }
            return
        }
        if let incomplete = firstIncompleteIndex, incomplete != safePage {
            withAnimation(.easeInOut(duration: 0.25)) {
                page = incomplete
            }
            return
        }
        guard drafts.contains(where: \.isFilled) else { return }
        for index in drafts.indices { drafts[index].syncDoseTimes() }
        onConfirm()
    }

    private func stepBack() {
        focusedField = nil
        if safePage > 0 {
            withAnimation(.easeInOut(duration: 0.25)) {
                page = safePage - 1
            }
        } else {
            onBack()
        }
    }

    private var pager: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(drafts.indices, id: \.self) { index in
                        Button {
                            focusedField = nil
                            withAnimation(.easeInOut(duration: 0.2)) { page = index }
                        } label: {
                            pagerCircle(
                                selected: index == page,
                                title: "\(index + 1)"
                            )
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel(session.t(.confirmMedicineOf, index + 1, drafts.count))
                    }
                    Button(action: addMedicineSlot) {
                        pagerCircle(selected: false, systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel(session.t(.confirmAddMedicine))
                }
            }
            if drafts.count > 1 {
                Text("\(page + 1)/\(drafts.count)")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.muted)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func pagerCircle(selected: Bool, title: String? = nil, systemImage: String? = nil) -> some View {
        ZStack {
            Circle()
                .fill(selected ? CheckMedTheme.primary : CheckMedTheme.surface)
            Circle()
                .strokeBorder(
                    selected ? CheckMedTheme.primaryShadow : CheckMedTheme.hairline,
                    lineWidth: 1.5
                )
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(CheckMedTheme.ink)
            } else if let title {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(selected ? CheckMedTheme.onPrimary : CheckMedTheme.ink)
            }
        }
        .frame(width: 36, height: 36)
        .contentShape(Circle())
    }

    private func addMedicineSlot() {
        focusedField = nil
        let usedInBatch = namedDraftCount
        if !entitlements.isSuper, usedInBatch >= remainingSlots {
            entitlements.presentPaywall()
            return
        }
        if entitlements.isSuper, drafts.count >= 12 {
            return
        }
        drafts.append(.empty)
        page = drafts.count - 1
    }

    private func sanitizeAndCapDrafts() {
        var next = drafts
        for index in next.indices {
            next[index].sanitizeScheduleFields()
        }
        next = next.cappedForPlan(isSuper: entitlements.isSuper, existingCount: existingMedicineCount)
        if next.isEmpty {
            next = [.empty]
        }
        if next != drafts {
            drafts = next
            page = min(page, max(0, drafts.count - 1))
        }
    }

    private func medicineFields(index: Int) -> some View {
        let missing = drafts.indices.contains(index) ? drafts[index].missingRequirement : nil
        return VStack(alignment: .leading, spacing: 18) {
            MedicineNameField(
                title: session.t(.manualMedicine),
                text: binding(index, \.medicine),
                embedded: true,
                highlightIncomplete: missing == .manualMissingMedicine,
                reportsFocus: $medicineFocused
            )
            confirmDivider
            compactField(
                session.t(.manualDose),
                text: binding(index, \.dose),
                field: .dose,
                highlightIncomplete: missing == .manualMissingDose,
                input: .doseLabel
            )
            confirmDivider
            TimesPerDayPicker(
                title: session.t(.manualTimesPerDay),
                value: binding(index, \.timesPerDay),
                highlightIncomplete: missing == .manualMissingTimesOrFrequency
            )
            confirmDivider
            compactField(
                session.t(.manualFrequency),
                text: binding(index, \.frequency),
                field: .frequency,
                highlightIncomplete: missing == .manualMissingTimesOrFrequency,
                input: .frequency
            )
            confirmDivider
            DoseTimesField(
                timesPerDay: binding(index, \.timesPerDay),
                frequency: binding(index, \.frequency),
                doseTimes: doseTimesBinding(index)
            )
            confirmDivider
            DurationRangeField(
                duration: binding(index, \.duration),
                embedded: true,
                highlightIncomplete: missing == .manualMissingDates
            )
            confirmDivider
            compactField(session.t(.medicineReason), text: binding(index, \.reason), field: .reason, optional: true, input: .freeText)
            confirmDivider
            compactField(session.t(.reportDoctor), text: binding(index, \.doctorName), field: .doctor, optional: true, input: .doctorName)
            confirmDivider
            compactField(session.t(.reportDoctorId), text: binding(index, \.doctorId), field: .doctorId, optional: true, input: .doctorId)
            confirmDivider
            compactField(session.t(.reportHospital), text: binding(index, \.hospitalName), field: .hospital, optional: true, input: .freeText)
            confirmDivider
            compactField(session.t(.reportDoctorNotes), text: binding(index, \.doctorNotes), field: .doctorNotes, optional: true, input: .freeText)
            confirmDivider
            compactField(
                session.t(.refillPackageAmount),
                text: binding(index, \.packageAmount),
                field: .packageAmount,
                optional: true,
                input: .packageAmount
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private var confirmDivider: some View {
        Rectangle()
            .fill(CheckMedTheme.hairline)
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private func removeCurrentMedicine() {
        focusedField = nil
        guard drafts.indices.contains(page) else { return }
        drafts.remove(at: page)
        if drafts.isEmpty {
            drafts = [.empty]
            page = 0
        } else {
            page = min(page, drafts.count - 1)
        }
    }

    private func binding(_ index: Int, _ keyPath: WritableKeyPath<OnboardingPrescriptionDraft, String>) -> Binding<String> {
        Binding(
            get: {
                guard drafts.indices.contains(index) else { return "" }
                return drafts[index][keyPath: keyPath]
            },
            set: { value in
                guard drafts.indices.contains(index) else { return }
                drafts[index][keyPath: keyPath] = value
            }
        )
    }

    private func doseTimesBinding(_ index: Int) -> Binding<[String]> {
        Binding(
            get: {
                guard drafts.indices.contains(index) else { return [] }
                return drafts[index].doseTimes
            },
            set: { value in
                guard drafts.indices.contains(index) else { return }
                drafts[index].doseTimes = value
            }
        )
    }

    private func compactField(
        _ title: String,
        text: Binding<String>,
        field: Field,
        optional: Bool = false,
        highlightIncomplete: Bool = false,
        input: ManualFieldInput = .freeText
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(highlightIncomplete ? CheckMedTheme.beak : CheckMedTheme.muted)
                if optional {
                    Text(session.t(.optionalField))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            }
            TextField(title, text: input.binding(text))
                .keyboardType(input.keyboard)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .padding(.vertical, 4)
                .focused($focusedField, equals: field)
        }
    }
}

struct DurationRangeField: View {
    @Environment(SessionStore.self) private var session
    @Binding var duration: String
    var embedded: Bool = false
    var highlightIncomplete: Bool = false

    @State private var showPicker = false
    @State private var pickingEnd = false
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()

    private var calendar: Calendar { session.foundationCalendar }

    private var savedBounds: (start: Date, end: Date)? {
        PlanDuration.bounds(from: duration, calendar: calendar)
    }

    private var savedDayCount: Int? {
        guard let bounds = savedBounds else { return nil }
        let s = calendar.startOfDay(for: bounds.start)
        let e = calendar.startOfDay(for: bounds.end)
        let diff = calendar.dateComponents([.day], from: s, to: e).day ?? 0
        return max(1, diff + 1)
    }

    private var dayCount: Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: max(end, start))
        let diff = calendar.dateComponents([.day], from: s, to: e).day ?? 0
        return max(1, diff + 1)
    }

    private var dayCountText: String {
        session.t(dayCount == 1 ? .durationDaysOne : .durationDaysFormat, dayCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.manualDuration))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            dateChoiceRow(
                title: session.t(.durationStart),
                date: savedBounds?.start,
                opensEnd: false
            )
            dateChoiceRow(
                title: session.t(.durationEnd),
                date: savedBounds?.end,
                opensEnd: true
            )
            if let count = savedDayCount {
                Text(session.t(count == 1 ? .durationDaysOne : .durationDaysFormat, count))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .accessibilityLabel(session.t(count == 1 ? .durationDaysOne : .durationDaysFormat, count))
            } else {
                Text(session.t(.manualMissingDates))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(highlightIncomplete ? CheckMedTheme.beak : CheckMedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(session.t(.durationPastStartHint))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .sheet(isPresented: $showPicker, onDismiss: commitDays) {
            NavigationStack {
                DurationRangeCalendar(
                    start: $start,
                    end: $end,
                    pickingEnd: $pickingEnd,
                    calendar: calendar,
                    locale: session.locale.foundationLocale,
                    startTitle: session.t(.durationStart),
                    endTitle: session.t(.durationEnd),
                    selectedTitle: session.t(.durationSelected),
                    dayCountText: dayCountText
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .navigationTitle(session.t(.manualDuration))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(session.t(.done)) {
                            commitDays()
                            showPicker = false
                        }
                        .font(.system(.body, design: .rounded).weight(.heavy))
                    }
                }
            }
            .background(CheckMedTheme.background)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .onAppear { seedFromDuration() }
        }
        .onChange(of: start) { _, _ in
            if end < start { end = start }
        }
    }

    private func dateChoiceRow(title: String, date: Date?, opensEnd: Bool) -> some View {
        Button {
            seedFromDuration()
            pickingEnd = opensEnd
            showPicker = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(highlightIncomplete ? CheckMedTheme.beak : CheckMedTheme.primaryShadow)
                    Text(date.map(dateLabel) ?? session.t(.durationPickDates))
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(date == nil ? CheckMedTheme.muted : CheckMedTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(.horizontal, embedded ? 0 : 14)
            .padding(.vertical, embedded ? 8 : 14)
            .frame(minHeight: 64)
            .background(embedded ? Color.clear : CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        highlightIncomplete ? CheckMedTheme.beak.opacity(0.7) : (embedded ? Color.clear : CheckMedTheme.hairline),
                        lineWidth: highlightIncomplete ? 2 : 1.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(date.map(dateLabel) ?? session.t(.durationPickDates))
        .accessibilityHint(session.t(.durationPickDates))
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = session.locale.foundationLocale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    private func seedFromDuration() {
        if let bounds = PlanDuration.bounds(from: duration, calendar: calendar) {
            start = bounds.start
            end = bounds.end
            return
        }
        let days = duration.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.last
        start = Date()
        if let days, days > 0 {
            end = calendar.date(byAdding: .day, value: days - 1, to: calendar.startOfDay(for: start)) ?? start
        }
    }

    private func commitDays() {
        duration = PlanDuration.encode(start: start, end: end, calendar: calendar)
    }
}

private struct DurationDayItem: Identifiable, Hashable {
    let date: Date
    let inMonth: Bool
    var id: Date { date }
}

struct DurationRangeCalendar: View {
    @Binding var start: Date
    @Binding var end: Date
    @Binding var pickingEnd: Bool
    let calendar: Calendar
    let locale: Locale
    let startTitle: String
    let endTitle: String
    let selectedTitle: String
    let dayCountText: String

    @State private var visibleMonth = Date()

    private var localizedCalendar: Calendar {
        var cal = calendar
        cal.locale = locale
        return cal
    }

    private var rangeStart: Date { localizedCalendar.startOfDay(for: start) }
    private var rangeEnd: Date { localizedCalendar.startOfDay(for: max(end, start)) }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth).capitalized(with: locale)
    }

    private var weekdaySymbols: [String] {
        let symbols = localizedCalendar.veryShortStandaloneWeekdaySymbols
        let first = localizedCalendar.firstWeekday - 1
        guard symbols.indices.contains(first) else { return symbols }
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var days: [DurationDayItem] {
        guard let monthStart = localizedCalendar.date(from: localizedCalendar.dateComponents([.year, .month], from: visibleMonth)) else {
            return []
        }
        let firstWeekday = localizedCalendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - localizedCalendar.firstWeekday + 7) % 7
        let daysInMonth = localizedCalendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        var items: [DurationDayItem] = []
        if leading > 0, let previous = localizedCalendar.date(byAdding: .day, value: -leading, to: monthStart) {
            for offset in 0..<leading {
                if let date = localizedCalendar.date(byAdding: .day, value: offset, to: previous) {
                    items.append(DurationDayItem(date: localizedCalendar.startOfDay(for: date), inMonth: false))
                }
            }
        }
        for day in 0..<daysInMonth {
            if let date = localizedCalendar.date(byAdding: .day, value: day, to: monthStart) {
                items.append(DurationDayItem(date: localizedCalendar.startOfDay(for: date), inMonth: true))
            }
        }
        let remainder = items.count % 7
        if remainder != 0, let last = items.last?.date {
            for offset in 1...(7 - remainder) {
                if let date = localizedCalendar.date(byAdding: .day, value: offset, to: last) {
                    items.append(DurationDayItem(date: localizedCalendar.startOfDay(for: date), inMonth: false))
                }
            }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(selectedTitle)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.muted)
                HStack(spacing: 10) {
                    dateSummaryChip(
                        title: startTitle,
                        date: rangeStart,
                        selected: !pickingEnd
                    ) {
                        pickingEnd = false
                        visibleMonth = rangeStart
                    }
                    dateSummaryChip(
                        title: endTitle,
                        date: rangeEnd,
                        selected: pickingEnd
                    ) {
                        pickingEnd = true
                        visibleMonth = rangeEnd
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 12) {
                HStack {
                    Text(monthTitle)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    Spacer()
                    HStack(spacing: 0) {
                        monthButton("chevron.left") { shiftMonth(-1) }
                        Rectangle()
                            .fill(CheckMedTheme.hairline)
                            .frame(width: 1, height: 18)
                        monthButton("chevron.right") { shiftMonth(1) }
                    }
                    .padding(.horizontal, 4)
                    .background(CheckMedTheme.locked.opacity(0.55), in: Capsule())
                }

                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                    ForEach(days) { item in
                        dayCell(item)
                    }
                }

                Text(dayCountText)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(16)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Spacer(minLength: 0)
        }
        .onAppear {
            visibleMonth = pickingEnd ? rangeEnd : rangeStart
        }
    }

    private func dateSummaryChip(title: String, date: Date, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(selected ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                Text(chipDateLabel(date))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? CheckMedTheme.mintWash : CheckMedTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? CheckMedTheme.primaryShadow : CheckMedTheme.hairline, lineWidth: selected ? 2.5 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(chipDateLabel(date))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chipDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    private func monthButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CheckMedTheme.ink)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: visibleMonth) {
            visibleMonth = next
        }
    }

    private func dayCell(_ item: DurationDayItem) -> some View {
        let day = calendar.startOfDay(for: item.date)
        let isStart = calendar.isDate(day, inSameDayAs: rangeStart)
        let isEnd = calendar.isDate(day, inSameDayAs: rangeEnd)
        let inRange = day >= rangeStart && day <= rangeEnd
        let single = calendar.isDate(rangeStart, inSameDayAs: rangeEnd)
        let number = calendar.component(.day, from: day)

        return Button {
            pick(day)
        } label: {
            ZStack {
                rangeTrack(isStart: isStart, isEnd: isEnd, inRange: inRange, single: single)
                Text("\(number)")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(textColor(isEndpoint: isStart || isEnd, inMonth: item.inMonth))
                    .frame(width: 34, height: 34)
                    .background(
                        (isStart || isEnd) ? CheckMedTheme.primary : Color.clear,
                        in: Circle()
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibility(day, isStart: isStart, isEnd: isEnd))
    }

    @ViewBuilder
    private func rangeTrack(isStart: Bool, isEnd: Bool, inRange: Bool, single: Bool) -> some View {
        if inRange, !single {
            HStack(spacing: 0) {
                if isStart {
                    Color.clear
                    CheckMedTheme.belly
                } else if isEnd {
                    CheckMedTheme.belly
                    Color.clear
                } else {
                    CheckMedTheme.belly
                }
            }
            .frame(height: 34)
        }
    }

    private func textColor(isEndpoint: Bool, inMonth: Bool) -> Color {
        if isEndpoint { return CheckMedTheme.onPrimary }
        return inMonth ? CheckMedTheme.ink : CheckMedTheme.muted.opacity(0.55)
    }

    private func pick(_ day: Date) {
        if pickingEnd {
            if day < rangeStart {
                start = day
                end = rangeStart
            } else {
                end = day
            }
        } else {
            start = day
            if rangeEnd < calendar.startOfDay(for: day) {
                end = day
            }
        }
        visibleMonth = day
    }

    private func dayAccessibility(_ day: Date, isStart: Bool, isEnd: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .long
        var label = formatter.string(from: day)
        if isStart { label += ", \(startTitle)" }
        if isEnd && !isStart { label += ", \(endTitle)" }
        return label
    }
}

struct TimesPerDayPicker: View {
    let title: String
    @Binding var value: String
    var highlightIncomplete: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(highlightIncomplete ? CheckMedTheme.beak : CheckMedTheme.muted)
            HStack(spacing: 0) {
                ForEach(["1", "2", "3", "4"], id: \.self) { option in
                    Button {
                        value = value == option ? "" : option
                    } label: {
                        Text(option)
                            .font(.system(.body, design: .rounded).weight(.heavy))
                            .foregroundStyle(value == option ? CheckMedTheme.onPrimary : CheckMedTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(value == option ? CheckMedTheme.primary : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(option)")
                }
            }
            .background(CheckMedTheme.locked.opacity(0.5))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(highlightIncomplete ? CheckMedTheme.beak.opacity(0.7) : CheckMedTheme.hairline, lineWidth: highlightIncomplete ? 2 : 1.5))
        }
    }
}

struct DoseTimesField: View {
    @Environment(SessionStore.self) private var session
    @Binding var timesPerDay: String
    @Binding var frequency: String
    @Binding var doseTimes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.doseTimesTitle))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            if timesCount > 1, doseTimes.contains(where: \.isEmpty) {
                Text(session.t(.doseTimesSpreadHint, intervalHours))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            ForEach(Array(doseTimes.indices), id: \.self) { index in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slotTitle(index))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                        Text(session.t(.doseTimeAlarmHint))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer(minLength: 8)
                    DatePicker(
                        slotTitle(index),
                        selection: timeBinding(index),
                        displayedComponents: .hourAndMinute
                    )
                    .environment(\.locale, session.locale.foundationLocale)
                    .labelsHidden()
                    .tint(CheckMedTheme.primaryShadow)
                }
            }
        }
        .onAppear { padTimesIfNeeded() }
        .onChange(of: timesPerDay) { _, _ in padTimesIfNeeded() }
    }

    private var timesCount: Int {
        if let value = Int(timesPerDay), (1...4).contains(value) { return value }
        return max(1, min(4, doseTimes.count))
    }

    private var intervalHours: Int {
        CheckMedStore.intervalHours(from: frequency, timesCount: timesCount)
    }

    private func slotTitle(_ index: Int) -> String {
        switch index {
        case 0: session.t(.doseTimeFirst)
        case 1: session.t(.doseTimeSecond)
        case 2: session.t(.doseTimeThird)
        default: session.t(.doseTimeFourth)
        }
    }

    private func padTimesIfNeeded() {
        var draft = OnboardingPrescriptionDraft.empty
        draft.timesPerDay = timesPerDay
        draft.frequency = frequency
        draft.doseTimes = doseTimes
        draft.syncDoseTimes()
        if draft.doseTimes != doseTimes {
            doseTimes = draft.doseTimes
        }
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        let calendar = CheckMedStore.clockCalendar()
        return Binding(
            get: {
                CheckMedStore.date(
                    on: Date(),
                    timeOfDay: doseTimes.indices.contains(index) ? doseTimes[index] : "08:00",
                    calendar: calendar
                ) ?? Date()
            },
            set: { date in
                guard doseTimes.indices.contains(index) else { return }
                doseTimes[index] = CheckMedStore.clockTime(from: date, calendar: calendar)
            }
        )
    }
}

struct PlanResumeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    let drafts: [OnboardingPrescriptionDraft]
    var showsAddMore: Bool = true
    var onContinue: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    PhilView(size: 108, smiling: true)
                    Text(session.t(.planJourneyHeadline))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .multilineTextAlignment(.center)
                    Text(session.t(.planJourneySubhead))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .multilineTextAlignment(.center)
                    Text(session.t(.planReportNote))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CheckMedTheme.primary.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    ForEach(Array(drafts.filter(\.hasMedicineName).enumerated()), id: \.offset) { _, draft in
                        resumeCard(draft)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            VStack(spacing: 10) {
                CheckMedButton(title: session.t(.continueButton), action: onContinue)
                if showsAddMore {
                    CheckMedButton(title: session.t(.planAddMoreOrFamily), style: .secondary) {
                        entitlements.presentPaywall()
                    }
                }
                CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }

    private func resumeCard(_ draft: OnboardingPrescriptionDraft) -> some View {
        let count = draft.timesCount
        let reason = draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 6) {
            Text(draft.medicine)
                .font(.system(.title3, design: .rounded).weight(.heavy))
            if !draft.dose.isEmpty {
                Text(draft.dose)
                    .font(.system(.body, design: .rounded).weight(.bold))
            }
            Text(session.t(.timesPerDayFormat, count))
                .font(.system(.body, design: .rounded).weight(.semibold))
            Text(PlanDuration.display(draft.duration, locale: session.locale.foundationLocale, calendar: session.foundationCalendar))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            Text("\(session.t(.doseTimesTitle)) (\(draft.compactTimesLabel))")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
            if !reason.isEmpty {
                Text(reason)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }
}

struct OnboardingOrganizeView: View {
    @Environment(SessionStore.self) private var session
    var onContinue: () -> Void
    var onBack: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            PhilView(size: 156, mood: .celebrate, pose: .pointingDown, smiling: true)
            Text(session.t(.organizeHeadline))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
            SpeechBubbleView(text: session.t(.organizeBody))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
            Spacer()
            CheckMedButton(title: session.t(.continueButton), action: onContinue)
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.28)) {
                appeared = true
            }
        }
    }
}

struct OnboardingPhilReadyView: View {
    @Environment(SessionStore.self) private var session
    var onContinue: () -> Void

    @State private var appeared = false
    @State private var didContinue = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            PhilView(size: 176, mood: .complete, smiling: true)
                .scaleEffect(appeared ? 1 : 0.86)
                .opacity(appeared ? 1 : 0.2)
            Text(session.t(.philReadyHeadline))
                .font(.system(.title, design: .rounded).weight(.black))
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            Text(session.t(.philReadyBody))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
            Spacer()
            CheckMedButton(title: session.t(.philReadyButton), action: continueNow)
                .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.32)) {
                appeared = true
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            continueNow()
        }
    }

    private func continueNow() {
        guard !didContinue else { return }
        didContinue = true
        onContinue()
    }
}

/// Free-plan gate after photo/PDF OCR, before Scan/Confirm.
struct ScanSlotLimitView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements

    let detected: [OnboardingPrescriptionDraft]
    let existingCount: Int
    @Binding var selectedKeys: Set<String>
    var onUnlockedAll: () -> Void
    var onContinueWithSelected: ([OnboardingPrescriptionDraft]) -> Void
    var onBack: () -> Void

    private var remainingSlots: Int {
        entitlements.freeMedicineSlotsRemaining(existingCount: existingCount)
    }

    private var detectedCount: Int { detected.count }

    private var continueTitle: String {
        remainingSlots == 1
            ? session.t(.scanLimitContinueOne)
            : session.t(.scanLimitContinue, remainingSlots)
    }

    private var selectedDrafts: [OnboardingPrescriptionDraft] {
        detected.filter { selectedKeys.contains(PrescriptionParser.canonicalMedicineKey($0.medicine)) }
    }

    private var canContinueWithSelection: Bool {
        remainingSlots > 0
            && !selectedDrafts.isEmpty
            && selectedDrafts.count <= remainingSlots
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    SetupStepHeader(
                        title: remainingSlots == 0
                            ? session.t(.confirmFreePlanFull)
                            : session.t(.scanLimitSelectTitle)
                    )
                    Text(detectedCount == 1
                         ? session.t(.scanLimitDetectedOne)
                         : session.t(.scanLimitDetected, detectedCount))
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(freePlanCopy)
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(session.t(.scanLimitSuperPitch))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if remainingSlots > 0 {
                        Text(session.t(.scanLimitSelectHint, remainingSlots))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    VStack(spacing: 8) {
                        ForEach(Array(detected.enumerated()), id: \.offset) { _, draft in
                            medicineRow(draft)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            VStack(spacing: 12) {
                CheckMedButton(title: session.t(.scanLimitStartTrial)) {
                    entitlements.presentPaywall()
                }
                if remainingSlots > 0 {
                    CheckMedButton(
                        title: continueTitle,
                        style: .secondary,
                        action: {
                            guard canContinueWithSelection else { return }
                            onContinueWithSelected(selectedDrafts)
                        }
                    )
                    .disabled(!canContinueWithSelection)
                    .opacity(canContinueWithSelection ? 1 : 0.45)
                }
                CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            if entitlements.isSuper || !entitlements.needsScanSlotLimit(
                detectedCount: detectedCount,
                existingCount: existingCount
            ) {
                onUnlockedAll()
            }
        }
        .onChange(of: entitlements.isSuper) { _, isSuper in
            if isSuper { onUnlockedAll() }
        }
    }

    private var freePlanCopy: String {
        if existingCount > 0 {
            return session.t(.scanLimitRemaining, existingCount, remainingSlots)
        }
        return session.t(.scanLimitFreeCap)
    }

    private func medicineRow(_ draft: OnboardingPrescriptionDraft) -> some View {
        let key = PrescriptionParser.canonicalMedicineKey(draft.medicine)
        let isSelected = selectedKeys.contains(key)
        let atCap = remainingSlots > 0 && selectedKeys.count >= remainingSlots && !isSelected
        return Button {
            guard remainingSlots > 0 else { return }
            if isSelected {
                selectedKeys.remove(key)
            } else if !atCap {
                selectedKeys.insert(key)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.medicine)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .multilineTextAlignment(.leading)
                    if !draft.dose.isEmpty {
                        Text(draft.dose)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? CheckMedTheme.primaryShadow : CheckMedTheme.hairline, lineWidth: 1.5)
            )
            .opacity(remainingSlots == 0 || atCap ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(remainingSlots == 0)
        .accessibilityLabel(draft.medicine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Scan-flow only. Does not write SwiftData or change treatment start.
struct OldPrescriptionAgeAlert: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Binding var date: Date?
    var onBack: () -> Void
    var onContinue: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            session.t(.oldPrescriptionTitle),
            isPresented: Binding(
                get: { date != nil },
                set: { if !$0 { date = nil } }
            )
        ) {
            Button(session.t(.back), role: .cancel, action: onBack)
            Button(session.t(.continueButton), action: onContinue)
        } message: {
            if let date {
                Text(
                    session.t(
                        .oldPrescriptionBody,
                        ScanPipeline.displayPrescriptionDate(date, locale: session.locale.foundationLocale)
                    )
                )
            }
        }
    }
}
