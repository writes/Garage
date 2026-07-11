import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class EntryCreateJourneyTests: JourneyTestCase {
    func testFuelEntryPersistsToLogAndDashboardWithinDemoSession() {
        let app = launchDemo(pro: true)
        openFuelForm(in: app)
        require(app.staticTexts["Last recorded: 18,240 mi"])

        replaceText(in: app.textFields["fuel.form.gallons"], with: "12.4")
        replaceText(in: app.textFields["fuel.form.price"], with: "4.10")
        replaceText(in: app.textFields["fuel.form.total"], with: "50.84")
        replaceText(in: app.textFields["fuel.form.station"], with: "Journey Fuel Station")
        replaceText(in: app.textFields["entry.form.odometer"], with: "18275")
        dismissKeyboard(in: app)

        let save = app.buttons["entry.form.save"]
        revealAndTap(save, in: app)
        requireGone(save)
        dismissSheetIfPresented(in: app)

        tapTab("Log", in: app)
        require(app.staticTexts["entry.row.odometer.18275"])

        tapTab("Dashboard", in: app)
        require(app.staticTexts["entry.row.odometer.18275"])
    }

    func testRegressiveOdometerShowsValidationAndDoesNotSave() {
        let app = launchDemo(pro: true)
        openFuelForm(in: app)
        require(app.staticTexts["Last recorded: 18,240 mi"])

        replaceText(in: app.textFields["entry.form.odometer"], with: "100")
        dismissKeyboard(in: app)
        revealAndTap(app.buttons["entry.form.save"], in: app)

        requireText(containing: "Odometer must be at least 18,240.", in: app)
        XCTAssertTrue(app.buttons["entry.form.save"].exists)
        XCTAssertFalse(app.staticTexts["entry.row.odometer.100"].exists)
    }

    private func openFuelForm(in app: XCUIApplication) {
        let addEntry = app.buttons["entry.add"]
        tapWhenHittable(addEntry)
        let fuel = app.buttons["entry.picker.fuel"]
        tapWhenHittable(fuel)
        require(app.textFields["fuel.form.gallons"])
    }
}
