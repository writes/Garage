import Foundation
import Testing
@testable import Garage

/// The Q3-C offer-visibility matrix, split from ReceiptCreditsControllerTests for the
/// file-length cap.
@MainActor
struct ReceiptCreditsOfferVisibilityTests {
    private final class AnalyticsSpy: AnalyticsTracking {
        var events: [AnalyticsEvent] = []
        func track(_ event: AnalyticsEvent) { events.append(event) }
        func setEnabled(_: Bool) {}
    }

    private func snapshot(purchasingEnabled: Bool? = true, deficit: Int? = 0) -> ReceiptQuotaSnapshot {
        var value = ReceiptQuotaSnapshot.fixture
        value.creditsPurchasingEnabled = purchasingEnabled
        value.creditsDeficit = deficit
        value.creditsRemaining = 10
        value.creditsScanRemaining = 40
        return value
    }

    private func makeController(
        markers: ReceiptCreditsMarkerStore, analytics: AnalyticsSpy = AnalyticsSpy()
    ) -> ReceiptCreditsController {
        ReceiptCreditsController(
            purchaser: ReceiptCreditsPurchaser(
                store: InertReceiptCreditsStoreClient(), markers: markers, currentUID: { "uid-1" }
            ),
            markers: markers,
            service: FakeReceiptService(result: .success(.init(
                proposal: sampleReceiptProposal, token: nil, quota: nil
            ))),
            analytics: analytics,
            currentUID: { "uid-1" },
            sleeper: { _ in }
        )
    }

    // MARK: - Offer visibility (Q3-C)

    @Test func proMonthDenialOffersDirectly() async {
        let markers = ReceiptCreditsMarkerStore(defaults: nil)
        let controller = makeController(markers: markers)
        controller.isProductAvailable = true
        let context = controller.offerContext(
            snapshot: snapshot(), failure: .proMonthExhausted(resetAt: nil)
        )
        #expect(context == .init(scope: .proMonth, deficit: 0))
    }

    @Test func freeDenialHidesUntilThePaywallWasDismissedOnce() async {
        let markers = ReceiptCreditsMarkerStore(defaults: nil)
        let controller = makeController(markers: markers)
        controller.isProductAvailable = true
        #expect(controller.offerContext(
            snapshot: snapshot(), failure: .freeLifetimeExhausted
        ) == nil)

        markers.recordPaywallDismissed(uid: "uid-1")
        #expect(controller.offerContext(
            snapshot: snapshot(), failure: .freeLifetimeExhausted
        ) == .init(scope: .freeLifetime, deficit: 0))
    }

    @Test func offerRequiresTheServerCapabilityFlag() async {
        let controller = makeController(markers: ReceiptCreditsMarkerStore(defaults: nil))
        controller.isProductAvailable = true
        for disabled in [snapshot(purchasingEnabled: false), snapshot(purchasingEnabled: nil)] {
            #expect(controller.offerContext(
                snapshot: disabled, failure: .proMonthExhausted(resetAt: nil)
            ) == nil)
        }
        // An OLD server omits every credit field — the offer must never render against it.
        #expect(controller.offerContext(
            snapshot: .fixture, failure: .proMonthExhausted(resetAt: nil)
        ) == nil)
    }

    @Test func offerRequiresAFetchableProductAndNeverRendersOnOtherFailures() async {
        let controller = makeController(markers: ReceiptCreditsMarkerStore(defaults: nil))
        #expect(controller.offerContext(
            snapshot: snapshot(), failure: .proMonthExhausted(resetAt: nil)
        ) == nil)

        controller.isProductAvailable = true
        #expect(controller.offerContext(snapshot: snapshot(), failure: .notAReceipt) == nil)
        #expect(controller.offerContext(snapshot: snapshot(), failure: nil) == nil)
    }

    @Test func deficitSurfacesInTheOfferContext() async {
        let controller = makeController(markers: ReceiptCreditsMarkerStore(defaults: nil))
        controller.isProductAvailable = true
        let context = controller.offerContext(
            snapshot: snapshot(deficit: 7), failure: .proMonthExhausted(resetAt: nil)
        )
        #expect(context?.deficit == 7)
    }

    @Test func offerShownReportsOncePerScope() async {
        let analytics = AnalyticsSpy()
        let controller = makeController(markers: ReceiptCreditsMarkerStore(defaults: nil), analytics: analytics)
        let context = ReceiptCreditsController.OfferContext(scope: .proMonth, deficit: 0)
        controller.reportOfferShownOnce(context)
        controller.reportOfferShownOnce(context)
        #expect(analytics.events == [.receiptCreditsOfferShown(scope: .proMonth)])
    }

}
