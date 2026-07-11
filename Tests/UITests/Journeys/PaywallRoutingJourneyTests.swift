import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class PaywallRoutingJourneyTests: JourneyTestCase {
    func testFreeGatesRouteFromGarageRemindersAndPDFReportsToSubscription() {
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
        require(app.buttons["export.buildCSV"])
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
        require(app.buttons["export.buildPDF"])
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

        // SwiftUI Link's XCUITest element type is implementation-dependent (it may be
        // exposed as a button rather than a link). The stable contract is its identifier.
        let terms = app.descendants(matching: .any)["subscription.terms"]
        let privacy = app.descendants(matching: .any)["subscription.privacy"]
        require(terms)
        require(privacy)
        XCTAssertTrue(terms.isHittable, "Terms of Use must be visible before purchase")
        XCTAssertTrue(privacy.isHittable, "Privacy Policy must be visible before purchase")
    }

    private func routeToSubscription(from gate: XCUIElement, in app: XCUIApplication) {
        tapWhenHittable(gate)
        require(app.buttons["subscription.refresh"])
    }
}
