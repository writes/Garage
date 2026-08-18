import XCTest

/// Per-arm journey lane for the Underhood (variant_a) structure — arm manifest §4 requires it
/// before enrollment. Control journeys keep tapping "Dashboard"/"Settings"; this suite exercises
/// the remapped IA end-to-end with the arm forced through the DEBUG lever.
///
/// The lever is an ENVIRONMENT variable (`ProcessInfo.processInfo.environment`), not a launch
/// argument — passing it via `launchArguments` silently launches control and every assertion
/// below times out on a tab bar that says "Dashboard".
@MainActor
final class UnderhoodDesignJourneyTests: JourneyTestCase {
    func testTabBarCarriesTheManifestIAWithoutStatsOrSettings() {
        let app = launchUnderhoodDemo()
        for title in ["Hood", "Logbook", "Record", "Bay", "Handover"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists, "missing \(title) tab")
        }
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        XCTAssertFalse(app.tabBars.buttons["Stats"].exists)
        XCTAssertFalse(app.tabBars.buttons["Dashboard"].exists)
    }

    func testSettingsAccessoryPresentsSettingsFromTheHood() {
        let app = launchUnderhoodDemo()
        let accessory = app.buttons["tab.settingsAccessory"]
        require(accessory)
        accessory.tap()
        require(app.navigationBars["Settings"])
    }

    func testRecordTabPresentsTheEntryPickerWithoutLeavingTheHood() {
        let app = launchUnderhoodDemo()
        app.tabBars.buttons["Record"].tap()
        // The picker sheet carries the concept's Record framing…
        require(app.staticTexts["Record"])
        // …and selection never rested on the Record slot: dismissing the sheet leaves the
        // user exactly where they were.
        app.swipeDown(velocity: .fast)
        require(app.tabBars.buttons["Hood"])
        XCTAssertTrue(app.tabBars.buttons["Hood"].isSelected)
    }

    func testHandoverTabHostsTheExportSurface() {
        let app = launchUnderhoodDemo()
        tapTab("Handover", in: app)
        require(app.navigationBars["Handover"])
        requireText(containing: "CSV record-data export", in: app)
    }

    func testTrendsRowPresentsTheUnmodifiedStats() {
        let app = launchUnderhoodDemo()
        let trends = app.buttons["hood.trends.row"]
        require(trends)
        trends.tap()
        require(app.navigationBars["Stats"])
    }

    /// Same launch contract as `launchDemo`, minus its hardcoded "Dashboard" wait (that tab does
    /// not exist in this arm) and plus the arm-forcing environment.
    private func launchUnderhoodDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["LOCAL_DEMO_MODE", "UI_TEST_PRO"]
        app.launchEnvironment["EXPERIMENT_FORCE_DESIGN_ARM"] = "variant_a"
        app.launch()
        require(app.tabBars.buttons["Hood"])
        let vehicleSwitcher = app.buttons["vehicle.switcher"]
        require(vehicleSwitcher)
        let vehicleLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Viper ACR"),
            object: vehicleSwitcher
        )
        XCTAssertEqual(XCTWaiter.wait(for: [vehicleLoaded], timeout: JourneyTestCase.timeout), .completed)
        return app
    }
}
