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
}

@MainActor
private final class RestorePurchasesProbe {
    private(set) var calls = 0

    func restore() async throws -> Bool {
        calls += 1
        return true
    }
}
