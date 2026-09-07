import PhotosUI
import SwiftUI
import UIKit

enum OnboardingAddMethod {
    case photo, pdf, manual
}

struct OnboardingPrescriptionDraft: Equatable, Sendable {
    var medicine: String
    var dose: String
    var frequency: String
    var duration: String
    var timesPerDay: String

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

    /// Combines times-per-day with the written frequency so dose slots can be built.
    var scheduleFrequency: String {
        let times = timesPerDay.trimmingCharacters(in: .whitespacesAndNewlines)
        let freq = frequency.trimmingCharacters(in: .whitespacesAndNewlines)
        if times.isEmpty { return freq }
        let stamped = "\(times)× daily"
        if freq.isEmpty { return stamped }
        return "\(stamped) · \(freq)"
    }
}

struct OnboardingAddMedicationView: View {
    @Environment(SessionStore.self) private var session
    var onPhoto: () -> Void
    var onChoosePhotos: () -> Void = {}
    var onPDF: () -> Void
    var onManual: () -> Void
    var onBack: () -> Void
    var showsChoosePhotos: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            SetupStepHeader(title: session.t(.scanAddTitle))
            Spacer(minLength: 8)
            PhilView(size: 120, pose: .pointingDown, smiling: true)
            Text(session.t(.scanOrganizeHint))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 8)
            CheckMedButton(title: session.t(.scanTakePhoto), action: onPhoto)
            if showsChoosePhotos {
                CheckMedButton(title: session.t(.scanChoosePhotos), style: .secondary, action: onChoosePhotos)
                    .keyboardShortcut("p", modifiers: [.command])
            }
            CheckMedButton(title: session.t(.scanUploadPDF), style: .secondary, action: onPDF)
            CheckMedButton(title: session.t(.scanSetManually), style: .secondary, action: onManual)
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
            SafetyCaption()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
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

struct OnboardingManualEntryView: View {
    @Environment(SessionStore.self) private var session
    @Binding var draft: OnboardingPrescriptionDraft
    var onContinue: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            SetupStepHeader(title: session.t(.scanSetManually))
            PhilView(size: 88, smiling: true)
            Text(session.t(.scanOrganizeHint))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            MedicineNameField(title: session.t(.manualMedicine), text: $draft.medicine)
            field(session.t(.manualDose), text: $draft.dose)
            timesPerDayRow
            field(session.t(.manualFrequency), text: $draft.frequency)
            DurationRangeField(duration: $draft.duration)
            Spacer(minLength: 8)
            CheckMedButton(title: session.t(.continueButton), action: onContinue)
                .disabled(!draft.isFilled)
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            TextField(title, text: text)
                .padding(12)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
                )
        }
    }

    private var timesPerDayRow: some View {
        TimesPerDayPicker(title: session.t(.manualTimesPerDay), value: $draft.timesPerDay)
    }
}

struct OnboardingAnalysingView: View {
    @Environment(SessionStore.self) private var session
    var isShort: Bool
    var work: (() async -> Void)? = nil
    var onFinished: () -> Void
    var importToken: Int = 0

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            PhilView(size: 168, mood: .celebrate, smiling: true)
                .scaleEffect(pulse ? 1.06 : 0.94)
                .opacity(pulse ? 1 : 0.82)
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
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .task(id: importToken) {
            let started = Date()
            if let work {
                await work()
            }
            let minimum = isShort ? 0.7 : 0.9
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
    var onConfirm: () -> Void
    var onBack: () -> Void

    @State private var page = 0
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case medicine, dose, frequency, duration
    }

    private var canConfirm: Bool {
        drafts.contains(where: \.isFilled)
    }

    private var keyboardOpen: Bool { focusedField != nil }
    private var freeMedicineCap: Int { SuperLimits.freePrescriptions }

