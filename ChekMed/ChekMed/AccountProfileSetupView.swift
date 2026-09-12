import SwiftUI

struct AccountProfileSetupView: View {
    @Environment(SessionStore.self) private var session
    var showsSignOut = true
    var onFinished: (() -> Void)? = nil

    /// Strictly forward except explicit Back. Raw value only increases via Continue.
    private enum Step: Int, Comparable {
        case callYou = 0
        case addressYou = 1

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @State private var step: Step = .callYou
    @State private var highestStepReached: Int = 0
    @State private var name = ""
    @State private var birthDate: Date?
    @State private var didChooseInitialStep = false

    var body: some View {
        Group {
            switch step {
            case .callYou:
                callYou
            case .addressYou:
                AddressYouSetupView(
                    onContinue: {
                        session.markProfileSetupComplete()
                        onFinished?()
                    },
                    onBack: { goBackToCallYou() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            chooseInitialStepIfNeeded()
            hydrateFields()
            applyDebugLaunchHooks()
        }
    }

    private var callYou: some View {
        VStack(spacing: 18) {
            SetupStepHeader(title: session.t(.callYouTitle), stepIndex: 1)
            PhilView(size: 108)
            Text(session.t(.callYouIntro))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            nameField
            DateOfBirthSelectField(date: $birthDate) { session.setBirthDate($0) }
            Spacer(minLength: 8)
            CheckMedButton(title: session.t(.continueButton)) {
                persistCallYou()
                advanceForward(to: .addressYou)
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

    /// Initial placement only. Never bounce addressYou → callYou on remount once past callYou.
    private func chooseInitialStepIfNeeded() {
        guard !didChooseInitialStep else { return }
        didChooseInitialStep = true
        let initial: Step = session.needsCallYouScreen ? .callYou : .addressYou
        step = initial
        highestStepReached = initial.rawValue
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
    }

    private func advanceForward(to next: Step) {
        // Forward-only: never decrease step except via explicit Back.
        guard next.rawValue >= step.rawValue else { return }
        step = next
        highestStepReached = max(highestStepReached, next.rawValue)
    }

    private func goBackToCallYou() {
        step = .callYou
        // Keep highestStepReached so a remount after Back still prefers addressYou
        // only when callYou is already satisfied — remount uses needsCallYouScreen.
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
