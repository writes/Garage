import Observation
import RevenueCat

@MainActor
@Observable
final class PurchaseService {
    private enum Mode {
        case live
        case uiTest
    }

    static let shared = PurchaseService()
    static let uiTest = PurchaseService(mode: .uiTest, isPro: AppRuntime.isUITestPro)

    private(set) var isPro = false
    private(set) var offerings: Offerings?
    private let mode: Mode
    private let identityReady: @MainActor () async -> String?
    private let customerInfoOverride: (@MainActor () async throws -> CustomerInfo)?
    private let purchaseOverride: (@MainActor () async throws -> CustomerInfo)?
    private let restorePurchasesOverride: (@MainActor () async throws -> Bool)?

    private init(mode: Mode = .live, isPro: Bool = false) {
        self.mode = mode
        self.isPro = isPro
        identityReady = { await AuthService.shared.waitForPurchasesIdentity() }
        customerInfoOverride = nil
        purchaseOverride = nil
        restorePurchasesOverride = nil
    }

#if DEBUG
    init(
        testIsPro: Bool,
        restorePurchasesOverride: (@MainActor () async throws -> Bool)? = nil,
        identityReady: (@MainActor () async -> String?)? = nil,
        customerInfoOverride: (@MainActor () async throws -> CustomerInfo)? = nil,
        purchaseOverride: (@MainActor () async throws -> CustomerInfo)? = nil
    ) {
        mode = customerInfoOverride == nil && purchaseOverride == nil && restorePurchasesOverride == nil
            ? .uiTest
            : .live
        isPro = testIsPro
        self.identityReady = identityReady ?? { "test-user" }
        self.customerInfoOverride = customerInfoOverride
        self.purchaseOverride = purchaseOverride
        self.restorePurchasesOverride = restorePurchasesOverride
    }
#endif

    func checkSubscriptionStatus() async {
        guard mode == .live else { return }
        guard await identityReady() != nil else { return }

        do {
            let customerInfo: CustomerInfo
            if let customerInfoOverride {
                customerInfo = try await customerInfoOverride()
            } else {
                customerInfo = try await Purchases.shared.customerInfo()
            }
            apply(customerInfo)
        } catch {
            AppLogger.purchase.error("Failed to check subscription: \(error.localizedDescription)")
        }
    }

    func fetchOfferings() async {
        guard mode == .live else { return }

        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            AppLogger.purchase.error("Failed to fetch offerings: \(error.localizedDescription)")
        }
    }

    func purchase(_ package: Package) async throws {
        try await performPurchase {
            let result = try await Purchases.shared.purchase(package: package)
            return result.customerInfo
        }
    }

    func restorePurchases() async throws {
        guard mode == .live else {
            throw AppError.subscriptionRequired("Purchases unavailable in UI tests")
        }
        guard await identityReady() != nil else {
            throw AppError.auth("Subscription identity is not ready")
        }

        if let restorePurchasesOverride {
            isPro = try await restorePurchasesOverride()
            return
        }

        let customerInfo = try await Purchases.shared.restorePurchases()
        apply(customerInfo)
    }

    func apply(_ customerInfo: CustomerInfo) {
        isPro = customerInfo.entitlements["pro"]?.isActive == true
    }

    private func performPurchase(_ purchase: @MainActor () async throws -> CustomerInfo) async throws {
        guard mode == .live else {
            throw AppError.subscriptionRequired("Purchases unavailable in UI tests")
        }
        guard await identityReady() != nil else {
            throw AppError.auth("Subscription identity is not ready")
        }

        apply(try await purchase())
    }

#if DEBUG
    func purchaseForTesting() async throws {
        guard let purchaseOverride else {
            throw AppError.subscriptionRequired("Purchases unavailable in UI tests")
        }

        try await performPurchase(purchaseOverride)
    }
#endif
}
