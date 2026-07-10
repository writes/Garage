import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE + UI_TEST_PRO; no live service evidence.
@MainActor
final class GarageScreensJourneyTests: JourneyTestCase {
    func testProGarageScreensNavigateAndPersistSparePartWithinDemoSession() {
        let app = launchDemo(pro: true)
        tapTab("Garage", in: app)

        open(app.buttons["garage.gallery"], in: app)
        require(app.staticTexts["No gallery photos yet"])
        returnToGarage(in: app)

        open(app.buttons["garage.wheels"], in: app)
        require(app.navigationBars["Wheel Gallery"])
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
