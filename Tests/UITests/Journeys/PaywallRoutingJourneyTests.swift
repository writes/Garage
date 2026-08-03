import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class PaywallRoutingJourneyTests: JourneyTestCase {
    func testFreeGatesRouteFromGarageAndRecordPDFToSubscription() {
        let app = launchDemo()

        tapTab("Garage", in: app)
        routeToSubscription(from: app.buttons["garage.gate.cta"], in: app)
        dismissSheet(in: app, waitingFor: app.buttons["subscription.refresh"])

        tapTab("Settings", in: app)
        let reminders = app.buttons["settings.reminders"]
        tapWhenHittable(reminders)
        require(app.textFields["reminder.form.title"])
        XCTAssertFalse(app.buttons["reminder.gate.cta"].exists)

        let settingsBack = app.navigationBars.buttons["Settings"]
        tapWhenHittable(settingsBack)
        let export = app.buttons["settings.export"]
        tapWhenHittable(export)
        require(app.buttons["export.buildCSV"])
        require(app.staticTexts["CSV record-data export"])
        require(app.buttons["export.gate.cta"])
        routeToSubscription(from: app.buttons["export.gate.cta"], in: app)
    }

    func testProDemoLeavesGarageAndRecordPDFUnlockedWithoutMediaToggles() {
        let app = launchDemo(pro: true)

        tapTab("Garage", in: app)
        require(app.buttons["garage.gallery"])
        require(app.buttons["garage.wheels"])
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
        assertMediaTogglesAreUnavailable(in: app)
    }

    /// The locked theme preview is a Button wired straight to the paywall; the unit seam
    /// (ThemePickerRowTests) pins the row DATA, but only a journey proves the tap itself routes.
    /// A free user must see every scheme listed locked — and none selectable.
    func testFreeThemePickerListsLockedSchemesThatRouteToSubscription() {
        let app = launchDemo()

        tapTab("Settings", in: app)
        let theme = app.buttons["settings.theme"]
        tapWhenHittable(theme)
        require(app.buttons["themes.locked.row.classic"])
        require(app.buttons["themes.locked.row.plum"])
        XCTAssertFalse(app.buttons["theme.option.classic"].exists)
        routeToSubscription(from: app.buttons["themes.locked.row.classic"], in: app)
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
        require(
            app.staticTexts["Pro includes up to 5 vehicles, parts, detailing, warranty and recall records, and stats."]
        )
        require(app.staticTexts["Review the current plan and price before purchasing."])
        // The paywall now auto-loads offerings on appear (.task); in demo/UI-test mode there is no
        // gateway (PurchaseService.uiTest), so that load resolves .notReady, not .plansUnavailable —
        // the same status text a manual "Refresh Plans" tap would produce, since both call the same
        // refreshTapped() path. This is what "unavailable" reads as before purchase now.
        require(app.staticTexts["Subscriptions are unavailable right now. Check your connection and try again."])
    }

    private func routeToSubscription(from gate: XCUIElement, in app: XCUIApplication) {
        revealAndTap(gate, in: app)
        require(app.buttons["subscription.refresh"])
    }

    private func assertMediaTogglesAreUnavailable(in app: XCUIApplication) {
        XCTAssertFalse(app.switches["Photo gallery"].exists)
        XCTAssertFalse(app.switches["Receipts & invoices"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["export.toggle.galleryPhotos"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["export.toggle.photoGallery"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["export.toggle.receipts"].exists)
    }
}
