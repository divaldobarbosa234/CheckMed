import SwiftUI

enum OnboardingAddMethod {
    case photo, pdf, manual
}

struct OnboardingPrescriptionDraft {
    var medicine: String
    var dose: String
    var frequency: String
    var duration: String

    static let scanned = OnboardingPrescriptionDraft(
        medicine: "Amoxicillin 500mg",
        dose: "1 capsule",
        frequency: "3× daily",
        duration: "7 days"
    )

    static let empty = OnboardingPrescriptionDraft(
        medicine: "",
        dose: "",
        frequency: "",
        duration: ""
    )

    var isFilled: Bool {
        !medicine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !dose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !frequency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct OnboardingAddMedicationView: View {
    @Environment(SessionStore.self) private var session
    var onPhoto: () -> Void
    var onPDF: () -> Void
    var onManual: () -> Void
    var onBack: () -> Void

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
            CheckMedButton(title: session.t(.scanUploadPDF), style: .secondary, action: onPDF)
            CheckMedButton(title: session.t(.scanSetManually), style: .secondary, action: onManual)
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
    }
}

struct OnboardingCameraView: View {
    @Environment(SessionStore.self) private var session
    var onCapture: () -> Void
    var onBack: () -> Void

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
                    Text(session.t(.scanViewfinder))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            Spacer(minLength: 8)
            CheckMedButton(title: session.t(.scanCapture), action: onCapture)
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
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
            field(session.t(.manualMedicine), text: $draft.medicine)
            field(session.t(.manualDose), text: $draft.dose)
            field(session.t(.manualFrequency), text: $draft.frequency)
            field(session.t(.manualDuration), text: $draft.duration)
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
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
        }
    }
}

struct OnboardingAnalysingView: View {
    @Environment(SessionStore.self) private var session
    var isShort: Bool
    var onFinished: () -> Void

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
        .task {
            let nanos: UInt64 = isShort ? 800_000_000 : 2_600_000_000
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            onFinished()
        }
        .accessibilityLabel(session.t(.scanAnalysingTitle))
    }
}

struct OnboardingConfirmView: View {
    @Environment(SessionStore.self) private var session
    @Binding var draft: OnboardingPrescriptionDraft
    var isManual: Bool
    var onConfirm: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            SetupStepHeader(
                title: isManual ? session.t(.confirmManualHeadline) : session.t(.confirmEditHeadline)
            )
            PhilView(size: 88, smiling: true)
            field(session.t(.manualMedicine), text: $draft.medicine)
            field(session.t(.manualDose), text: $draft.dose)
            field(session.t(.manualFrequency), text: $draft.frequency)
            field(session.t(.manualDuration), text: $draft.duration)
            Spacer(minLength: 8)
            CheckMedButton(title: session.t(.confirmLooksGood), action: onConfirm)
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
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
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
