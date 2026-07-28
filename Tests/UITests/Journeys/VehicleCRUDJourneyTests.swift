import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class VehicleCRUDJourneyTests: JourneyTestCase {
    func testDashboardReloadsEntriesForTheNewlySelectedVehicle() {
        let app = launchDemo()
        let viperEntry = app.staticTexts["entry.row.odometer.18240"]
        require(viperEntry)

        tapWhenHittable(app.buttons["vehicle.switcher"])
        tapWhenHittable(app.buttons["Daily SQ5"])

        require(app.staticTexts["entry.row.odometer.82440"])
        XCTAssertFalse(viperEntry.exists, "Dashboard must not retain the previous vehicle's entries after switching.")
    }

    func testProDemoAddsAndSelectsVehicleFromSwitcher() {
        let app = launchDemo(pro: true)
        openVehicleForm(in: app)

        replaceText(in: app.textFields["vehicle.form.nickname"], with: "Journey GT3")
        replaceText(in: app.textFields["vehicle.form.make"], with: "Porsche")
        replaceText(in: app.textFields["vehicle.form.model"], with: "911 GT3")
        replaceText(in: app.textFields["vehicle.form.year"], with: "2022")
        replaceText(in: app.textFields["vehicle.form.odometer"], with: "1200")
        dismissKeyboard(in: app)

        let save = app.buttons["vehicle.form.save"]
        revealAndTap(save, in: app)
        requireGone(save)

        let switcher = app.buttons["vehicle.switcher"]
        tapWhenHittable(switcher)
        let addedVehicle = app.buttons["Journey GT3"]
        tapWhenHittable(addedVehicle)
        require(app.staticTexts["Journey GT3"])
    }

    /// Rewritten when the cap became a preflight. This used to walk the whole vehicle form and
    /// assert the server's rejection banner — i.e. it asserted the dead end itself: a free user
    /// filling six fields and waiting for a round trip to be told "no" by a button reading
    /// "Try Again". That path is gone by design, and the server rule it exercised is covered
    /// directly by VehicleServiceTests, so nothing is lost by asserting the new behaviour instead.
    func testFreeDemoOffersProAtTheVehicleCapInsteadOfTheForm() {
        let app = launchDemo()
        tapWhenHittable(app.buttons["vehicle.switcher"])
        tapWhenHittable(app.buttons["vehicle.switcher.add"])

        // The paywall, not the vehicle form — and specifically before any data entry is wasted.
        require(app.buttons["subscription.refresh"])
        XCTAssertFalse(
            app.textFields["vehicle.form.nickname"].exists,
            "A capped free user must not be walked through the vehicle form before being told."
        )
    }

    private func openVehicleForm(in app: XCUIApplication) {
        let switcher = app.buttons["vehicle.switcher"]
        tapWhenHittable(switcher)
        let addVehicle = app.buttons["vehicle.switcher.add"]
        tapWhenHittable(addVehicle)
        require(app.textFields["vehicle.form.nickname"])
    }
}
