import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var session
    var onCreateAccount: () -> Void
    var onGuest: () -> Void
    var onBack: () -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var companion = "Phil"

    private struct Beat {
        let title: String
        let bubble: String
        let caption: String
    }

    private var beats: [Beat] {
        [
            Beat(
                title: "Hi! I'm \(companion.isEmpty ? "Phil" : companion).",
                bubble: "I'll stick with you — like a streak pal for your medicines. What should I call you?",
                caption: "Name your companion and yourself. Phil is the host, not a decoration."
            ),
            Beat(
                title: "Scan · we organize · you check",
                bubble: "Photograph or import a prescription. I structure what was written. You verify every field.",
                caption: "OCR is a reading aid. I never recommend a medicine, a dose, or a diagnosis."
            ),
            Beat(
                title: "Today is a path",
                bubble: "Home is dose nodes, not a clinical table first. Taken celebrates. Skip does not break the streak.",
                caption: "Alarms land in Phase 5. Super never locks taking a dose."
            ),
            Beat(
                title: "Want me to remind you?",
                bubble: "Medication reminders, treatment alerts, important pings. You can change this later in Profile.",
                caption: "Display name stays with the account once you sign in."
            ),
        ]
    }

    private var last: Bool { step == beats.count - 1 }
    private var beat: Beat { beats[step] }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("\(step + 1)/\(beats.count)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .textCase(.uppercase)
                    .tracking(1)
                HStack(spacing: 8) {
                    ForEach(0..<beats.count, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? CheckMedTheme.primary : CheckMedTheme.locked)
                            .frame(width: index == step ? 18 : 8, height: 8)
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
            PhilView(size: 128)
            SpeechBubbleView(text: beat.bubble)
            Text(beat.title)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            Text(beat.caption)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            Spacer()

            if step == 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your name")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(CheckMedTheme.muted)
                    TextField("Alex", text: $name)
                        .padding(14)
                        .background(CheckMedTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
                    Text("Companion name")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(CheckMedTheme.muted)
                    TextField("Phil", text: $companion)
                        .padding(14)
                        .background(CheckMedTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
                }
            }

            CheckMedButton(title: last ? "Create account" : "Continue", action: next)
            if last {
                CheckMedButton(title: "Continue as guest", style: .secondary, action: skipToGuest)
            } else {
                CheckMedButton(title: "Back", style: .ghost) {
                    if step == 0 {
                        onBack()
                    } else {
                        step -= 1
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear {
            if session.displayName != "there" { name = session.displayName }
            companion = session.companionName
        }
    }

    private func persistNames() {
        session.saveOnboardingNames(displayName: name, companionName: companion)
    }

    private func next() {
        persistNames()
        if last {
            onCreateAccount()
            return
        }
        step += 1
    }

    private func skipToGuest() {
        persistNames()
        session.continueAsGuest()
        onGuest()
    }
}
