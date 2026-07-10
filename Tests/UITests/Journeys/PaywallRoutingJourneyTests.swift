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
        tapWhenHittable(reminders)
        routeToSubscription(from: app.buttons["reminder.gate.cta"], in: app)
        dismissSheet(in: app, waitingFor: app.buttons["subscription.refresh"])

        let settingsBack = app.navigationBars.buttons["Settings"]
        tapWhenHittable(settingsBack)
        let export = app.buttons["settings.export"]
        tapWhenHittable(export)
        routeToSubscription(from: app.buttons["export.gate.cta"], in: app)
    }

    func testProDemoLeavesGarageRemindersAndExportUnlocked() {
        let app = launchDemo(pro: true)

        tapTab("Garage", in: app)
        require(app.buttons["garage.gallery"])
        XCTAssertFalse(app.buttons["garage.gate.cta"].exists)

        tapTab("Settings", in: app)
        let reminders = app.buttons["settings.reminders"]
        tapWhenHittable(reminders)
        require(app.textFields["reminder.form.title"])

        let settingsBack = app.navigationBars.buttons["Settings"]
        tapWhenHittable(settingsBack)
        let export = app.buttons["settings.export"]
        tapWhenHittable(export)
        require(app.buttons["export.buildCSV"])
        XCTAssertFalse(app.buttons["export.gate.cta"].exists)
    }

    func testSubscriptionOffersRestorePurchasesControl() {
        let app = launchDemo()

        tapTab("Garage", in: app)
        routeToSubscription(from: app.buttons["garage.gate.cta"], in: app)

        let restore = app.buttons["subscription.restore"]
        require(restore)
        tapWhenHittable(restore)
    }

    func testSubscriptionShowsTermsAndPrivacyLinksBeforePurchase() {
        let app = launchDemo()

        tapTab("Garage", in: app)
        routeToSubscription(from: app.buttons["garage.gate.cta"], in: app)

        require(app.links["subscription.terms"])
        require(app.links["subscription.privacy"])
    }

    private func routeToSubscription(from gate: XCUIElement, in app: XCUIApplication) {
        tapWhenHittable(gate)
        require(app.buttons["subscription.refresh"])
    }
}
