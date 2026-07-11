import XCTest

@MainActor
final class EntryCreationTests: XCTestCase {
    func testLocalDemoOpensTheRealFuelEntryForm() {
        let app = XCUIApplication()
        app.launchArguments = ["LOCAL_DEMO_MODE", "UI_TEST_PRO"]
        app.launch()

        tapWhenHittable(app.buttons["entry.add"], timeout: 10)
        tapWhenHittable(app.buttons["entry.picker.fuel"], timeout: 5)

        XCTAssertTrue(app.textFields["fuel.form.gallons"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entry.form.save"].exists)
    }
}