    var body: some View {
        VStack(spacing: 10) {
            header
            pagerBanner
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !isManual, drafts.allSatisfy({ !$0.hasMedicineName }) {
                            Text(session.t(.scanOCREmptyHint))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        medicineFields(index: min(page, max(0, drafts.count - 1)))
                            .id("fields")
                        if !keyboardOpen {
                            CheckMedButton(title: session.t(.confirmLooksGood), action: onConfirm)
                                .disabled(!canConfirm)
                            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
                            SafetyCaption()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, keyboardOpen ? 12 : 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, field in
                    guard field != nil else { return }
                    withAnimation {
                        proxy.scrollTo("fields", anchor: .top)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            PhilThinkingImage(size: 44)
                .accessibilityHidden(true)
            Text(isManual ? session.t(.confirmManualHeadline) : session.t(.confirmEditHeadline))
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if keyboardOpen {
                Button(session.t(.done)) { focusedField = nil }
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .frame(minWidth: 44, minHeight: 44)
            } else if currentDraft.hasMedicineName {
                Button(action: removeCurrentMedicine) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CheckMedTheme.danger)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.t(.confirmRemoveMedicine))
            }
        }
    }

    private var currentDraft: OnboardingPrescriptionDraft {
        guard drafts.indices.contains(page) else { return .empty }
        return drafts[page]
    }

    private var pagerBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            pagePills
            if !entitlements.isSuper {
                Text(session.t(.confirmFreePlanLimit))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if drafts.count > 1 {
                Text(session.t(.confirmMultipleHint))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.belly)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CheckMedTheme.primaryShadow.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var pagePills: some View {
        HStack(spacing: 8) {
            ForEach(drafts.indices, id: \.self) { index in
                Button {
                    focusedField = nil
                    withAnimation(.easeInOut(duration: 0.2)) { page = index }
                } label: {
                    Text("\(index + 1)")
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(index == page ? CheckMedTheme.onPrimary : CheckMedTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(index == page ? CheckMedTheme.primary : CheckMedTheme.surface)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                index == page ? CheckMedTheme.primaryShadow : CheckMedTheme.hairline,
                                lineWidth: 1.5
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.t(.confirmMedicineOf, index + 1, drafts.count))
            }
            Button(action: addMedicineSlot) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(CheckMedTheme.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(CheckMedTheme.hairline, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.confirmAddMedicine))
            Text(session.t(.confirmMedicineOf, page + 1, max(drafts.count, 1)))
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func addMedicineSlot() {
        focusedField = nil
        if !entitlements.isSuper, drafts.count >= freeMedicineCap {
            entitlements.presentPaywall()
            return
        }
        drafts.append(.empty)
        page = drafts.count - 1
    }

    private func medicineFields(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MedicineNameField(
                title: session.t(.manualMedicine),
                text: binding(index, \.medicine)
            )
            compactField(session.t(.manualDose), text: binding(index, \.dose), field: .dose)
            TimesPerDayPicker(
                title: session.t(.manualTimesPerDay),
                value: binding(index, \.timesPerDay)
            )
            compactField(session.t(.manualFrequency), text: binding(index, \.frequency), field: .frequency)
            DurationRangeField(duration: binding(index, \.duration))
        }
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

    private func compactField(_ title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            TextField(title, text: text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
                )
                .focused($focusedField, equals: field)
        }
    }
}

struct DurationRangeField: View {
    @Environment(SessionStore.self) private var session
    @Binding var duration: String

    @State private var showPicker = false
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()

    private var calendar: Calendar { session.foundationCalendar }

    private var dayCount: Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: max(end, start))
        let diff = calendar.dateComponents([.day], from: s, to: e).day ?? 0
        return max(1, diff + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.t(.manualDuration))
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            Button {
                seedFromDuration()
                showPicker = true
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                    Text(duration.isEmpty ? session.t(.durationPickDates) : duration)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(duration.isEmpty ? CheckMedTheme.muted : CheckMedTheme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.manualDuration))
            .accessibilityValue(duration)
        }
        .sheet(isPresented: $showPicker, onDismiss: commitDays) {
            NavigationStack {
                VStack(spacing: 8) {
                    Text(session.t(.durationStart))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.muted)
                        .textCase(.uppercase)
                    DatePicker(
                        session.t(.durationStart),
                        selection: $start,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, session.locale.foundationLocale)

                    Text(session.t(.durationEnd))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.muted)
                        .textCase(.uppercase)
                    DatePicker(
                        session.t(.durationEnd),
                        selection: $end,
                        in: start...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, session.locale.foundationLocale)

                    Text(session.t(.durationDaysFormat, dayCount))
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .navigationTitle(session.t(.manualDuration))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(session.t(.done)) {
                            commitDays()
                            showPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .onAppear { seedFromDuration() }
        }
        .onChange(of: start) { _, _ in
            if end < start { end = start }
        }
    }

    private func seedFromDuration() {
        let days = duration.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
        start = Date()
        if let days, days > 0 {
            end = calendar.date(byAdding: .day, value: days - 1, to: calendar.startOfDay(for: start)) ?? start
        }
    }

    private func commitDays() {
        duration = session.t(.durationDaysFormat, dayCount)
    }
}

struct TimesPerDayPicker: View {
    let title: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(CheckMedTheme.muted)
            HStack(spacing: 8) {
                ForEach(["1", "2", "3", "4"], id: \.self) { option in
                    Button {
                        value = value == option ? "" : option
                    } label: {
                        Text(option)
                            .font(.system(.body, design: .rounded).weight(.heavy))
                            .foregroundStyle(value == option ? Color.white : CheckMedTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(value == option ? CheckMedTheme.primary : CheckMedTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        value == option ? CheckMedTheme.primaryShadow : CheckMedTheme.hairline,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(option)")
                }
            }
        }
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
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
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

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            PhilView(size: 176, mood: .complete, smiling: true)
                .scaleEffect(appeared ? 1 : 0.88)
                .opacity(appeared ? 1 : 0)
            Text(session.t(.philReadyHeadline))
                .font(.system(.title, design: .rounded).weight(.black))
                .multilineTextAlignment(.center)
            Text(session.t(.philReadyBody))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            CheckMedButton(title: session.t(.philReadyButton), action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            withAnimation(.spring(duration: 0.72, bounce: 0.32)) {
                appeared = true
            }
        }
    }
}
