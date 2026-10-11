import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var onClose: (() -> Void)? = nil

    @State private var selectedProductID = SuperProductID.yearly

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
                    philHero
                    planPicker
                    includesCard
                    trustRow
                    statusBlock
                    cta
                    legalFooter
                }
                extraActions
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
        .onChange(of: entitlements.isSuper) { _, isSuper in
            if isSuper, onClose != nil {
                close()
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
            .accessibilityLabel(session.t(.paywallClose))
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
        case .missingProducts:
            Text(session.t(.paywallStandardLead))
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundStyle(CheckMedTheme.ink)
        case .standard:
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

    private var philHero: some View {
        PhilView(size: 132, mood: .idle, smiling: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
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
        }
        if let status = localizedStatus(entitlements.userStatus) {
            Text(status)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.safety)
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
                .disabled(entitlements.isLoading || entitlements.introEligibility(for: selectedProduct) == .unknown)
            }
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
            PhilView(size: 96, mood: .celebrate, smiling: true)
            SpeechBubbleView(
                text: entitlements.usedDebugUnlock
                    ? session.t(.paywallDebugNote)
                    : session.t(.paywallOnBubble)
            )
            Text(session.t(.paywallActive))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.superAccent)
        }
    }

    private var extraActions: some View {
        VStack(spacing: 8) {
            if !entitlements.isSuper {
                CheckMedButton(title: session.t(.paywallRestore), style: .secondary) {
                    Task { await entitlements.restore() }
                }
                .disabled(entitlements.isLoading)
                CheckMedButton(title: session.t(.paywallNotNow), style: .ghost, action: close)
            }
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
            SafetyCaption()
                .frame(maxWidth: .infinity)
        }
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
        case .checking:
            return session.t(.paywallRenewalLegalStandard)
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
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements

    var onFinished: () -> Void
    @State private var didFinish = false

    private var trialProduct: Product? {
        entitlements.yearlyProduct ?? entitlements.monthlyProduct
    }

    private var messaging: SuperAcquisitionMessaging {
        entitlements.acquisitionMessaging(for: trialProduct)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x3184EE), Color(hex: 0x3258D4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                trialStars

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        closeRow
                        Text(offerTitle)
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)

                        TrialPhilCrowd()
                            .frame(height: 240)

                        offerDetails
                        if let status = localizedStatus(entitlements.userStatus) {
                            Text(status)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }
                        actions
                        legalFooter
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await entitlements.refresh()
            if entitlements.isSuper { finishOnce() }
        }
        .onChange(of: entitlements.isSuper) { _, isSuper in
            if isSuper { finishOnce() }
        }
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }

    private var offerTitle: String {
        switch messaging {
        case .checking: session.t(.onboardingTrialOfferChecking)
        case .trial: session.t(.onboardingTrialOffer)
        case .standard, .missingProducts: session.t(.onboardingTrialOfferStandard)
        }
    }

    private var closeRow: some View {
        HStack {
            Button(action: finishOnce) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.paywallNotNow))
            Spacer()
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var offerDetails: some View {
        VStack(spacing: 4) {
            switch messaging {
            case .checking:
                Text(session.t(.paywallCheckingOffer))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
            case .missingProducts:
                Text(session.t(.paywallProductsMissing))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
            case .standard:
                Text(session.t(.paywallStandardLead))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                if let trialProduct {
                    Text("\(trialProduct.displayPrice) \(period(for: trialProduct))")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
            case .trial(let days):
                Text(trialAccent(days: days))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                if let trialProduct {
                    Text(session.t(.paywallThenContinue, "\(trialProduct.displayPrice) \(period(for: trialProduct))"))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                guard let trialProduct else { return }
                Task { await entitlements.purchase(trialProduct) }
            } label: {
                HStack(spacing: 8) {
                    if entitlements.isLoading {
                        ProgressView()
                            .tint(Color(hex: 0x2F68DC))
                    }
                    Text(primaryTitle)
                }
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Color(hex: 0x2F68DC))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.16), radius: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(purchaseDisabled)
            .opacity(trialProduct == nil || messaging == .checking ? 0.65 : 1)

            Button(session.t(.paywallRestore)) {
                Task { await entitlements.restore() }
            }
            .font(.system(.body, design: .rounded).weight(.heavy))
            .foregroundStyle(.white)
            .disabled(entitlements.isLoading)

            Button(session.t(.paywallNotNow), action: finishOnce)
                .font(.system(.body, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .padding(.vertical, 8)
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text(renewalLegalText)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
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
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private var purchaseDisabled: Bool {
        guard let trialProduct else { return true }
        if entitlements.isLoading { return true }
        return entitlements.introEligibility(for: trialProduct) == .unknown
    }

    private var primaryTitle: String {
        guard let trialProduct else { return session.t(.paywallCheckingOffer) }
        switch entitlements.introEligibility(for: trialProduct) {
        case .eligible:
            if let days = entitlements.introTrialDayCount(for: trialProduct) {
                return days == 1
                    ? session.t(.paywallStartTrialDay, days)
                    : session.t(.paywallStartTrialDays, days)
            }
            return session.t(.paywallStartTrialGeneric)
        case .ineligible:
            return session.t(.paywallStartPlan, session.t(.paywallSuper), trialProduct.displayPrice)
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
        switch messaging {
        case .trial(let days):
            if let days { return session.t(.paywallRenewalLegalTrialDays, days) }
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

    private var trialStars: some View {
        GeometryReader { proxy in
            ZStack {
                Circle().fill(.white.opacity(0.85)).frame(width: 5, height: 5)
                    .position(x: proxy.size.width * 0.13, y: 45)
                Circle().fill(.white.opacity(0.55)).frame(width: 7, height: 7)
                    .position(x: proxy.size.width * 0.74, y: 24)
                Circle().fill(.white.opacity(0.8)).frame(width: 4, height: 4)
                    .position(x: proxy.size.width * 0.91, y: 116)
                Circle().fill(.white.opacity(0.45)).frame(width: 6, height: 6)
                    .position(x: proxy.size.width * 0.08, y: proxy.size.height * 0.48)
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(x: proxy.size.width * 0.89, y: proxy.size.height * 0.37)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func period(for product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .year: session.t(.paywallPerYear)
        case .month: session.t(.paywallPerMonth)
        default: ""
        }
    }
}

private struct TrialPhilCrowd: View {
    var body: some View {
        ZStack {
            crowdGlow
            characterBubble(color: CheckMedTheme.sunshineWash, size: 84) {
                PhilGlassesImage(size: 72)
            }
            .offset(x: -92, y: -48)

            characterBubble(color: CheckMedTheme.mintWash, size: 88) {
                PhilView(size: 67, smiling: true)
            }
            .offset(x: 0, y: -68)

            characterBubble(color: CheckMedTheme.lavenderWash, size: 84) {
                PhilThinkingImage(size: 72)
            }
            .offset(x: 92, y: -44)

            characterBubble(color: CheckMedTheme.blueWash, size: 92) {
                PhilDoctor2DImage(size: 78)
            }
            .offset(x: -76, y: 49)

            characterBubble(color: CheckMedTheme.sunshineWash, size: 96) {
                PhilReadingImage(size: 82)
            }
            .offset(x: 18, y: 50)

            characterBubble(color: CheckMedTheme.mintWash, size: 88) {
                Image("phil_doctor")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 75, height: 75)
                    .accessibilityHidden(true)
            }
            .offset(x: 103, y: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cooper")
    }

    private var crowdGlow: some View {
        Ellipse()
            .fill(.white.opacity(0.13))
            .frame(width: 330, height: 210)
            .overlay(
                Ellipse()
                    .stroke(.white.opacity(0.18), lineWidth: 2)
                    .padding(18)
            )
    }

    private func characterBubble<Content: View>(
        color: Color,
        size: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Circle().fill(color)
            content()
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white, lineWidth: 4))
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 5)
    }
}
