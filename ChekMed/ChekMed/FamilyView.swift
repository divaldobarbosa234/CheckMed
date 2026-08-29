import SwiftUI

struct FamilyView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Family")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                HStack(alignment: .center, spacing: 12) {
                    PhilView(size: 72)
                    SpeechBubbleView(
                        text: entitlements.extraFamilySlotUnlocked
                            ? "Two seats. I sit beside whoever is active — never mix two people's doses."
                            : "One profile is free. A second slot is Super. I sit beside whoever is active — never mix two people's doses."
                    )
                }

                profileCard(
                    title: session.displayName,
                    subtitle: "You · active",
                    locked: false
                )

                if entitlements.extraFamilySlotUnlocked {
                    profileCard(
                        title: "Family member",
                        subtitle: "Empty Super seat. Switching profiles lands with Super family in Phase 6.",
                        locked: false
                    )
                } else {
                    Button {
                        entitlements.presentPaywall()
                    } label: {
                        profileCard(
                            title: "Add a family profile",
                            subtitle: "Second seat is Super. Your first profile stays free.",
                            locked: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a family profile. Super required.")
                }

                CheckMedButton(title: "Back to profile", style: .secondary, action: dismiss.callAsFunction)
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle("Family")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func profileCard(title: String, subtitle: String, locked: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                Text(subtitle)
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Spacer()
            if locked {
                Text("SUPER")
                    .font(.system(.caption2, design: .rounded).weight(.black))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CheckMedTheme.superAccent, in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(locked ? CheckMedTheme.superAccent.opacity(0.5) : Color(hex: 0xEFEFEF), lineWidth: 2)
        )
    }
}
