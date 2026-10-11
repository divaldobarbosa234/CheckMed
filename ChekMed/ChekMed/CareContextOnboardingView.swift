import SwiftUI

struct CareContextOnboardingView: View {
    @Environment(SessionStore.self) private var session
    var onContinue: () -> Void

    @State private var selection: CareContextChoice?
    @State private var didFinish = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    PhilView(size: 96, smiling: true)
                    VStack(spacing: 8) {
                        Text(session.t(.careContextTitle))
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(CheckMedTheme.navy)
                            .multilineTextAlignment(.center)
                        Text(session.t(.careContextLead))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 10) {
                        ForEach(CareContextChoice.allCases, id: \.self) { choice in
                            careCard(choice)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            CheckMedButton(title: session.t(.continueButton), action: finish)
                .disabled(selection == nil)
                .accessibilityIdentifier("care-context-continue")
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .safeAreaPadding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.welcomeCream.ignoresSafeArea())
        .onAppear {
            if selection == nil {
                selection = session.careContextChoice
            }
        }
        .accessibilityLabel(session.t(.careContextTitle))
    }

    private func careCard(_ choice: CareContextChoice) -> some View {
        let selected = selection == choice
        return Button {
            selection = choice
        } label: {
            HStack(spacing: 12) {
                Text(session.t(choice.titleKey))
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.navy)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? CheckMedTheme.primary : CheckMedTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? CheckMedTheme.mintWash : CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? CheckMedTheme.navy.opacity(0.28) : CheckMedTheme.hairline, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("care-context-\(choice.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func finish() {
        guard let selection else { return }
        guard OnboardingWelcomeRouting.consumeCareContextAdvance(alreadyFinished: didFinish) else { return }
        didFinish = true
        session.setCareContext(selection)
        onContinue()
    }
}

struct CareContextSelectField: View {
    @Environment(SessionStore.self) private var session
    @Binding var value: CareContextChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.t(.careContextTitle))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            VStack(spacing: 8) {
                ForEach(CareContextChoice.allCases, id: \.self) { choice in
                    Button {
                        value = choice
                        session.setCareContext(choice)
                    } label: {
                        HStack {
                            Text(session.t(choice.titleKey))
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.navy)
                            Spacer()
                            if value == choice {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(CheckMedTheme.primaryShadow)
                            }
                        }
                        .padding(12)
                        .background(value == choice ? CheckMedTheme.mintWash : CheckMedTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
