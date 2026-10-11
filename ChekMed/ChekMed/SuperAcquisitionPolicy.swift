import Foundation

/// Intro-offer eligibility is distinct from Super entitlement.
/// An empty product-ID set is not ineligible until refresh has settled.
enum SuperIntroEligibility: Equatable {
    case unknown
    case eligible
    case ineligible
}

enum SuperTrialPeriodUnit: Equatable {
    case day
    case week
    case month
    case year
}

enum SuperAcquisitionMessaging: Equatable {
    case checking
    case trial(days: Int?)
    case standard
    case missingProducts
}

/// Pure acquisition rules. Does not grant Super and does not call StoreKit.
enum SuperAcquisitionPolicy {
    /// Home must not auto-present PaywallView. Feature gates still call `presentPaywall()`.
    static let homePresentsPaywallAutomatically = false

    static func skipOnboardingTrial(isSuper: Bool) -> Bool { isSuper }

    static func grantsSuper(from eligibility: SuperIntroEligibility) -> Bool { false }

    static func introEligibility(
        settled: Bool,
        eligibleProductIDs: Set<String>,
        productID: String
    ) -> SuperIntroEligibility {
        guard settled else { return .unknown }
        return eligibleProductIDs.contains(productID) ? .eligible : .ineligible
    }

    /// Day/week intro periods can be shown as a day count. Longer units stay neutral.
    static func confirmedTrialDays(unit: SuperTrialPeriodUnit, value: Int) -> Int? {
        guard value > 0 else { return nil }
        switch unit {
        case .day: return value
        case .week: return value * 7
        case .month, .year: return nil
        }
    }

    static func messaging(
        entitlementSettled: Bool,
        eligibilitySettled: Bool,
        productsMissing: Bool,
        eligibility: SuperIntroEligibility,
        trialDays: Int?
    ) -> SuperAcquisitionMessaging {
        if !entitlementSettled || !eligibilitySettled || eligibility == .unknown {
            return .checking
        }
        if productsMissing {
            return .missingProducts
        }
        if eligibility == .eligible {
            return .trial(days: trialDays)
        }
        return .standard
    }
}

enum EntitlementUserStatus: Equatable {
    case idle
    case cancelled
    case pending
    case unknownState
    case restored
    case restoredDebug
    case restoreEmpty
    case debugUnlocked
    case system(String)
}
