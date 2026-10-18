import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var onClose: (() -> Void)? = nil
    /// Kept for onboarding call sites. This paywall is a single screen.
    var startAtChoosePlan: Bool = false

    @State private var selectedProductID = SuperProductID.yearly

    init(onClose: (() -> Void)? = nil, startAtChoosePlan: Bool = false) {
        self.onClose = onClose
        self.startAtChoosePlan = startAtChoosePlan
    }

    private var yearly: Product? { entitlements.yearlyProduct }
    private var monthly: Product? { entitlements.monthlyProduct }
    private var selectedProduct: Product? {
        entitlements.products.first { $0.id == selectedProductID } ?? yearly ?? monthly
    }

    private var superItems: [String] {
        [
            session.t(.paywallSuper1),
            session.t(.paywallSuper2),
            session.t(.paywallSuper3),
            session.t(.paywallSuper5),
            session.t(.paywallSuper6),
            session.t(.paywallSuper7),
            session.t(.paywallSuper8),
            session.t(.paywallSuper9),
            session.t(.paywallSuper10),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if entitlements.isSuper {
                    activeCard
                } else {
                    trialHeadline
                    cooperHero
                    planPicker
                    includesCard
                    trustRow
                    statusBlock
                    cta
                    restoreNotNowButtons
                    legalFooter
                }
                SafetyCaption()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(CheckMedTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await entitlements.refresh()
            if yearly == nil, let monthly {
                selectedProductID = monthly.id
            }
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var header: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(CheckMedTheme.surface, in: Circle())
                    .overlay(Circle().stroke(CheckMedTheme.hairline, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.paywallNotNow))
            Spacer()
            Text(session.t(.paywallSuper))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.top, 8)
    }

    private var trialHeadline: some View {
        VStack(spacing: 8) {
            headlineText
            if let selectedProduct, case .trial = entitlements.acquisitionMessaging(for: selectedProduct) {
                Text(session.t(.paywallThenContinue, "\(selectedProduct.displayPrice) \(period(for: selectedProduct))"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else if case .standard = entitlements.acquisitionMessaging(for: selectedProduct) {
                Text(session.t(.paywallStandardBody))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var headlineText: some View {
        switch entitlements.acquisitionMessaging(for: selectedProduct) {
        case .checking:
            Text(session.t(.paywallCheckingOffer))
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.ink)
        case .missingProducts, .standard:
            Text(session.t(.paywallStandardLead))
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.ink)
        case .trial(let days):
            Text(session.t(.paywallTrialLead))
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.ink)
            + Text(trialAccent(days: days))
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.primaryShadow)
            + Text(session.t(.paywallTrialTail))
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.ink)
        }
    }

    private var cooperHero: some View {
        Image("cooper_super_hero")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: 148)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityLabel("Cooper")
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            if let yearly {
                planCard(product: yearly, title: session.t(.paywallPlanYearly), popular: true)
            }
            if let monthly {
                planCard(product: monthly, title: session.t(.paywallPlanMonthly), popular: false)
            }
        }
    }

    private func planCard(product: Product, title: String, popular: Bool) -> some View {
        let selected = selectedProductID == product.id
        return Button {
            selectedProductID = product.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if popular {
                    Text(session.t(.paywallMostPopular))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.onPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(CheckMedTheme.primary, in: Capsule())
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                        Text(product.displayPrice)
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.ink)
                    }
                    Spacer()
                    Text(period(for: product))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.muted)
                    ZStack {
                        Circle()
                            .stroke(selected ? CheckMedTheme.primaryShadow : CheckMedTheme.hairline, lineWidth: 2)
                            .frame(width: 24, height: 24)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(CheckMedTheme.onPrimary)
                                .frame(width: 18, height: 18)
                                .background(CheckMedTheme.primary, in: Circle())
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? CheckMedTheme.belly : CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? CheckMedTheme.primaryShadow : CheckMedTheme.hairline, lineWidth: selected ? 2.5 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var includesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.paywallIncludes))
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
            ForEach(superItems, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                    Text(item)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private var trustRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(CheckMedTheme.flowDot)
            Text(session.t(.paywallSecureApple))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .overlay(
            Capsule().stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var statusBlock: some View {
        if entitlements.products.isEmpty {
            Text(session.t(.paywallProductsMissing))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
                .multilineTextAlignment(.center)
        }
        if let status = localizedStatus(entitlements.userStatus) {
            Text(status)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
                .multilineTextAlignment(.center)
        }
        if entitlements.isLoading {
            ProgressView()
                .tint(CheckMedTheme.primaryShadow)
        }
    }

    private var cta: some View {
        VStack(spacing: 10) {
            Text(session.t(.paywallCancelAnytime))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            if let selectedProduct {
                CheckMedButton(title: primaryTitle(for: selectedProduct)) {
                    Task { await entitlements.purchase(selectedProduct) }
                }
                .disabled(!canPurchase)
            }
        }
    }

    private var restoreNotNowButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await entitlements.restore() }
            } label: {
                Text(session.t(.paywallRestore))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(CheckMedTheme.primary, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)
            .disabled(entitlements.isLoading)
            .accessibilityLabel(session.t(.paywallRestore))

            Button(action: close) {
                Text(session.t(.paywallNotNow))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(CheckMedTheme.locked, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.paywallNotNow))
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text(renewalLegalText)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            HStack(spacing: 4) {
                NavigationLink {
                    LegalDocumentView(kind: .termsOfUse)
                } label: {
                    Text(session.t(.termsOfUseTitle))
                        .underline()
                }
                Text(session.t(.paywallAnd))
                NavigationLink {
                    LegalDocumentView(kind: .privacyPolicy)
                } label: {
                    Text(session.t(.privacyPolicyTitle))
                        .underline()
                }
            }
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.flowDot)
        }
        .frame(maxWidth: .infinity)
    }

    private var activeCard: some View {
        VStack(spacing: 12) {
            Image("cooper_super_celebrate")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 120)
                .accessibilityLabel("Cooper")
            SpeechBubbleView(
                text: entitlements.usedDebugUnlock
                    ? session.t(.paywallDebugNote)
                    : session.t(.paywallOnBubble)
            )
            Text(session.t(.paywallActive))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.superAccent)
            CheckMedButton(title: session.t(.paywallClose), action: close)
        }
    }

    private var canPurchase: Bool {
        guard let selectedProduct else { return false }
        if entitlements.isLoading { return false }
        if entitlements.isSuper { return false }
        return entitlements.introEligibility(for: selectedProduct) != .unknown
    }

    private func primaryTitle(for product: Product) -> String {
        switch entitlements.introEligibility(for: product) {
        case .eligible:
            if let days = entitlements.introTrialDayCount(for: product) {
                return days == 1
                    ? session.t(.paywallStartTrialDay, days)
                    : session.t(.paywallStartTrialDays, days)
            }
            return session.t(.paywallStartTrialGeneric)
        case .ineligible:
            return session.t(.paywallStartPlan, session.t(.paywallSuper), product.displayPrice)
        case .unknown:
            return session.t(.paywallCheckingOffer)
        }
    }

    private func trialAccent(days: Int?) -> String {
        guard let days else { return session.t(.paywallTrialAccentGeneric) }
        return days == 1
            ? session.t(.paywallTrialAccentDay, days)
            : session.t(.paywallTrialAccentDays, days)
    }

    private var renewalLegalText: String {
        switch entitlements.acquisitionMessaging(for: selectedProduct) {
        case .trial(let days):
            if let days {
                return session.t(.paywallRenewalLegalTrialDays, days)
            }
            return session.t(.paywallRenewalLegalTrial)
        default:
            return session.t(.paywallRenewalLegalStandard)
        }
    }

    private func localizedStatus(_ status: EntitlementUserStatus) -> String? {
        switch status {
        case .idle: nil
        case .cancelled: session.t(.paywallPurchaseCancelled)
        case .pending: session.t(.paywallPurchasePending)
        case .unknownState: session.t(.paywallPurchaseUnknown)
        case .restored: session.t(.paywallRestoreSuccess)
        case .restoredDebug: session.t(.paywallRestoreDebug)
        case .restoreEmpty: session.t(.paywallRestoreEmpty)
        case .debugUnlocked: session.t(.paywallDebugNote)
        case .system(let message): message
        }
    }

    private func period(for product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .year: session.t(.paywallPerYear)
        case .month: session.t(.paywallPerMonth)
        default: ""
        }
    }
}

struct OnboardingSuperTrialView: View {
    var onFinished: () -> Void

    var body: some View {
        NavigationStack {
            PaywallView(onClose: onFinished)
        }
    }
}
