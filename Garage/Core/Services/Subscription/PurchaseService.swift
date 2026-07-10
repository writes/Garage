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
    static let uiTest = PurchaseService(mode: .uiTest)

    private(set) var isPro = false
    private(set) var offerings: Offerings?
    private let mode: Mode

    private init(mode: Mode = .live) {
        self.mode = mode
    }

    init(testIsPro: Bool) {
        mode = .uiTest
        isPro = testIsPro
    }

    func checkSubscriptionStatus() async {
        guard mode == .live else { return }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            isPro = customerInfo.entitlements["pro"]?.isActive == true
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
        guard mode == .live else {
            throw AppError.subscriptionRequired("Purchases unavailable in UI tests")
        }

        let result = try await Purchases.shared.purchase(package: package)
        isPro = result.customerInfo.entitlements["pro"]?.isActive == true
    }

    func restorePurchases() async throws {
        guard mode == .live else {
            throw AppError.subscriptionRequired("Purchases unavailable in UI tests")
        }

        let customerInfo = try await Purchases.shared.restorePurchases()
        isPro = customerInfo.entitlements["pro"]?.isActive == true
    }
}
