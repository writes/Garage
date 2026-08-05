import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE + UI_TEST_PRO; no live service evidence.
@MainActor
final class GarageScreensJourneyTests: JourneyTestCase {
    func testProGarageScreensNavigateAndPersistSparePartWithinDemoSession() {
        let app = launchDemo(pro: true)
        tapTab("Garage", in: app)

        // The two record rows have no write path, so they must not read as peers of Spare Parts /
        // Detailing / Warranty, which do.
        XCTAssertEqual(app.buttons["garage.gallery"].value as? String, "Coming soon")
        XCTAssertEqual(app.buttons["garage.wheels"].value as? String, "Coming soon")
        XCTAssertNotEqual(app.buttons["garage.parts"].value as? String, "Coming soon")

        open(app.buttons["garage.gallery"], in: app)
        require(app.navigationBars["Gallery Records"])
        require(app.descendants(matching: .any)["garage.gallery.notice"])
        require(app.staticTexts["Photo records aren't available yet."])
        require(app.staticTexts["Gallery photo records are coming soon"])
        require(app.staticTexts["Support for gallery photo records is coming in a future update."])
        assertNoBetaOrDanglingPromiseCopy(in: app)
        XCTAssertFalse(app.staticTexts["Included in export"].exists)
        XCTAssertFalse(app.staticTexts["Hidden from export"].exists)
        returnToGarage(in: app)

        open(app.buttons["garage.wheels"], in: app)
        require(app.navigationBars["Wheel Records"])
        require(app.descendants(matching: .any)["garage.wheels.notice"])
        require(app.staticTexts["Photo records aren't available yet."])
        require(app.staticTexts["Wheel photo records are coming soon"])
        require(app.staticTexts["Support for wheel photo records is coming in a future update."])
        assertNoBetaOrDanglingPromiseCopy(in: app)
        XCTAssertFalse(app.staticTexts["Included in export"].exists)
        XCTAssertFalse(app.staticTexts["Hidden from export"].exists)
        returnToGarage(in: app)

        open(app.buttons["garage.parts"], in: app)
        addSparePart(in: app)
        require(app.staticTexts["Journey Brake Pads"])
        returnToGarage(in: app)

        open(app.buttons["garage.detailing"], in: app)
        require(app.staticTexts["Light polish and sealant"])
        returnToGarage(in: app)

        open(app.buttons["garage.warranty"], in: app)
        require(app.staticTexts["No warranty records yet"])
        require(app.staticTexts["No recall records yet"])
    }

    /// Guideline 2.2 pin: a shipping build must not describe itself as a beta anywhere a reviewer
    /// can reach, and the two record screens must not promise content their build cannot produce.
    private func assertNoBetaOrDanglingPromiseCopy(in app: XCUIApplication) {
        let betaCopy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'beta'"))
        XCTAssertEqual(betaCopy.count, 0, "No user-facing screen may describe the app as a beta")
        XCTAssertFalse(app.staticTexts["Existing gallery record details appear here when available."].exists)
        XCTAssertFalse(app.staticTexts["Existing wheel record details appear here when available."].exists)
    }

    private func open(_ element: XCUIElement, in app: XCUIApplication) {
        tapWhenHittable(element)
    }

    private func addSparePart(in app: XCUIApplication) {
        let add = app.buttons["parts.add"]
        tapWhenHittable(add)
        replaceText(in: app.textFields["parts.form.name"], with: "Journey Brake Pads")
        replaceText(in: app.textFields["parts.form.quantity"], with: "2")
        replaceText(in: app.textFields["parts.form.location"], with: "Test Shelf")
        dismissKeyboard(in: app)

        let save = app.buttons["parts.form.save"]
        revealAndTap(save, in: app)
        requireGone(save)
    }
}
