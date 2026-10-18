import Foundation
import StoreKit

enum SuperProductID {
    static let monthly = "com.checkmed.super.monthly"
    static let yearly = "com.checkmed.super.annual"
    static var all: Set<String> { [monthly, yearly] }
}

enum DebugSuperUnlockPolicy {
    static func restoresPersistedUnlock(_ persisted: Bool, isDebugBuild: Bool) -> Bool {
        persisted && isDebugBuild
    }
}

@MainActor
@Observable
final class EntitlementStore {
    var showPaywall = false
    /// Super already at the 12-medicine technical ceiling. Not a paywall.
    var showSuperMedicineCeiling = false

    private(set) var isSuper = false
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var userStatus: EntitlementUserStatus = .idle
    private(set) var usedDebugUnlock = false
    private(set) var introEligibleProductIDs: Set<String> = []
    private(set) var introEligibilitySettled = false
    private(set) var entitlementSettled = false

    var freeFamilySlots: Int { 1 }
    var familySlots: Int { isSuper ? 2 : freeFamilySlots }
    var extraFamilySlotUnlocked: Bool { isSuper }
    var canChooseAlarmTheme: Bool { isSuper }
    var canUseVoiceReading: Bool { isSuper }
    var canUseAdvanceReminder: Bool { isSuper }
    /// Share/export PDF for reports (browse/view/edit stays free).
    var canViewJourneyReport: Bool { isSuper }
    /// MapKit pharmacy search only (screen + map UI stay free).
    var canSearchPharmacies: Bool { isSuper }
    var canUseRefillReminder: Bool { true }

    var monthlyProduct: Product? { products.first { $0.id == SuperProductID.monthly } }
    var yearlyProduct: Product? { products.first { $0.id == SuperProductID.yearly } }

    func introEligibility(for product: Product) -> SuperIntroEligibility {
        SuperAcquisitionPolicy.introEligibility(
            settled: introEligibilitySettled,
            eligibleProductIDs: introEligibleProductIDs,
            productID: product.id
        )
    }

    func isEligibleForFreeTrial(_ product: Product) -> Bool {
        introEligibility(for: product) == .eligible
    }

    func introTrialDayCount(for product: Product) -> Int? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let unit: SuperTrialPeriodUnit
        switch offer.period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: return nil
        }
        return SuperAcquisitionPolicy.confirmedTrialDays(unit: unit, value: offer.period.value)
    }

    func acquisitionMessaging(for product: Product?) -> SuperAcquisitionMessaging {
        let eligibility: SuperIntroEligibility
        let days: Int?
        if let product {
            eligibility = introEligibility(for: product)
            days = introTrialDayCount(for: product)
        } else if !introEligibilitySettled || !entitlementSettled {
            eligibility = .unknown
            days = nil
        } else {
            eligibility = .ineligible
            days = nil
        }
        return SuperAcquisitionPolicy.messaging(
            entitlementSettled: entitlementSettled,
            eligibilitySettled: introEligibilitySettled,
            productsMissing: introEligibilitySettled && products.isEmpty,
            eligibility: eligibility,
            trialDays: days
        )
    }

    var allowsDebugUnlock: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private enum Keys {
        static let debugUnlock = "checkmed.super.debugUnlock"
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    init() {
        #if DEBUG
        if IntakeVerify.shouldIsolateProcess && !TH1LocalVerification.shouldIsolateProcess {
            isSuper = false
            usedDebugUnlock = false
            entitlementSettled = true
            introEligibilitySettled = true
            return
        }
        #endif
        let persistedDebugUnlock = UserDefaults.standard.bool(forKey: Keys.debugUnlock)
        usedDebugUnlock = DebugSuperUnlockPolicy.restoresPersistedUnlock(
            persistedDebugUnlock,
            isDebugBuild: Self.isDebugBuild
        )
        if persistedDebugUnlock && !usedDebugUnlock {
            UserDefaults.standard.removeObject(forKey: Keys.debugUnlock)
        }
        if usedDebugUnlock {
            isSuper = true
            entitlementSettled = true
        }
        Task { await refresh() }
        Task { await listenForTransactions() }
    }

    func presentPaywall() {
        showPaywall = true
    }

    func refresh() async {
        isLoading = true
        userStatus = .idle
        introEligibilitySettled = false
        await loadProducts()
        await refreshIntroEligibility()
        await updateEntitlementFromStore()
        entitlementSettled = true
        isLoading = false
    }

    func purchase(_ product: Product) async {
        isLoading = true
        userStatus = .idle
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateEntitlementFromStore()
                await refreshIntroEligibility()
                if isSuper { showPaywall = false }
            case .userCancelled:
                userStatus = .cancelled
            case .pending:
                userStatus = .pending
            @unknown default:
                userStatus = .unknownState
            }
        } catch {
            userStatus = .system(error.localizedDescription)
        }
        isLoading = false
    }

    func restore() async {
        isLoading = true
        userStatus = .idle
        do {
            try await AppStore.sync()
        } catch {
            userStatus = .system(error.localizedDescription)
            isLoading = false
            return
        }
        await updateEntitlementFromStore()
        await refreshIntroEligibility()
        if isSuper && !usedDebugUnlock {
            userStatus = .restored
            showPaywall = false
        } else if usedDebugUnlock {
            userStatus = .restoredDebug
        } else {
            userStatus = .restoreEmpty
        }
        isLoading = false
    }

    func unlockForDevelopment() {
        guard allowsDebugUnlock else { return }
        usedDebugUnlock = true
        isSuper = true
        entitlementSettled = true
        UserDefaults.standard.set(true, forKey: Keys.debugUnlock)
        userStatus = .debugUnlocked
        showPaywall = false
    }

    func clearDebugUnlock() {
        usedDebugUnlock = false
        UserDefaults.standard.removeObject(forKey: Keys.debugUnlock)
        Task { await updateEntitlementFromStore() }
    }

    private func loadProducts() async {
        do {
            products = try await Product.products(for: SuperProductID.all)
                .sorted { $0.price < $1.price }
        } catch {
            products = []
            introEligibleProductIDs = []
        }
    }

    private func refreshIntroEligibility() async {
        var eligible: Set<String> = []
        for product in products {
            guard let subscription = product.subscription,
                  let offer = subscription.introductoryOffer,
                  offer.paymentMode == .freeTrial else { continue }
            if await subscription.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        introEligibleProductIDs = eligible
        introEligibilitySettled = true
    }

    private func updateEntitlementFromStore() async {
        var hasStoreEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if SuperProductID.all.contains(transaction.productID) {
                hasStoreEntitlement = true
                break
            }
        }
        isSuper = hasStoreEntitlement || usedDebugUnlock
        entitlementSettled = true
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if let transaction = try? checkVerified(update) {
                await transaction.finish()
                await updateEntitlementFromStore()
                await refreshIntroEligibility()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
