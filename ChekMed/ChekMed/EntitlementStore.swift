import Foundation
import StoreKit

enum SuperProductID {
    static let monthly = "com.checkmed.super.monthly"
    static let yearly = "com.checkmed.super.yearly"
    static var all: Set<String> { [monthly, yearly] }
}

@MainActor
@Observable
final class EntitlementStore {
    var showPaywall = false

    private(set) var isSuper = false
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var statusMessage: String?
    private(set) var usedDebugUnlock = false
    private(set) var introEligibleProductIDs: Set<String> = []

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

    func isEligibleForFreeTrial(_ product: Product) -> Bool {
        introEligibleProductIDs.contains(product.id)
    }

    var allowsDebugUnlock: Bool {
        #if targetEnvironment(simulator)
        true
        #elseif DEBUG
        true
        #else
        false
        #endif
    }

    private enum Keys {
        static let debugUnlock = "checkmed.super.debugUnlock"
    }

    init() {
        usedDebugUnlock = UserDefaults.standard.bool(forKey: Keys.debugUnlock)
        if usedDebugUnlock { isSuper = true }
        Task { await refresh() }
        Task { await listenForTransactions() }
    }

    func presentPaywall() {
        showPaywall = true
    }

    func refresh() async {
        isLoading = true
        statusMessage = nil
        await loadProducts()
        await refreshIntroEligibility()
        await updateEntitlementFromStore()
        isLoading = false
    }

    func purchase(_ product: Product) async {
        isLoading = true
        statusMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateEntitlementFromStore()
                if isSuper { showPaywall = false }
            case .userCancelled:
                statusMessage = "No charge. You can stay on Free — Taken and the first treatment stay open."
            case .pending:
                statusMessage = "That purchase is pending. Super unlocks after Apple confirms it."
            @unknown default:
                statusMessage = "Apple returned an unknown purchase state."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
        isLoading = false
    }

    func restore() async {
        isLoading = true
        statusMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            statusMessage = error.localizedDescription
            isLoading = false
            return
        }
        await updateEntitlementFromStore()
        if isSuper && !usedDebugUnlock {
            statusMessage = "Super is restored for this Apple ID."
            showPaywall = false
        } else if usedDebugUnlock {
            statusMessage = "Simulator unlock is on. That is not an App Store charge."
        } else {
            statusMessage = "No Super on this Apple ID yet. In Xcode, select Products.storekit on the scheme to try monthly/yearly. For TestFlight or the store, create those products in App Store Connect."
        }
        isLoading = false
    }

    func unlockForDevelopment() {
        guard allowsDebugUnlock else { return }
        usedDebugUnlock = true
        isSuper = true
        UserDefaults.standard.set(true, forKey: Keys.debugUnlock)
        statusMessage = "Unlocked Super on this simulator or debug build. Not a live Apple charge."
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
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if let transaction = try? checkVerified(update) {
                await transaction.finish()
                await updateEntitlementFromStore()
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
