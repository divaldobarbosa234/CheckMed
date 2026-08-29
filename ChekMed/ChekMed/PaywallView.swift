import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    PhilView(size: 96)
                    SpeechBubbleView(
                        text: entitlements.isSuper
                            ? "Super is on. Streak freeze and a second family seat are yours. Taken was always free."
                            : "Super is like Duolingo Super. Streak freeze, extra looks, one extra family profile. Taken stays free."
                    )
                }

                Text("Super CheckMed")
                    .font(.system(size: 28, weight: .black, design: .rounded))

                Text("Core logging and reminders stay free. Super never locks Taken or creating your first treatment.")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)

                planCard(
                    title: "Free",
                    tint: CheckMedTheme.primary,
                    items: [
                        "Account, one profile, scan, today's path",
                        "Reminders and tracking",
                        "One companion look",
                        "Taken is always free",
                        "First treatment editor is always free",
                    ]
                )

                planCard(
                    title: "Super",
                    tint: CheckMedTheme.superAccent,
                    items: [
                        "Streak freeze",
                        "Extra companion looks",
                        "Extra alarm sounds",
                        "One extra family profile",
                        "Voice-read polish",
                        "Longer history filters",
                    ]
                )

                if entitlements.isSuper {
                    Text(entitlements.usedDebugUnlock
                         ? "Super is unlocked on this debug/simulator install — not an App Store charge."
                         : "Super is active on this Apple ID.")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.superAccent)
                } else if entitlements.products.isEmpty {
                    Text("App Store products are not connected yet (com.checkmed.super.monthly / yearly). Restore still checks this Apple ID. Nothing here charges Apple until those products exist.")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.safety)
                }

                if let status = entitlements.statusMessage {
                    Text(status)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.safety)
                }

                if entitlements.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                ForEach(entitlements.products, id: \.id) { product in
                    CheckMedButton(title: subscribeTitle(for: product)) {
                        Task { await entitlements.purchase(product) }
                    }
                    .disabled(entitlements.isLoading || entitlements.isSuper)
                }

                CheckMedButton(title: "Restore purchases", style: .secondary) {
                    Task { await entitlements.restore() }
                }
                .disabled(entitlements.isLoading)

                if entitlements.allowsDebugUnlock {
                    CheckMedButton(
                        title: entitlements.usedDebugUnlock ? "Clear simulator unlock" : "Unlock Super (simulator / debug only)",
                        style: .ghost
                    ) {
                        if entitlements.usedDebugUnlock {
                            entitlements.clearDebugUnlock()
                        } else {
                            entitlements.unlockForDevelopment()
                        }
                    }
                }

                CheckMedButton(title: "Not now", style: .ghost, action: dismiss.callAsFunction)

                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(CheckMedTheme.background)
        .navigationTitle("Super")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: dismiss.callAsFunction)
            }
        }
        .task { await entitlements.refresh() }
    }

    private func subscribeTitle(for product: Product) -> String {
        "Super \(product.displayPrice) \(period(for: product))"
    }

    private func period(for product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .year: "per year"
        case .month: "per month"
        default: ""
        }
    }

    private func planCard(title: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item)
                }
                .font(.system(.body, design: .rounded).weight(.bold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 2)
        )
    }
}
