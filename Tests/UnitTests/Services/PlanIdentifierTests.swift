import Foundation
import Testing
@testable import Garage

/// Guards the store product identifiers.
///
/// These shipped wrong: `Constants` carried `garage_pro_monthly` / `garage_pro_annual` while App
/// Store Connect only ever had `com.writes.harrysplayhouse.pro.monthly` and `...pro.yearly`.
/// Nothing caught it, because the failure mode is silent — the offerings pipeline filters every
/// package through `AnalyticsProductID(storeProductIdentifier:)`, drops anything unrecognised into
/// `omittedUnknownProductIDs`, and renders an **empty paywall**. No error, no crash, nothing to
/// buy. RevenueCat listed both hardcoded IDs as "Not found" and the app never noticed.
///
/// A unit test cannot reach App Store Connect, so these assert the invariants that would have
/// caught it: store IDs are reverse-DNS under the app's bundle prefix, and every real product ID
/// round-trips through the analytics mapping.
@MainActor
struct PlanIdentifierTests {
    /// Matches the bundle identifier the Release build ships under.
    private static let bundlePrefix = "com.writes.harrysplayhouse"

    @Test func planIdentifiersMatchAppStoreConnect() {
        #expect(Constants.monthlyPlanIdentifier == "com.writes.harrysplayhouse.pro.monthly")
        #expect(Constants.annualPlanIdentifier == "com.writes.harrysplayhouse.pro.yearly")
    }

    /// The shape check that would have caught the original bug: a bare `garage_pro_monthly` is not
    /// reverse-DNS and cannot be a real StoreKit product for this app.
    @Test(arguments: [Constants.monthlyPlanIdentifier, Constants.annualPlanIdentifier])
    func planIdentifiersAreReverseDNSUnderTheBundlePrefix(identifier: String) {
        // An unrecognised ID is silently dropped and the paywall renders empty.
        #expect(
            identifier.hasPrefix(Self.bundlePrefix + "."),
            "\(identifier) is not a StoreKit product ID for this app"
        )
        #expect(!identifier.contains(" "))
        #expect(identifier.lowercased() == identifier, "StoreKit product IDs are case sensitive")
    }

    @Test func theTwoPlansAreDistinct() {
        #expect(Constants.monthlyPlanIdentifier != Constants.annualPlanIdentifier)
    }

    // MARK: - The mapping that does the filtering

    /// Every real store product must resolve. Anything that returns nil here is invisible in the
    /// paywall.
    @Test func realStoreIdentifiersResolveToAnalyticsProducts() {
        #expect(AnalyticsProductID(storeProductIdentifier: Constants.monthlyPlanIdentifier) == .monthly)
        #expect(AnalyticsProductID(storeProductIdentifier: Constants.annualPlanIdentifier) == .annual)
    }

    /// The identifiers that were wrongly hardcoded must NOT resolve — they do not exist in the
    /// store, and treating them as valid is what masked the defect.
    @Test(arguments: ["garage_pro_monthly", "garage_pro_annual"])
    func staleIdentifiersDoNotResolve(stale: String) {
        #expect(
            AnalyticsProductID(storeProductIdentifier: stale) == nil,
            "\(stale) does not exist in App Store Connect and must not be treated as a product"
        )
    }

    @Test func unknownIdentifiersAreRejected() {
        #expect(AnalyticsProductID(storeProductIdentifier: "") == nil)
        #expect(AnalyticsProductID(storeProductIdentifier: "com.writes.harrysplayhouse.pro.weekly") == nil)
        #expect(AnalyticsProductID(storeProductIdentifier: "com.other.app.pro.monthly") == nil)
    }

    /// Analytics labels are deliberately NOT the store IDs. They are stable names that saved
    /// Firebase funnels key on, so they must not drift toward the store SKUs.
    @Test func analyticsLabelsAreStable_andSeparateFromStoreIdentifiers() {
        #expect(AnalyticsProductID.monthly.rawValue == "garage_pro_monthly")
        #expect(AnalyticsProductID.annual.rawValue == "garage_pro_annual")
        #expect(AnalyticsProductID.monthly.rawValue != Constants.monthlyPlanIdentifier)
        #expect(AnalyticsProductID.annual.rawValue != Constants.annualPlanIdentifier)
    }
}
