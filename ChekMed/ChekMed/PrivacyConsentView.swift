import SwiftUI

/// Destinations presented from privacy onboarding (own stack, not the main app path).
private enum PrivacyOnboardingRoute: Hashable {
    case settings
    case document(LegalDocumentKind)
}

/// Privacy / consent in first-time onboarding (after How it works). Accept stores
/// policy/terms acknowledgement only — never optional analytics or marketing.
struct PrivacyConsentView: View {
    @Environment(SessionStore.self) private var session
    var onAccept: () -> Void

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    privacyMain
                }
                .scrollBounceBehavior(.basedOnSize)

                footerActions
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CheckMedTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PrivacyOnboardingRoute.self) { route in
                switch route {
                case .settings:
                    PrivacySettingsView()
                case .document(let kind):
                    LegalDocumentView(kind: kind)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.t(.privacyHeadline))
    }

    private var privacyMain: some View {
        VStack(spacing: 12) {
            PhilView(size: 80, mood: .idle, pose: .pointingDown, smiling: true)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(session.t(.privacyHeadline))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CheckMedTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(session.t(.privacySubhead))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
            }

            Text(session.t(.privacyBody))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                PrivacyInfoCard(
                    icon: "list.bullet.clipboard.fill",
                    title: session.t(.privacyHowTitle),
                    message: session.t(.privacyHowBody)
                )
                PrivacyInfoCard(
                    icon: "slider.horizontal.3",
                    title: session.t(.privacyControlTitle),
                    message: session.t(.privacyControlBody)
                )
                PrivacyInfoCard(
                    icon: "doc.text.magnifyingglass",
                    title: session.t(.privacyTransparentTitle),
                    message: session.t(.privacyTransparentBody)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var footerActions: some View {
        VStack(spacing: 8) {
            CheckMedButton(title: session.t(.privacyAccept)) {
                session.acknowledgePrivacy()
                onAccept()
            }
            .accessibilityLabel(session.t(.privacyAccept))
            .accessibilityHint(session.t(.privacyAcceptHint))

            CheckMedButton(title: session.t(.privacySettingsButton), style: .secondary) {
                path.append(PrivacyOnboardingRoute.settings)
            }
            .accessibilityLabel(session.t(.privacySettingsButton))
            .accessibilityHint(session.t(.privacySettingsHint))

            privacyFooter
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .background(CheckMedTheme.background)
    }

    private var privacyFooter: some View {
        Text(LocalizedStringKey(session.t(.privacyFooter)))
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(CheckMedTheme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .tint(CheckMedTheme.primaryShadow)
            .environment(\.openURL, OpenURLAction { url in
                openLegal(url)
            })
            .accessibilityAddTraits(.isStaticText)
    }

    private func openLegal(_ url: URL) -> OpenURLAction.Result {
        switch url.host {
        case "privacy":
            path.append(PrivacyOnboardingRoute.document(.privacyPolicy))
            return .handled
        case "terms":
            path.append(PrivacyOnboardingRoute.document(.termsOfUse))
            return .handled
        default:
            return .discarded
        }
    }
}

private struct PrivacyInfoCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CheckMedTheme.belly)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .symbolRenderingMode(.monochrome)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
    }
}

struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    private var document: LegalDocument { kind.document }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(document.lastUpdatedLine)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)

                ForEach(document.blocks) { block in
                    switch block.kind {
                    case .heading:
                        Text(block.title)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                            .padding(.top, 4)
                            .accessibilityAddTraits(.isHeader)
                    case .paragraph:
                        Text(block.body)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    case .labeled:
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.title)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                            if !block.body.isEmpty {
                                Text(block.body)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                            }
                        }
                        .foregroundStyle(CheckMedTheme.ink)
                    case .stacked:
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(block.lines, id: \.self) { line in
                                Text(line)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                            }
                        }
                        .foregroundStyle(CheckMedTheme.ink)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel(document.title)
    }
}

/// Consent management. Required processing stays on; optional analytics and
/// marketing stay off unless the user turns them on here — never via Accept.
///
/// Lawyer TODOs live in `LegalContent.swift` (legal basis, health-data condition,
/// consent wording, retention, AI providers, international transfers, analytics,
/// marketing, medical-device classification, user age, data deletion, policy URL,
/// terms wording). Categories are structured so those answers can be wired later
/// without changing Accept.
struct PrivacySettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    PhilView(size: 72, pose: .idle, smiling: true)
                        .accessibilityHidden(true)
                    Text(session.t(.privacySettingsIntro))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                categoryCard(
                    title: session.t(.privacyRequiredTitle),
                    message: session.t(.privacyRequiredBody),
                    badge: session.t(.privacyAlwaysOn)
                ) {
                    Toggle(isOn: .constant(true)) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .disabled(true)
                    .tint(CheckMedTheme.primary)
                    .accessibilityLabel(session.t(.privacyRequiredTitle))
                    .accessibilityValue(session.t(.privacyAlwaysOn))
                    .accessibilityHint(session.t(.privacyRequiredHint))
                }

                categoryCard(
                    title: session.t(.privacyAnalyticsTitle),
                    message: session.t(.privacyAnalyticsBody),
                    badge: session.t(.privacyOptional)
                ) {
                    Toggle(
                        isOn: Binding(
                            get: { session.optionalAnalyticsEnabled },
                            set: { session.setOptionalAnalyticsEnabled($0) }
                        )
                    ) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .tint(CheckMedTheme.primary)
                    .accessibilityLabel(session.t(.privacyAnalyticsTitle))
                    .accessibilityHint(session.t(.privacyAnalyticsHint))
                }

                categoryCard(
                    title: session.t(.privacyMarketingTitle),
                    message: session.t(.privacyMarketingBody),
                    badge: session.t(.privacyOptional)
                ) {
                    Toggle(
                        isOn: Binding(
                            get: { session.optionalMarketingEnabled },
                            set: { session.setOptionalMarketingEnabled($0) }
                        )
                    ) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .tint(CheckMedTheme.primary)
                    .accessibilityLabel(session.t(.privacyMarketingTitle))
                    .accessibilityHint(session.t(.privacyMarketingHint))
                }

                NavigationLink {
                    LegalDocumentView(kind: .privacyPolicy)
                } label: {
                    legalRow(session.t(.privacyPolicyTitle))
                }
                .frame(minHeight: 44)

                NavigationLink {
                    LegalDocumentView(kind: .termsOfUse)
                } label: {
                    legalRow(session.t(.termsOfUseTitle))
                }
                .frame(minHeight: 44)
            }
            .padding(20)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.privacySettingsTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryCard<Accessory: View>(
        title: String,
        message: String,
        badge: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(badge)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(CheckMedTheme.muted)
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                accessory()
                    .frame(minWidth: 44, minHeight: 44)
            }
            Text(message)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
    }

    private func legalRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CheckMedTheme.muted)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
        )
    }
}
