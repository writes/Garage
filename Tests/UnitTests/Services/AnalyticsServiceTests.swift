import Testing
@testable import Garage

@MainActor
struct AnalyticsServiceTests {
    @Test func v1EventNames_areStable() {
        #expect(AnalyticsEvent.v1Names == [
            "first_vehicle_added",
            "first_entry_added",
            "paywall_viewed",
            "purchase_completed",
            "purchase_restored",
            "export_csv",
            "export_pdf",
            "oil_analysis_requested",
            "oil_analysis_succeeded",
            "oil_analysis_quota_denied"
        ])
    }

    @Test func v1Definitions_includeExpectedTypedParametersAndSchemaVersion() {
        let events: [AnalyticsEvent] = [
            .firstVehicleAdded,
            .firstEntryAdded(entryType: .fuel),
            .paywallViewed(source: .settings),
            .purchaseCompleted(productID: .annual),
            .purchaseRestored,
            .exportCSV(entryCount: 12),
            .exportPDF(entryCount: 8),
            .oilAnalysisRequested,
            .oilAnalysisSucceeded,
            .oilAnalysisQuotaDenied(reason: .freeLifetimeExhausted)
        ]

        #expect(events.map(\.definition) == [
            AnalyticsEventDefinition(name: "first_vehicle_added"),
            AnalyticsEventDefinition(name: "first_entry_added", parameters: [.entryType(.fuel)]),
            AnalyticsEventDefinition(name: "paywall_viewed", parameters: [.source(.settings)]),
            AnalyticsEventDefinition(name: "purchase_completed", parameters: [.productID(.annual)]),
            AnalyticsEventDefinition(name: "purchase_restored"),
            AnalyticsEventDefinition(name: "export_csv", parameters: [.entryCount(12)]),
            AnalyticsEventDefinition(name: "export_pdf", parameters: [.entryCount(8)]),
            AnalyticsEventDefinition(name: "oil_analysis_requested"),
            AnalyticsEventDefinition(name: "oil_analysis_succeeded"),
            AnalyticsEventDefinition(
                name: "oil_analysis_quota_denied",
                parameters: [.reason(.freeLifetimeExhausted)]
            )
        ])
    }

    @Test func disabledSpy_dropsEventsUntilOptIn() {
        let analytics = AnalyticsSpy()

        analytics.setEnabled(false)
        analytics.track(.firstVehicleAdded)

        #expect(analytics.events.isEmpty)
        #expect(analytics.enabledValues == [false])

        analytics.setEnabled(true)
        analytics.track(.firstVehicleAdded)

        #expect(analytics.events == [.firstVehicleAdded])
    }
}
