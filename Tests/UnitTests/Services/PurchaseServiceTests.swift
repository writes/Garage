import Foundation
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

    @Test func subscriptionStatus_waitsForFirebaseRevenueCatIdentityBeforeReadingEntitlements() async {
        let identityProbe = IdentitySyncProbe()
        let entitlementProbe = CustomerInfoProbe(customerInfo: customerInfo(isPro: true))
        let authServiceBox = AuthServiceBox()
        let service = PurchaseService(
            testIsPro: false,
            identityReady: {
                guard let authService = authServiceBox.service else { return nil }
                return await authService.waitForPurchasesIdentity()
            },
            customerInfoOverride: entitlementProbe.load
        )
        authServiceBox.service = AuthService(
            testUID: "firebase-user",
            purchasesIdentitySync: identityProbe.sync,
            purchasesCustomerInfoApply: service.apply
        )

        let statusTask = Task { await service.checkSubscriptionStatus() }
        await Task.yield()

        #expect(identityProbe.actions == [.logIn("firebase-user")])
        #expect(entitlementProbe.calls == 0)

        identityProbe.completeLogIn(with: customerInfo(isPro: true))
        await statusTask.value

        #expect(entitlementProbe.calls == 1)
        #expect(service.isPro)
    }

    @Test func purchase_waitsForIdentityBeforeStartingThePurchase() async throws {
        let identityGate = IdentityGate()
        let purchaseProbe = CustomerInfoProbe(customerInfo: customerInfo(isPro: true))
        let service = PurchaseService(
            testIsPro: false,
            identityReady: identityGate.wait,
            purchaseOverride: purchaseProbe.load
        )

        let purchaseTask = Task { try await service.purchaseForTesting() }
        await Task.yield()

        #expect(purchaseProbe.calls == 0)

        identityGate.open(for: "firebase-user")
        try await purchaseTask.value

        #expect(purchaseProbe.calls == 1)
        #expect(service.isPro)
    }

    @Test func restorePurchases_waitsForIdentityBeforeStartingTheRestore() async throws {
        let identityGate = IdentityGate()
        let restoreProbe = RestorePurchasesProbe()
        let service = PurchaseService(
            testIsPro: false,
            restorePurchasesOverride: restoreProbe.restore,
            identityReady: identityGate.wait
        )

        let restoreTask = Task { try await service.restorePurchases() }
        await Task.yield()

        #expect(restoreProbe.calls == 0)

        identityGate.open(for: "firebase-user")
        try await restoreTask.value

        #expect(restoreProbe.calls == 1)
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

    private func customerInfo(isPro: Bool) -> CustomerInfo {
        let proEntitlement = EntitlementInfo(
            identifier: "pro",
            isActive: isPro,
            willRenew: true,
            periodType: .normal,
            store: .appStore,
            productIdentifier: "garage.pro",
            isSandbox: true,
            ownershipType: .purchased
        )
        let now = Date()
        return CustomerInfo(
            entitlements: EntitlementInfos(entitlements: ["pro": proEntitlement]),
            requestDate: now,
            firstSeen: now,
            originalAppUserId: "firebase-user"
        )
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

@MainActor
private final class IdentitySyncProbe {
    private(set) var actions: [PurchasesIdentityAction] = []
    private var logInContinuation: CheckedContinuation<PurchasesIdentityResult, Never>?

    func sync(_ action: PurchasesIdentityAction) async -> PurchasesIdentityResult {
        actions.append(action)
        switch action {
        case .logIn:
            return await withCheckedContinuation { continuation in
                logInContinuation = continuation
            }
        case .logOut:
            return .loggedOut
        }
    }

    func completeLogIn(with customerInfo: CustomerInfo) {
        logInContinuation?.resume(returning: .customerInfo(customerInfo))
        logInContinuation = nil
    }
}

@MainActor
private final class IdentityGate {
    private var continuation: CheckedContinuation<String?, Never>?

    func wait() async -> String? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open(for userID: String) {
        continuation?.resume(returning: userID)
        continuation = nil
    }
}

@MainActor
private final class CustomerInfoProbe {
    private let customerInfo: CustomerInfo
    private(set) var calls = 0

    init(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
    }

    func load() async throws -> CustomerInfo {
        calls += 1
        return customerInfo
    }
}

@MainActor
private final class AuthServiceBox {
    var service: AuthService?
}
