import SwiftUI

struct AccountProfileSetupView: View {
    @Environment(SessionStore.self) private var session
    var showsSignOut = true
    var onFinished: (() -> Void)? = nil

    @State private var name = ""
    @State private var birthDate: Date?
    @State private var pronouns = ""
    @State private var gender = ""
    @State private var didFinish = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    PhilView(size: 96, smiling: true)
                    VStack(spacing: 8) {
                        Text(session.t(.profileMeetTitle))
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(CheckMedTheme.navy)
                            .multilineTextAlignment(.center)
                        Text(session.t(.profileMeetLead))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    nameField
                    DateOfBirthSelectField(date: $birthDate) { session.setBirthDate($0) }
                    optionalCaption
                    PronounSelectField(value: $pronouns) { session.setPronouns($0) }
                    GenderSelectField(value: $gender) { session.setGender($0) }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            CheckMedButton(title: session.t(.continueButton)) {
                persistAndFinish()
            }
            .disabled(!canContinue)
            .accessibilityIdentifier("profile-setup-continue")
            .padding(.horizontal, 24)
            .padding(.top, 8)
            if showsSignOut {
                CheckMedButton(title: session.t(.profileSignOut), style: .ghost) {
                    session.signOut()
                }
                .padding(.horizontal, 24)
            }
        }
        .safeAreaPadding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.welcomeCream.ignoresSafeArea())
        .onAppear {
            hydrateFields()
            applyDebugLaunchHooks()
        }
        .accessibilityLabel(session.t(.profileMeetTitle))
    }

    private var canContinue: Bool {
        OnboardingIdentityPolicy.hasRequiredIdentity(
            hasPreferredName: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasBirthDate: birthDate != nil
        )
    }

    private var optionalCaption: some View {
        Text(session.t(.profileOptionalLater))
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(CheckMedTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.t(.preferredName))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CheckMedTheme.muted)
            TextField("Alex", text: $name)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
        }
    }

    private func hydrateFields() {
        if session.hasPreferredName {
            name = session.displayName
        } else if name.isEmpty, let inferred = session.inferredPreferredName {
            name = inferred
        }
        if birthDate == nil {
            birthDate = session.birthDate
        }
        if pronouns.isEmpty {
            pronouns = session.pronouns
        }
        if gender.isEmpty {
            gender = session.gender
        }
    }

    private func applyDebugLaunchHooks() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let value = env["CHECKMED_UI_NAME"], !value.isEmpty {
            name = value
        }
        if birthDate == nil, env["CHECKMED_UI_NAME"] != nil || env["CHECKMED_UI_SIGNUP"] == "1" {
            var components = DateComponents()
            components.year = 1994
            components.month = 6
            components.day = 15
            birthDate = Calendar(identifier: .gregorian).date(from: components)
        }
        #endif
    }

    private func persistAndFinish() {
        guard canContinue else { return }
        guard OnboardingWelcomeRouting.consumeProfileAdvance(alreadyFinished: didFinish) else { return }
        didFinish = true
        session.setDisplayName(name)
        session.setBirthDate(birthDate)
        if !pronouns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.setPronouns(pronouns)
        }
        if !gender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.setGender(gender)
        }
        session.markProfileSetupComplete()
        onFinished?()
    }
}
