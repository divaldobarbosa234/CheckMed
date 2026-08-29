import SwiftUI
import UserNotifications

struct SetupStepHeader: View {
    let title: String
    var stepIndex: Int? = nil

    var body: some View {
        VStack(spacing: 6) {
            if let stepIndex {
                Text(String(format: "%02d", stepIndex))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .tracking(1)
            }
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.heavy))
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityLabel(title)
    }
}

/// Shared pronouns + gender step. Used after preferred name / date of birth
/// on both first-time onboarding and signed-in profile setup. Language is not here.
struct AddressYouSetupView: View {
    @Environment(SessionStore.self) private var session
    var stepIndex: Int? = nil
    var onContinue: () -> Void
    var onBack: () -> Void

    @State private var pronouns = ""
    @State private var gender = ""

    var body: some View {
        VStack(spacing: 16) {
            SetupStepHeader(title: session.t(.addressYouTitle), stepIndex: stepIndex)
            Spacer()
            PhilView(size: 120)
            Text(session.t(.addressYouIntro))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            PronounSelectField(value: $pronouns) { session.setPronouns($0) }
            GenderSelectField(value: $gender) { session.setGender($0) }
            Spacer()
            CheckMedButton(title: session.t(.continueButton)) {
                session.saveAddressing(pronouns: pronouns, gender: gender)
                onContinue()
            }
            .disabled(!Self.isComplete(pronouns: pronouns, gender: gender))
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear {
            pronouns = session.pronouns
            gender = session.gender
        }
    }

    static func isComplete(pronouns: String, gender: String) -> Bool {
        let nextPronouns = pronouns.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextGender = gender.trimmingCharacters(in: .whitespacesAndNewlines)
        return !nextPronouns.isEmpty
            && nextPronouns != ProfilePronoun.custom.rawValue
            && !nextGender.isEmpty
            && nextGender != ProfileGender.custom.rawValue
    }
}

/// Shared “Allow notifications” step. Shown after Phil organizes the prescription —
/// never from Splash, language, or How it works.
struct NotificationsPermissionView: View {
    @Environment(SessionStore.self) private var session
    var stepIndex: Int? = nil
    var secondaryTitle: String? = nil
    var onEnable: () -> Void = {}
    var onSecondary: (() -> Void)? = nil
    var onBack: () -> Void

    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 16) {
            SetupStepHeader(title: session.t(.notifsTitle), stepIndex: stepIndex)
            Spacer()
            PhilView(size: 148)
            Text(session.t(.notifsHeadline))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                Text(session.t(.notifsMeds))
                Text(session.t(.notifsTreatment))
                Text(session.t(.notifsImportant))
            }
            .font(.system(.body, design: .rounded).weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            CheckMedButton(title: session.t(.notifsEnable)) {
                requestThenFinish(onEnable)
            }
            .disabled(isRequesting)
            if let secondaryTitle, let onSecondary {
                CheckMedButton(title: secondaryTitle, style: .secondary) {
                    session.markNotificationsPrompted()
                    onSecondary()
                }
                .disabled(isRequesting)
            }
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
                .disabled(isRequesting)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func requestThenFinish(_ done: @escaping () -> Void) {
        isRequesting = true
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                session.markNotificationsPrompted()
                isRequesting = false
                done()
            }
        }
    }
}
