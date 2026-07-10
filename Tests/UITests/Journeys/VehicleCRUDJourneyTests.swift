import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class VehicleCRUDJourneyTests: JourneyTestCase {
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
        require(switcher)
        switcher.tap()
        let addedVehicle = app.buttons["Journey GT3"]
        require(addedVehicle)
        addedVehicle.tap()
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
        require(app.staticTexts["Free accounts are limited to 1 vehicle. Upgrade to Pro for unlimited."])
    }

    private func openVehicleForm(in app: XCUIApplication) {
        let switcher = app.buttons["vehicle.switcher"]
        require(switcher)
        switcher.tap()
        let addVehicle = app.buttons["vehicle.switcher.add"]
        require(addVehicle)
        addVehicle.tap()
        require(app.textFields["vehicle.form.nickname"])
    }
}
