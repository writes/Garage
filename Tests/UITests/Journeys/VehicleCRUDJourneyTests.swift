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

    func testFreeDemoShowsVehicleLimitSurfaceForAdditionalVehicle() {
        let app = launchDemo()
        openVehicleForm(in: app)

        replaceText(in: app.textFields["vehicle.form.nickname"], with: "Limit Probe")
        replaceText(in: app.textFields["vehicle.form.make"], with: "Ford")
        replaceText(in: app.textFields["vehicle.form.model"], with: "GT")
        replaceText(in: app.textFields["vehicle.form.odometer"], with: "100")
        dismissKeyboard(in: app)

        revealAndTap(app.buttons["vehicle.form.save"], in: app)
        require(app.descendants(matching: .any)["vehicle.form.error"])
        require(app.staticTexts["Free accounts are limited to 1 vehicle. Upgrade to Pro for up to 5 vehicles."])
    }

    private func openVehicleForm(in app: XCUIApplication) {
        let switcher = app.buttons["vehicle.switcher"]
        tapWhenHittable(switcher)
        let addVehicle = app.buttons["vehicle.switcher.add"]
        tapWhenHittable(addVehicle)
        require(app.textFields["vehicle.form.nickname"])
    }
}
