import Foundation
import RevenueCat

@MainActor
protocol RevenueCatClienting: AnyObject {
    var appUserID: String { get }
    func invalidatePackageCache()
    func logIn(uid: String) async -> RevenueCatObserved<EntitlementSnapshot>
    func logOut() async -> RevenueCatObserved<EntitlementSnapshot>
    func customerInfo() async -> RevenueCatObserved<EntitlementSnapshot>
    func offerings() async -> RevenueCatObserved<ClientOfferingsPayload>
    func purchase(
        handle: PackageHandle,
        offeringID: String,
        packageID: String,
        productID: String,
        analyticsProduct: AnalyticsProductID
    ) async -> RevenueCatObserved<ClientPurchasePayload>
    func restore() async -> RevenueCatObserved<EntitlementSnapshot>
    /// A live push channel for entitlement changes (FIX D): server-side or later-approved
    /// (Ask-to-Buy/SCA) purchases converge without waiting for relaunch or paywall reopen.
    func observeCustomerInfoUpdates() -> AsyncStream<EntitlementSnapshot>
}

struct RawPurchaseResult: Equatable, Sendable {
    let userCancelled: Bool
    let snapshot: EntitlementSnapshot
}

struct RawPackageFacts: Equatable, Sendable {
    let packageID: String
    let productID: String
    let title: String
    let packageDescription: String
    let localizedPrice: String
    let period: SubscriptionPeriodDTO?
}

struct RawOfferingFacts: Equatable, Sendable {
    let offeringID: String
    let packages: [RawPackageFacts]
}

struct RevenueCatCachedPackage {
    let package: Package?
    let offeringID: String
    let facts: RawPackageFacts
    let analyticsProduct: AnalyticsProductID
}

typealias ObservedUserIDProvider = @MainActor @Sendable () -> String
typealias SubscriptionClientFactory = @MainActor () -> any RevenueCatClienting
typealias SubscriptionGatewayFactory = @MainActor (
    any RevenueCatClienting,
    SubscriptionCommitRelay
) -> SubscriptionGateway
typealias SubscriptionMonitorFactory = @MainActor (
    @escaping @MainActor @Sendable () -> Void
) -> SubscriptionRecoveryMonitor

#if DEBUG
typealias DebugPurchaseExecutor = @MainActor @Sendable (
    PackageHandle,
    String,
    String,
    String,
    AnalyticsProductID
) async throws -> RawPurchaseResult

typealias DebugOfferingsExecutor = @MainActor @Sendable () async throws -> RawOfferingFacts?
#endif

enum RevenueCatValueMapper {
    @MainActor
    static func observe<Value: Sendable>(
        userID: ObservedUserIDProvider,
        operation: () async throws -> Value
    ) async -> RevenueCatObserved<Value> {
        do {
            return RevenueCatObserved(result: .success(try await operation()), observedAppUserID: userID())
        } catch {
            return RevenueCatObserved(
                result: .failure(SubscriptionOutcomeClassifier.error(error)),
                observedAppUserID: userID()
            )
        }
    }

    static func snapshot(_ info: CustomerInfo) -> EntitlementSnapshot {
        let entitlement = info.entitlements["pro"]
        return EntitlementSnapshot(
            isActive: entitlement?.isActive == true,
            expirationDate: entitlement?.expirationDate,
            productID: entitlement?.productIdentifier,
            period: period(entitlement?.periodType)
        )
    }

    /// The single place RevenueCat's `PeriodType` crosses into app types. `prepaid` is Play Store
    /// only and unreachable on iOS; it and any future case map to `.unknown` rather than
    /// `.normal`, so an unmapped phase can never be silently counted as a paid purchase.
    static func period(_ periodType: PeriodType?) -> EntitlementPeriod {
        switch periodType {
        case .normal: return .normal
        case .intro: return .intro
        case .trial: return .trial
        default: return .unknown
        }
    }

    static func facts(_ package: Package) -> RawPackageFacts {
        let product = package.storeProduct
        return RawPackageFacts(
            packageID: package.identifier,
            productID: product.productIdentifier,
            title: product.localizedTitle,
            packageDescription: product.localizedDescription,
            localizedPrice: product.localizedPriceString,
            period: period(product.subscriptionPeriod)
        )
    }

    static func dto(
        _ facts: RawPackageFacts,
        offeringID: String,
        handle: PackageHandle,
        product: AnalyticsProductID
    ) -> PackageDTO {
        PackageDTO(
            handle: handle,
            offeringID: offeringID,
            packageID: facts.packageID,
            productID: facts.productID,
            analyticsProduct: product,
            title: facts.title,
            packageDescription: facts.packageDescription,
            localizedPrice: facts.localizedPrice,
            period: facts.period
        )
    }

    static func isCancellation(_ error: Error) -> Bool {
        (error as NSError).asErrorCode == .purchaseCancelledError
    }

    /// Ask-to-Buy/SCA deferred to an approver — the SDK throws this promptly (never hangs).
    /// Mirrors `isCancellation` exactly: same NSError-bridged ErrorCode detection (FIX A).
    static func isPaymentPending(_ error: Error) -> Bool {
        (error as NSError).asErrorCode == .paymentPendingError
    }

    private static func period(_ period: SubscriptionPeriod?) -> SubscriptionPeriodDTO? {
        guard let period else { return nil }
        let unit: SubscriptionPeriodDTO.Unit
        switch period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: unit = .unknown
        }
        return SubscriptionPeriodDTO(value: period.value, unit: unit)
    }
}

struct SubscriptionRuntimeComponents {
    let relay: SubscriptionCommitRelay
    let gateway: SubscriptionGateway
    let monitor: SubscriptionRecoveryMonitor
    let scheduler: any EntitlementExpiryScheduling
}

@MainActor
enum SubscriptionRuntimeFactory {
    static func make(
        reporter: any SubscriptionIntegrityReporter,
        expirySchedulerFactory: EntitlementExpirySchedulerFactory,
        clientFactory: SubscriptionClientFactory,
        gatewayFactory: SubscriptionGatewayFactory,
        monitorFactory: SubscriptionMonitorFactory
    ) -> SubscriptionRuntimeComponents {
        let relay = SubscriptionCommitRelay(reporter: reporter)
        let gateway = gatewayFactory(clientFactory(), relay)
        let retry: @MainActor @Sendable () -> Void = { [weak gateway] in
            _ = gateway?.requestIdentityRetry()
        }
        return SubscriptionRuntimeComponents(
            relay: relay,
            gateway: gateway,
            monitor: monitorFactory(retry),
            scheduler: expirySchedulerFactory()
        )
    }
}
