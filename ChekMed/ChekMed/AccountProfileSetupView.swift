import SwiftUI

struct AccountProfileSetupView: View {
    @Environment(SessionStore.self) private var session
    var showsSignOut = true
    var onFinished: (() -> Void)? = nil

    private enum Step {
        case callYou
        case addressYou
    }

    @State private var step: Step = .callYou
    @State private var name = ""
    @State private var birthDate: Date?

    var body: some View {
        Group {
            switch step {
            case .callYou:
                callYou
            case .addressYou:
                AddressYouSetupView(
                    onContinue: {
                        onFinished?()
                    },
                    onBack: { step = .callYou }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            step = session.needsCallYouScreen ? .callYou : .addressYou
            if session.hasPreferredName {
                name = session.displayName
            } else if let inferred = session.inferredPreferredName {
                name = inferred
            }
            birthDate = session.birthDate
            applyDebugLaunchHooks()
        }
    }

    private var callYou: some View {
        VStack(spacing: 18) {
            SetupStepHeader(title: session.t(.callYouTitle))
            PhilView(size: 108)
            Text(session.t(.callYouIntro))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            nameField
            DateOfBirthSelectField(date: $birthDate) { session.setBirthDate($0) }
            Spacer(minLength: 8)
            CheckMedButton(title: session.t(.continueButton)) {
                persistCallYou()
                step = .addressYou
            }
            .disabled(!canContinueCallYou)
            if showsSignOut {
                CheckMedButton(title: session.t(.profileSignOut), style: .ghost) {
                    session.signOut()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var canContinueCallYou: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && birthDate != nil
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

    private func persistCallYou() {
        session.setDisplayName(name)
        session.setBirthDate(birthDate)
    }
}
