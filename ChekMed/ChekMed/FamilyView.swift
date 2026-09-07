import SwiftUI

struct FamilyView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(FamilyStore.self) private var family
    @Environment(CheckMedStore.self) private var treatments
    @Environment(\.dismiss) private var dismiss

    @State private var nameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.t(.profileFamily))
                    .font(.system(size: 28, weight: .black, design: .rounded))
                HStack(alignment: .center, spacing: 12) {
                    PhilView(size: 72)
                    SpeechBubbleView(
                        text: entitlements.extraFamilySlotUnlocked
                            ? session.t(.familyNeverMixOn)
                            : session.t(.familyNeverMixOff)
                    )
                }

                profileCard(
                    title: session.displayName,
                    subtitle: family.isViewingExtra ? session.t(.familyYou) : session.t(.familyYouActive),
                    locked: false
                )
                if family.isViewingExtra {
                    CheckMedButton(title: session.t(.familySwitchTo), style: .secondary) {
                        family.selectPrimary()
                        family.applyScope(to: treatments, primaryProfileId: session.profileId)
                    }
                }

                if entitlements.extraFamilySlotUnlocked {
                    extraSeat
                } else {
                    Button {
                        entitlements.presentPaywall()
                    } label: {
                        profileCard(
                            title: session.t(.familyAddProfile),
                            subtitle: session.t(.familyAddLockedSubtitle),
                            locked: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.t(.familyAddProfile))
                }

                CheckMedButton(title: session.t(.familyBackProfile), style: .secondary, action: dismiss.callAsFunction)
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.profileFamily))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nameDraft = family.extra?.name ?? ""
        }
    }

    @ViewBuilder
    private var extraSeat: some View {
        if let extra = family.extra {
            profileCard(
                title: extra.name,
                subtitle: family.isViewingExtra
                    ? session.t(.familyYouActive)
                    : session.t(.paywallSuper1),
                locked: false
            )
            CheckMedButton(title: session.t(.familySwitchTo), style: .secondary) {
                _ = family.selectExtra()
                family.applyScope(to: treatments, primaryProfileId: session.profileId)
            }
            CheckMedButton(title: session.t(.familyRemove), style: .ghost) {
                family.selectPrimary()
                family.removeExtra()
                family.applyScope(to: treatments, primaryProfileId: session.profileId)
                nameDraft = ""
            }
        } else {
            profileCard(
                title: session.t(.familyAddProfile),
                subtitle: session.t(.familyEmptySeat),
                locked: false
            )
            TextField(session.t(.familyNamePlaceholder), text: $nameDraft)
                .padding(14)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
            CheckMedButton(title: session.t(.familySaveMember)) {
                if family.addExtra(name: nameDraft, allowed: entitlements.extraFamilySlotUnlocked) {
                    nameDraft = family.extra?.name ?? nameDraft
                } else {
                    entitlements.presentPaywall()
                }
            }
            .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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
                SuperLockBadge()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(locked ? CheckMedTheme.superAccent.opacity(0.5) : CheckMedTheme.hairline, lineWidth: 2)
        )
    }
}
