#if DEBUG
import Foundation

/// O4 Super trial / paywall hygiene. No DoseLoop, no medication fixtures.
enum SuperTrialContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        expect(
            !SuperAcquisitionPolicy.homePresentsPaywallAutomatically,
            "O4: Home does not auto-present a paywall"
        )
        expect(
            SuperAcquisitionPolicy.skipOnboardingTrial(isSuper: true),
            "O4: Super skips onboarding acquisition"
        )
        expect(
            !SuperAcquisitionPolicy.skipOnboardingTrial(isSuper: false),
            "O4: Free users still reach onboarding acquisition"
        )
        expect(
            !SuperAcquisitionPolicy.grantsSuper(from: .eligible)
                && !SuperAcquisitionPolicy.grantsSuper(from: .ineligible)
                && !SuperAcquisitionPolicy.grantsSuper(from: .unknown),
            "O4: eligibility never grants Super"
        )

        expect(
            SuperAcquisitionPolicy.introEligibility(
                settled: false,
                eligibleProductIDs: [],
                productID: SuperProductID.yearly
            ) == .unknown,
            "O4: empty product-ID set before refresh is unknown, not ineligible"
        )
        expect(
            SuperAcquisitionPolicy.introEligibility(
                settled: true,
                eligibleProductIDs: [SuperProductID.yearly],
                productID: SuperProductID.yearly
            ) == .eligible,
            "O4: settled eligible product is eligible"
        )
        expect(
            SuperAcquisitionPolicy.introEligibility(
                settled: true,
                eligibleProductIDs: [],
                productID: SuperProductID.yearly
            ) == .ineligible,
            "O4: settled empty set is ineligible"
        )

        expect(
            SuperAcquisitionPolicy.confirmedTrialDays(unit: .day, value: 3) == 3,
            "O4: 3-day intro maps to 3 days"
        )
        expect(
            SuperAcquisitionPolicy.confirmedTrialDays(unit: .week, value: 1) == 7,
            "O4: week intro maps to days"
        )
        expect(
            SuperAcquisitionPolicy.confirmedTrialDays(unit: .month, value: 1) == nil,
            "O4: month intro has no assumed day count"
        )

        expect(
            SuperAcquisitionPolicy.messaging(
                entitlementSettled: false,
                eligibilitySettled: false,
                productsMissing: false,
                eligibility: .unknown,
                trialDays: nil
            ) == .checking,
            "O4: unknown/loading uses neutral checking copy"
        )
        expect(
            SuperAcquisitionPolicy.messaging(
                entitlementSettled: true,
                eligibilitySettled: true,
                productsMissing: false,
                eligibility: .eligible,
                trialDays: 3
            ) == .trial(days: 3),
            "O4: eligible uses trial messaging"
        )
        expect(
            SuperAcquisitionPolicy.messaging(
                entitlementSettled: true,
                eligibilitySettled: true,
                productsMissing: false,
                eligibility: .ineligible,
                trialDays: 3
            ) == .standard,
            "O4: ineligible uses standard Super messaging"
        )
        expect(
            SuperAcquisitionPolicy.messaging(
                entitlementSettled: true,
                eligibilitySettled: true,
                productsMissing: true,
                eligibility: .ineligible,
                trialDays: nil
            ) == .missingProducts,
            "O4: missing products do not claim a trial"
        )

        let returning = OnboardingWelcomeRouting.Input(
            hasChosenLanguage: true,
            hasAcknowledgedPrivacy: true,
            hasCompletedSignInThisInstall: true,
            isSessionUnlocked: true,
            hasSeenWelcome: false,
            hasCareContext: false,
            hasCompletedOnboarding: true,
            isReturningAuthenticated: true,
            needsIdentityProfile: false,
            userDataSettled: true
        )
        expect(
            OnboardingWelcomeRouting.hostPhase(returning) == .home,
            "O4: returning users do not replay acquisition"
        )

        expect(
            SuperProductID.monthly == "com.checkmed.super.monthly"
                && SuperProductID.yearly == "com.checkmed.super.yearly",
            "O4: StoreKit product IDs unchanged"
        )
        expect(
            SuperLimits.freePrescriptions == 3
                && SuperLimits.superPrescriptions == 12,
            "O4: existing Free/Super creation limits remain 3/12"
        )
        expect(
            !DebugSuperUnlockPolicy.restoresPersistedUnlock(true, isDebugBuild: false),
            "O4: Release ignores a persisted DEBUG unlock"
        )
        expect(
            DebugSuperUnlockPolicy.restoresPersistedUnlock(true, isDebugBuild: true),
            "O4: DEBUG may restore its test unlock"
        )
        expect(
            !DebugSuperUnlockPolicy.restoresPersistedUnlock(false, isDebugBuild: true),
            "O4: DEBUG does not invent an unlock without the persisted flag"
        )

        let formatKeys: Set<L10n.Key> = [
            .paywallStartTrialDays,
            .paywallStartTrialDay,
            .paywallTrialAccentDays,
            .paywallTrialAccentDay,
            .paywallRenewalLegalTrialDays,
        ]
        let gateKeys: [L10n.Key] = [
            .treatmentsTrySuper,
            .scanLimitStartTrial,
            .confirmFreePlanFull,
            .treatmentsSlotsFull,
        ]
        let required: [L10n.Key] = formatKeys.sorted { $0.rawValue < $1.rawValue } + gateKeys + [
            .paywallCheckingOffer,
            .paywallStandardLead,
            .paywallStandardBody,
            .paywallStartTrialGeneric,
            .paywallRenewalLegalTrial,
            .paywallRenewalLegalStandard,
            .paywallPurchaseCancelled,
            .paywallPurchasePending,
            .paywallPurchaseUnknown,
            .paywallRestoreSuccess,
            .paywallRestoreDebug,
            .paywallRestoreEmpty,
            .onboardingTrialOfferChecking,
            .onboardingTrialOfferStandard,
            .paywallSuper10,
            .refillSuperBody,
            .paywallRestore,
            .termsOfUseTitle,
            .privacyPolicyTitle,
        ]

        for locale in AppLocale.allCases {
            for key in required {
                let value = L10n.string(key, locale: locale)
                expect(!value.isEmpty, "O4: \(key) localized for \(locale.rawValue)")
                if formatKeys.contains(key) {
                    expect(value.contains("%d"), "O4: \(key) keeps format placeholder (\(locale.rawValue))")
                } else {
                    expect(!value.contains("%d") && !value.contains("%@"), "O4: \(key) has no raw placeholder (\(locale.rawValue))")
                }
            }
            for key in gateKeys {
                let lower = L10n.string(key, locale: locale).lowercased()
                expect(
                    !lower.contains("3 day")
                        && !lower.contains("3 dia")
                        && !lower.contains("3 día")
                        && !lower.contains("3 jour"),
                    "O4: \(key) has no unconditional 3-day trial claim (\(locale.rawValue))"
                )
            }
            let super10 = L10n.string(.paywallSuper10, locale: locale).lowercased()
            expect(
                super10.contains("alarm") || super10.contains("alarme") || super10.contains("alarma"),
                "O4: Super10 advertises alarm theme, not free refill (\(locale.rawValue))"
            )
            let refill = L10n.string(.refillSuperBody, locale: locale).lowercased()
            expect(
                refill.contains("pharmac") || refill.contains("farmá") || refill.contains("farmac"),
                "O4: Refill Super card still offers pharmacy search (\(locale.rawValue))"
            )
        }

        return failures
    }
}
#endif
