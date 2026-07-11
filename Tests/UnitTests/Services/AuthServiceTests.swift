import Foundation
import RevenueCat
import Testing
@testable import Garage

@MainActor
struct AuthServiceTests {
    @Test func localDemo_authenticatesImmediatelyWithDemoUID() {
        let service = AuthService.localDemo

        #expect(service.isAuthenticated)
        #expect(service.uid == AppRuntime.demoUserId)
    }

    @Test func uiTestMode_blocksLiveSignInAndSignOutClearsInjectedState() async {
        let analytics = AnalyticsSpy()
        let service = AuthService(testUID: "test-user", analytics: analytics)

        do {
            try await service.signInWithApple(idToken: "token", nonce: "nonce")
            Issue.record("Expected UI-test authentication mode to reject live sign-in")
        } catch {
            #expect(error as? AppError == .auth("Authentication is disabled in UI tests"))
        }

        try? service.signOut()

        #expect(!service.isAuthenticated)
        #expect(service.uid == nil)
        #expect(analytics.enabledValues.last == false)
    }

    @Test func accountSwitch_disablesAnalyticsBeforeTheNextProfileCanLoad() {
        let analytics = AnalyticsSpy()
        let service = AuthService(testUID: "first-user", analytics: analytics)
        analytics.setEnabled(true)

        service.switchAuthenticatedUserForTesting(to: "second-user")

        #expect(service.uid == "second-user")
        #expect(analytics.enabledValues.last == false)
    }

    @Test func authenticatedUser_awaitsRevenueCatIdentityAndAppliesReturnedCustomerInfo() async throws {
        let identityProbe = PurchasesIdentityProbe()
        let purchaseService = PurchaseService(testIsPro: false)
        let service = AuthService(
            testUID: "firebase-user",
            purchasesIdentitySync: identityProbe.sync,
            purchasesCustomerInfoApply: purchaseService.apply
        )

        let readyUserID = Task { await service.waitForPurchasesIdentity() }
        await Task.yield()

        #expect(identityProbe.actions == [.logIn("firebase-user")])
        #expect(!purchaseService.isPro)

        identityProbe.completeLogIn(with: customerInfo(isPro: true))

        let resolvedUserID = await readyUserID.value
        #expect(resolvedUserID == "firebase-user")
        #expect(purchaseService.isPro)

        try service.signOut()
        _ = await service.waitForPurchasesIdentity()

        #expect(identityProbe.actions == [.logIn("firebase-user"), .logOut])
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
private final class PurchasesIdentityProbe {
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
