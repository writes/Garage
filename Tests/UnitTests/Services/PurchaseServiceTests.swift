import RevenueCat
import Testing
@testable import Garage

@MainActor
struct PurchaseServiceTests {
    @Test func restorePurchases_callsTheInjectedRestorePathAndRefreshesEntitlement() async throws {
        let probe = RestorePurchasesProbe()
        let service = PurchaseService(
            testIsPro: false,
            restorePurchasesOverride: probe.restore
        )

        try await service.restorePurchases()

        #expect(probe.calls == 1)
        #expect(service.isPro)
    }

    @Test func annualDisclosureIncludesLocalizedPriceDurationAndRenewal() {
        let disclosure = SubscriptionDisclosure.renewalTerms(
            localizedPrice: "$34.99",
            period: SubscriptionPeriod(value: 1, unit: .year)
        )

        #expect(disclosure == "$34.99/year, auto-renews until cancelled.")
    }

    @Test func nonSubscriptionDisclosureDoesNotClaimAutoRenewal() {
        let disclosure = SubscriptionDisclosure.renewalTerms(localizedPrice: "$49.99", period: nil)

        #expect(disclosure == "$49.99, not an auto-renewing subscription.")
    }
}

@MainActor
private final class RestorePurchasesProbe {
    private(set) var calls = 0

    func restore() async throws -> Bool {
        calls += 1
        return true
    }
}
