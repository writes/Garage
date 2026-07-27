import Foundation
import Testing
@testable import Garage

/// Covers trial detection: the `EntitlementPeriod` model, and `PurchaseServiceState`'s choice
/// between `trial_started` and `purchase_completed`. Those two must stay mutually exclusive —
/// emitting both would leave the paid count inflated by trials, which is the defect the split
/// exists to fix.
@MainActor
struct TrialDetectionTests {
    private static let lease = SubscriptionFixtures.leaseA
    private static let future = Date(timeIntervalSince1970: 4_000_000_000)
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(period: EntitlementPeriod) -> EntitlementSnapshot {
        EntitlementSnapshot(
            isActive: true,
            expirationDate: Self.future,
            productID: Constants.annualPlanIdentifier,
            period: period
        )
    }

    /// Establishes the ready lease, then commits a completed purchase and returns what the state
    /// machine decided to report.
    private func analytics(for period: EntitlementPeriod) -> AnalyticsEvent? {
        var state = PurchaseServiceState()
        _ = state.apply(
            .identityApplied(lease: Self.lease, snapshot: snapshot(period: .normal)),
            now: { Self.now }
        )
        let effects = state.apply(
            .purchaseCompleted(
                lease: Self.lease,
                snapshot: snapshot(period: period),
                productID: .annual
            ),
            now: { Self.now }
        )
        return effects.analytics
    }

    // MARK: - Model

    @Test func periodDefaultsToUnknown_soPreExistingCallSitesAreNeverMiscountedAsPaid() {
        let snap = EntitlementSnapshot(isActive: true, expirationDate: nil, productID: nil)
        #expect(snap.period == .unknown)
        #expect(snap.period != .normal, "unknown must not collapse into normal")
    }

    @Test func disablingEntitlement_preservesThePeriod() {
        let disabled = snapshot(period: .trial).disablingEntitlement()
        #expect(disabled.isActive == false)
        #expect(disabled.period == .trial, "revoking entitlement must not rewrite billing phase")
    }

    @Test func entitlementPeriod_rawValuesAreStable() {
        #expect(EntitlementPeriod.normal.rawValue == "normal")
        #expect(EntitlementPeriod.trial.rawValue == "trial")
        #expect(EntitlementPeriod.intro.rawValue == "intro")
        #expect(EntitlementPeriod.unknown.rawValue == "unknown")
    }

    // MARK: - Routing

    @Test func trialPurchase_emitsTrialStarted_notPurchaseCompleted() {
        #expect(analytics(for: .trial) == .trialStarted(productID: .annual))
    }

    @Test(arguments: [EntitlementPeriod.normal, .intro, .unknown])
    func nonTrialPurchase_emitsPurchaseCompleted(period: EntitlementPeriod) {
        #expect(analytics(for: period) == .purchaseCompleted(productID: .annual))
    }

    /// Exactly one of the two must fire for any purchase, in either direction.
    @Test func trialAndPurchaseEvents_areMutuallyExclusive() {
        for period in [EntitlementPeriod.normal, .trial, .intro, .unknown] {
            let event = analytics(for: period)
            let isTrial = event == .trialStarted(productID: .annual)
            let isPurchase = event == .purchaseCompleted(productID: .annual)
            #expect(isTrial != isPurchase, "exactly one must fire for \(period)")
        }
    }

    // MARK: - Analytics contract

    @Test func trialStarted_isInTheEventNameList_andNamesStayUnique() {
        #expect(AnalyticsEvent.activationFunnelNames.contains("trial_started"))
        #expect(Set(AnalyticsEvent.allNames).count == AnalyticsEvent.allNames.count)
    }

    @Test func trialStarted_definitionCarriesProductAndSchemaVersion() {
        let definition = AnalyticsEvent.trialStarted(productID: .monthly).definition
        #expect(definition.name == "trial_started")
        #expect(definition.parameters.contains(.productID(.monthly)))
        #expect(definition.parameters.contains(.schemaVersion(1)))
        #expect(definition.firebaseParameters["product_id"] as? String == "garage_pro_monthly")
    }

    @Test func trialStarted_coversEveryProduct() {
        for product in AnalyticsProductID.allCases {
            let definition = AnalyticsEvent.trialStarted(productID: product).definition
            #expect(definition.name == "trial_started")
            #expect(definition.parameters.contains(.productID(product)))
        }
    }
}
