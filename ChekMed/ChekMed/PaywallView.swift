import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    PhilView(size: 96)
                    SpeechBubbleView(
                        text: entitlements.isSuper
                            ? session.t(.paywallOnBubble)
                            : session.t(.paywallOffBubble)
                    )
                }

                Text(session.t(.paywallTitle))
                    .font(.system(size: 28, weight: .black, design: .rounded))

                Text(session.t(.paywallBody))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)

                planCard(
                    title: session.t(.paywallFree),
                    tint: CheckMedTheme.primary,
                    items: [
                        session.t(.paywallFree1),
                        session.t(.paywallFree2),
                        session.t(.paywallFree3),
                        session.t(.paywallFree4),
                        session.t(.paywallFree5),
                        session.t(.paywallFree6),
                        session.t(.paywallFree7),
                    ]
                )

                planCard(
                    title: session.t(.paywallSuper),
                    tint: CheckMedTheme.superAccent,
                    items: [
                        session.t(.paywallSuper1),
                        session.t(.paywallSuper2),
                        session.t(.paywallSuper3),
                        session.t(.paywallSuper4),
                        session.t(.paywallSuper5),
                        session.t(.paywallSuper7),
                        session.t(.paywallSuper8),
                        session.t(.paywallSuper9),
                        session.t(.paywallSuper10),
                    ]
                )

                if entitlements.isSuper {
                    Text(entitlements.usedDebugUnlock
                         ? session.t(.paywallDebugNote)
                         : session.t(.paywallActive))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.superAccent)
                } else if entitlements.products.isEmpty {
                    Text(session.t(.paywallProductsMissing))
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

                CheckMedButton(title: session.t(.paywallRestore), style: .secondary) {
                    Task { await entitlements.restore() }
                }
                .disabled(entitlements.isLoading)

                if entitlements.allowsDebugUnlock {
                    CheckMedButton(
                        title: entitlements.usedDebugUnlock ? session.t(.paywallClearDebug) : session.t(.paywallUnlockDebug),
                        style: .ghost
                    ) {
                        if entitlements.usedDebugUnlock {
                            entitlements.clearDebugUnlock()
                        } else {
                            entitlements.unlockForDevelopment()
                        }
                    }
                }

                CheckMedButton(title: session.t(.paywallNotNow), style: .ghost, action: dismiss.callAsFunction)

                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.paywallSuper))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(session.t(.paywallClose), action: dismiss.callAsFunction)
            }
        }
        .task { await entitlements.refresh() }
    }

    private func subscribeTitle(for product: Product) -> String {
        "Super \(product.displayPrice) \(period(for: product))"
    }

    private func period(for product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .year: session.t(.paywallPerYear)
        case .month: session.t(.paywallPerMonth)
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
