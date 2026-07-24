import Foundation
import RevenueCat

@MainActor
final class LiveRevenueCatClient: RevenueCatClienting {
    private let observedUserID: ObservedUserIDProvider
    #if DEBUG
    private let offeringsExecutor: DebugOfferingsExecutor?
    private let purchaseExecutor: DebugPurchaseExecutor?
    #endif
    private var cacheEpoch: UInt64 = 0, packageOrdinal: UInt64 = 0
    private var packages: [PackageHandle: RevenueCatCachedPackage] = [:]

    var appUserID: String { observedUserID() }

    init() {
        observedUserID = { Purchases.shared.appUserID }
        #if DEBUG
        offeringsExecutor = nil
        purchaseExecutor = nil
        #endif
    }

    #if DEBUG
    init(
        observedUserID: @escaping ObservedUserIDProvider,
        offeringsExecutor: DebugOfferingsExecutor? = nil,
        purchaseExecutor: DebugPurchaseExecutor? = nil
    ) {
        self.observedUserID = observedUserID
        self.offeringsExecutor = offeringsExecutor
        self.purchaseExecutor = purchaseExecutor
    }
    #endif

    func invalidatePackageCache() {
        _ = SubscriptionCheckedCounter.advance(&cacheEpoch, name: "package cache epoch")
        packages.removeAll(keepingCapacity: false)
    }

    func logIn(uid: String) async -> RevenueCatObserved<EntitlementSnapshot> {
        await RevenueCatValueMapper.observe(userID: observedUserID) {
            RevenueCatValueMapper.snapshot((try await Purchases.shared.logIn(uid)).customerInfo)
        }
    }

    func logOut() async -> RevenueCatObserved<EntitlementSnapshot> {
        await RevenueCatValueMapper.observe(userID: observedUserID) {
            // Purchases.logOut() throws on an already-anonymous user; that state is the goal,
            // not a failure, so report the current snapshot instead.
            guard !Purchases.shared.isAnonymous else {
                return RevenueCatValueMapper.snapshot(try await Purchases.shared.customerInfo())
            }
            return RevenueCatValueMapper.snapshot(try await Purchases.shared.logOut())
        }
    }

    func customerInfo() async -> RevenueCatObserved<EntitlementSnapshot> {
        await RevenueCatValueMapper.observe(userID: observedUserID) {
            RevenueCatValueMapper.snapshot(try await Purchases.shared.customerInfo())
        }
    }

    func offerings() async -> RevenueCatObserved<ClientOfferingsPayload> {
        let admissionEpoch = cacheEpoch
        do {
            let acquired = try await acquireOffering()
            guard admissionEpoch == cacheEpoch else {
                return observed(.success(.cacheInvalidated))
            }
            guard let acquired else {
                invalidatePackageCache()
                return observed(.success(.unavailable(epoch: cacheEpoch)))
            }
            let snapshot = install(acquired)
            guard !snapshot.packages.isEmpty else {
                return observed(.success(.unavailable(epoch: snapshot.epoch)))
            }
            return observed(.success(.loaded(snapshot)))
        } catch {
            return observed(.failure(SubscriptionOutcomeClassifier.error(error)))
        }
    }

    func purchase(
        handle: PackageHandle,
        offeringID: String,
        packageID: String,
        productID: String,
        analyticsProduct: AnalyticsProductID
    ) async -> RevenueCatObserved<ClientPurchasePayload> {
        guard let cached = packages[handle], handle.cacheEpoch == cacheEpoch,
              cached.offeringID == offeringID,
              cached.facts.packageID == packageID, cached.facts.productID == productID,
              cached.analyticsProduct == analyticsProduct else {
            return observed(.success(.selectionInvalidated))
        }
        #if DEBUG
        if purchaseExecutor == nil, cached.package == nil {
            return observed(.success(.selectionInvalidated))
        }
        #endif
        do {
            guard let result = try await executePurchase(cached: cached, handle: handle) else {
                return observed(.success(.selectionInvalidated))
            }
            if result.userCancelled { return observed(.success(.cancelled)) }
            return observed(.success(.completed(snapshot: result.snapshot, product: analyticsProduct)))
        } catch {
            if RevenueCatValueMapper.isCancellation(error) { return observed(.success(.cancelled)) }
            return observed(.failure(SubscriptionOutcomeClassifier.error(error)))
        }
    }

    func restore() async -> RevenueCatObserved<EntitlementSnapshot> {
        await RevenueCatValueMapper.observe(userID: observedUserID) {
            RevenueCatValueMapper.snapshot(try await Purchases.shared.restorePurchases())
        }
    }

    private func acquireOffering() async throws -> (String, [(Package?, RawPackageFacts)])? {
        #if DEBUG
        if let offeringsExecutor {
            guard let facts = try await offeringsExecutor() else { return nil }
            return (facts.offeringID, facts.packages.map { (nil, $0) })
        }
        #endif
        guard let offering = try await Purchases.shared.offerings().current else { return nil }
        return (offering.identifier, offering.availablePackages.map { package in
            (package, RevenueCatValueMapper.facts(package))
        })
    }

    private func install(_ acquired: (String, [(Package?, RawPackageFacts)])) -> OfferingsSnapshot {
        invalidatePackageCache()
        var dtos: [PackageDTO] = []
        var omitted: [String] = []
        for (package, facts) in acquired.1 {
            guard facts.period?.isSupportedRenewal == true,
                  let product = AnalyticsProductID(storeProductIdentifier: facts.productID) else {
                omitted.append(facts.productID)
                continue
            }
            let handle = PackageHandle(
                cacheEpoch: cacheEpoch,
                ordinal: SubscriptionCheckedCounter.advance(&packageOrdinal, name: "package ordinal")
            )
            packages[handle] = RevenueCatCachedPackage(
                package: package,
                offeringID: acquired.0,
                facts: facts,
                analyticsProduct: product
            )
            dtos.append(RevenueCatValueMapper.dto(
                facts,
                offeringID: acquired.0,
                handle: handle,
                product: product
            ))
        }
        return OfferingsSnapshot(
            epoch: cacheEpoch,
            offeringID: acquired.0,
            packages: dtos,
            omittedUnknownProductIDs: omitted
        )
    }

    private func executePurchase(
        cached: RevenueCatCachedPackage,
        handle: PackageHandle
    ) async throws -> RawPurchaseResult? {
        #if DEBUG
        if let purchaseExecutor {
            return try await purchaseExecutor(
                handle,
                cached.offeringID,
                cached.facts.packageID,
                cached.facts.productID,
                cached.analyticsProduct
            )
        }
        #endif
        guard let package = cached.package,
              package.presentedOfferingContext.offeringIdentifier == cached.offeringID else { return nil }
        let result = try await Purchases.shared.purchase(package: package)
        let snapshot = RevenueCatValueMapper.snapshot(result.customerInfo)
        return RawPurchaseResult(userCancelled: result.userCancelled, snapshot: snapshot)
    }

    private func observed<Value: Sendable>(_ result: Result<Value, SubscriptionError>) -> RevenueCatObserved<Value> {
        RevenueCatObserved(result: result, observedAppUserID: observedUserID())
    }
}
