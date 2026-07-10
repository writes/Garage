import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class PaywallRoutingJourneyTests: JourneyTestCase {
    func testFreeGatesRouteFromGarageRemindersAndExportToSubscription() {
        let app = launchDemo()

        tapTab("Garage", in: app)
        routeToSubscription(from: app.buttons["garage.gate.cta"], in: app)
        dismissSheet(in: app, waitingFor: app.buttons["subscription.refresh"])

        tapTab("Settings", in: app)
        let reminders = app.buttons["settings.reminders"]
        require(reminders)
        reminders.tap()
        routeToSubscription(from: app.buttons["reminder.gate.cta"], in: app)
        dismissSheet(in: app, waitingFor: app.buttons["subscription.refresh"])

        let settingsBack = app.navigationBars.buttons["Settings"]
        require(settingsBack)
        settingsBack.tap()
        let export = app.buttons["settings.export"]
        require(export)
        export.tap()
        routeToSubscription(from: app.buttons["export.gate.cta"], in: app)
    }

    func testProDemoLeavesGarageRemindersAndExportUnlocked() {
        let app = launchDemo(pro: true)

        tapTab("Garage", in: app)
        require(app.buttons["garage.gallery"])
        XCTAssertFalse(app.buttons["garage.gate.cta"].exists)

        tapTab("Settings", in: app)
        let reminders = app.buttons["settings.reminders"]
        require(reminders)
        reminders.tap()
        require(app.textFields["reminder.form.title"])

        let settingsBack = app.navigationBars.buttons["Settings"]
        require(settingsBack)
        settingsBack.tap()
        let export = app.buttons["settings.export"]
        require(export)
        export.tap()
        require(app.buttons["export.buildCSV"])
        XCTAssertFalse(app.buttons["export.gate.cta"].exists)
    }

    private func routeToSubscription(from gate: XCUIElement, in app: XCUIApplication) {
        require(gate)
        gate.tap()
        require(app.buttons["subscription.refresh"])
    }
}
