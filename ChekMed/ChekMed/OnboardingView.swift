import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var session
    var onFinished: () -> Void
    var onCreateAccount: () -> Void
    var onBack: () -> Void

    enum Step: Int {
        case howItWorks = 0
        case personalSetup = 1
        case notifications = 2
    }

    @State private var step: Step = .howItWorks
    @State private var name = ""
    @State private var birthDate: Date?
    @State private var locale: AppLocale = .english
    @State private var timeZone = CheckMedTimeZones.preferred

    var body: some View {
        Group {
            switch step {
            case .howItWorks:
                howItWorks
            case .personalSetup:
                personalSetup
            case .notifications:
                notifications
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            if session.displayName != "there" { name = session.displayName }
            birthDate = session.birthDate
            locale = session.locale
            timeZone = session.timeZoneName
        }
    }

    private var howItWorks: some View {
        VStack(spacing: 16) {
            header(session.t(.howTitle), kicker: session.t(.howKicker))
            Spacer()
            Text(session.t(.howHeadline))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            ForEach(L10n.howSteps(session.locale), id: \.title) { item in
                HStack(alignment: .center, spacing: 12) {
                    PhilView(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                        Text(item.body)
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    Spacer()
                }
                .padding(12)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Spacer()
            CheckMedButton(title: session.t(.continueButton)) { step = .personalSetup }
            CheckMedButton(title: session.t(.back), style: .ghost, action: onBack)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var personalSetup: some View {
        VStack(spacing: 16) {
            header(session.t(.setupTitle))
            Spacer()
            PhilView(size: 120)
            Text(session.t(.setupIntro))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            field(session.t(.name), text: $name, placeholder: "Alex")
            DateOfBirthSelectField(date: $birthDate) { session.setBirthDate($0) }
            LanguageSelectField(locale: $locale) { session.setLocale($0) }
            TimeZoneSelectField(timeZone: $timeZone) { session.setTimeZoneName($0) }
            Text(session.t(.setupPhoto))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            CheckMedButton(title: session.t(.continueButton)) {
                persist()
                step = .notifications
            }
            CheckMedButton(title: session.t(.back), style: .ghost) { step = .howItWorks }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var notifications: some View {
        VStack(spacing: 16) {
            header(session.t(.notifsTitle))
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
                persist()
                session.continueAsGuest()
                onFinished()
            }
            CheckMedButton(title: session.t(.createAccount), style: .secondary) {
                persist()
                session.continueAsGuest()
                onCreateAccount()
            }
            CheckMedButton(title: session.t(.back), style: .ghost) { step = .personalSetup }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func header(_ title: String, kicker: String? = nil) -> some View {
        VStack(spacing: 6) {
            Text("0\(step.rawValue + 3)")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .tracking(1)
            if let kicker {
                Text(kicker)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.heavy))
        }
        .padding(.top, 8)
        .accessibilityLabel(title)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CheckMedTheme.muted)
            TextField(placeholder, text: text)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
        }
    }

    private func persist() {
        session.saveOnboardingProfile(
            displayName: name,
            language: locale.rawValue,
            timeZoneName: timeZone,
            birthDate: birthDate
        )
    }
}
