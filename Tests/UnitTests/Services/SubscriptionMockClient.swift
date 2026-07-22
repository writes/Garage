import Foundation
@testable import Garage

@MainActor
final class SubscriptionMockClient: RevenueCatClienting {
    typealias LoginHandler = @MainActor (String) async -> RevenueCatObserved<EntitlementSnapshot>
    typealias StatusHandler = @MainActor () async -> RevenueCatObserved<EntitlementSnapshot>
    typealias OfferingsHandler = @MainActor () async -> RevenueCatObserved<ClientOfferingsPayload>
    typealias PurchaseHandler = @MainActor (
        PackageHandle,
        String,
        String,
        String,
        AnalyticsProductID
    ) async -> RevenueCatObserved<ClientPurchasePayload>

    var appUserID = "anonymous"
    var loginHandler: LoginHandler?
    var statusHandler: StatusHandler?
    var offeringsHandler: OfferingsHandler?
    var purchaseHandler: PurchaseHandler?
    var restoreHandler: StatusHandler?
    private(set) var invalidationCount = 0
    private(set) var loginUIDs: [String] = []
    private(set) var statusCalls = 0
    private(set) var offeringsCalls = 0
    private(set) var purchaseCalls = 0
    private(set) var restoreCalls = 0
    private(set) var callLog: [String] = []

    func invalidatePackageCache() { invalidationCount += 1 }

    func logIn(uid: String) async -> RevenueCatObserved<EntitlementSnapshot> {
        loginUIDs.append(uid)
        callLog.append("login:\(uid)")
        if let loginHandler {
            let result = await loginHandler(uid)
            appUserID = result.observedAppUserID
            return result
        }
        appUserID = uid
        return observed(.success(.inactive), uid: uid)
    }

    func logOut() async -> RevenueCatObserved<EntitlementSnapshot> {
        callLog.append("logout")
        appUserID = "anonymous"
        return observed(.success(.inactive), uid: "anonymous")
    }

    func customerInfo() async -> RevenueCatObserved<EntitlementSnapshot> {
        statusCalls += 1
        callLog.append("status")
        if let statusHandler { return await statusHandler() }
        return observed(.success(.inactive))
    }

    func offerings() async -> RevenueCatObserved<ClientOfferingsPayload> {
        offeringsCalls += 1
        callLog.append("offerings")
        if let offeringsHandler { return await offeringsHandler() }
        return observed(.success(.unavailable(epoch: 1)))
    }

    func purchase(
        handle: PackageHandle,
        offeringID: String,
        packageID: String,
        productID: String,
        analyticsProduct: AnalyticsProductID
    ) async -> RevenueCatObserved<ClientPurchasePayload> {
        purchaseCalls += 1
        callLog.append("purchase")
        if let purchaseHandler {
            return await purchaseHandler(handle, offeringID, packageID, productID, analyticsProduct)
        }
        return observed(.success(.selectionInvalidated))
    }

    func restore() async -> RevenueCatObserved<EntitlementSnapshot> {
        restoreCalls += 1
        callLog.append("restore")
        if let restoreHandler { return await restoreHandler() }
        return observed(.success(.inactive))
    }

    func observed<Value: Sendable>(
        _ result: Result<Value, SubscriptionError>,
        uid: String? = nil
    ) -> RevenueCatObserved<Value> {
        RevenueCatObserved(result: result, observedAppUserID: uid ?? appUserID)
    }
}

private extension EntitlementSnapshot {
    static let inactive = EntitlementSnapshot(
        isActive: false,
        expirationDate: nil,
        productID: nil
    )
}

@MainActor
final class HeldValue<Value: Sendable> {
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<Value, Never>] = [:]
    private var starts: [Int] = []
    private var startWaiter: CheckedContinuation<Int, Never>?
    private(set) var calls = 0

    func load() async -> Value {
        let id = nextID
        nextID += 1
        calls += 1
        return await withCheckedContinuation { continuation in
            continuations[id] = continuation
            if let startWaiter {
                self.startWaiter = nil
                startWaiter.resume(returning: id)
            } else {
                starts.append(id)
            }
        }
    }

    func waitForStart() async -> Int {
        if !starts.isEmpty { return starts.removeFirst() }
        return await withCheckedContinuation { startWaiter = $0 }
    }

    func resolve(_ id: Int, with value: Value) {
        continuations.removeValue(forKey: id)?.resume(returning: value)
    }

    func drain(with value: Value) {
        let pending = continuations.values
        continuations.removeAll()
        starts.removeAll()
        pending.forEach { $0.resume(returning: value) }
        startWaiter?.resume(returning: -1)
        startWaiter = nil
    }
}
