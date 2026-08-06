import XCTest

/// Hermetic UI journey for the derived surfaces on Dashboard and Stats: LOCAL_DEMO_MODE +
/// UI_TEST_PRO, no live service evidence.
///
/// Most of this file asserts ABSENCE, and that is the point. The demo vehicle carries one fuel
/// entry, one wear snapshot per item and no tire installation — thin data by design — and every
/// feature here is built to stay silent on thin data rather than print a confident-looking guess.
/// A regression that starts rendering a projection against a single reading would pass every unit
/// test that only exercises the happy path, and this is the one place it shows up.
@MainActor
final class EnthusiastInsightsJourneyTests: JourneyTestCase {
    /// The one new surface the demo data CAN support: the Viper has a track day on record.
    func testStatsShowsTheTrackDaySummaryForAVehicleWithTrackHistory() {
        let app = launchDemo(pro: true)
        tapTab("Stats", in: app)

        let card = app.descendants(matching: .any)["stats.trackDays"]
        require(card)
        // The card combines its children for VoiceOver, so the heading and figures arrive as one
        // element's label rather than as separate static texts.
        XCTAssertTrue(card.label.contains("Track days"), "Unexpected track card label: \(card.label)")
        XCTAssertTrue(card.label.contains("Most recent"), "Unexpected track card label: \(card.label)")
    }

    /// One fill-up is nowhere near `FuelEconomyAdvisor`'s ten-tank baseline, and one wear snapshot
    /// is a point rather than a rate. Both new Dashboard surfaces must be absent, and the wear
    /// section must still render normally around them.
    func testDashboardStaysSilentWhenTheHistoryCannotSupportAProjection() {
        let app = launchDemo(pro: true)
        tapTab("Dashboard", in: app)
        require(app.staticTexts["Wear items"])

        XCTAssertFalse(
            app.descendants(matching: .any)["dashboard.fuelEconomy"].exists,
            "A single fuel entry cannot establish a baseline, so nothing may be claimed about it"
        )
        // The wear bars combine their children, so a note reaches accessibility as part of the
        // bar's VALUE — searching static texts alone would find nothing either way.
        assertNothingCarriesAValue(containing: "at the current rate", in: app)
        assertNothingCarriesAValue(containing: "rubber ages", in: app)
    }

    private func assertNothingCarriesAValue(
        containing text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value CONTAINS[c] %@", text))
        XCTAssertEqual(matches.count, 0, "Unsupported claim rendered: \(text)", file: file, line: line)
    }
}
