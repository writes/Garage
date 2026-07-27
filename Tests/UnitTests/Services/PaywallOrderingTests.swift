import Foundation
import Testing
@testable import Garage

/// Covers the paywall's plan ordering. Annual leads because it generates roughly twice the
/// revenue per install of monthly; the rule is ordering only — no plan is hidden and monthly
/// remains selectable.
@MainActor
struct PaywallOrderingTests {
    private func package(
        _ product: AnalyticsProductID,
        ordinal: UInt64 = 1
    ) -> PackageDTO {
        PackageDTO(
            handle: PackageHandle(cacheEpoch: 1, ordinal: ordinal),
            offeringID: "default",
            packageID: product == .annual ? "$rc_annual" : "$rc_monthly",
            productID: product == .annual
                ? Constants.annualPlanIdentifier
                : Constants.monthlyPlanIdentifier,
            analyticsProduct: product,
            title: product == .annual ? "Annual" : "Monthly",
            packageDescription: "",
            localizedPrice: product == .annual ? "$34.99" : "$4.99",
            period: SubscriptionPeriodDTO(value: 1, unit: product == .annual ? .year : .month)
        )
    }

    private func snapshot(_ packages: [PackageDTO]) -> OfferingsSnapshot {
        OfferingsSnapshot(
            epoch: 1,
            offeringID: "default",
            packages: packages,
            omittedUnknownProductIDs: []
        )
    }

    private func ordered(_ packages: [PackageDTO]) -> [AnalyticsProductID] {
        SubscriptionPlanOrder.ordered(snapshot(packages)).map(\.analyticsProduct)
    }

    @Test func annualLeads_whateverOrderRevenueCatReturns() {
        #expect(ordered([package(.monthly), package(.annual)]) == [.annual, .monthly])
        #expect(ordered([package(.annual), package(.monthly)]) == [.annual, .monthly])
    }

    @Test func orderingIsTotal_soRendersDoNotReshuffle() {
        let input = [package(.monthly, ordinal: 9), package(.annual, ordinal: 2)]
        let first = ordered(input)
        for _ in 0..<25 {
            #expect(ordered(input) == first, "ordering must be deterministic across renders")
        }
    }

    /// Swift's sort is not stable, so same-rank packages need an explicit tiebreak or they are
    /// free to swap between renders.
    @Test func sameRankPackages_breakTiesOnHandleOrdinal() {
        let ordinals = SubscriptionPlanOrder
            .ordered(snapshot([package(.monthly, ordinal: 7), package(.monthly, ordinal: 3)]))
            .map(\.handle.ordinal)
        #expect(ordinals == [3, 7])
    }

    @Test func noPlanIsDropped() {
        let result = SubscriptionPlanOrder.ordered(snapshot([package(.monthly), package(.annual)]))
        #expect(result.count == 2, "ordering must never hide a plan the user could buy")
    }

    @Test func handlesSinglePlanAndEmptyOfferings() {
        #expect(ordered([package(.annual)]) == [.annual])
        #expect(ordered([package(.monthly)]) == [.monthly])
        #expect(SubscriptionPlanOrder.ordered(snapshot([])).isEmpty)
    }

    /// The first row is the emphasised one, so this is what decides which plan gets the
    /// PrimaryButton treatment.
    @Test func annualIsThePreferredRow_whenBothArePresent() {
        let result = SubscriptionPlanOrder.ordered(snapshot([package(.monthly), package(.annual)]))
        #expect(result.first?.analyticsProduct == .annual)
    }

    @Test func packageIdentifiersAreProductKeyed_notPositional() {
        // Guards the reason identifiers were changed: a positional id silently repoints at a
        // different plan the moment ordering changes.
        for product in AnalyticsProductID.allCases {
            #expect("subscription.package.\(product.rawValue)".hasSuffix(product.rawValue))
        }
        #expect(AnalyticsProductID.annual.rawValue != AnalyticsProductID.monthly.rawValue)
    }
}
