import XCTest

@MainActor
final class EntryCreationTests: XCTestCase {
    func testLocalDemoOpensTheRealFuelEntryForm() {
        let app = XCUIApplication()
        app.launchArguments = ["LOCAL_DEMO_MODE", "UI_TEST_PRO"]
        app.launch()

        XCTAssertTrue(app.buttons["entry.add"].waitForExistence(timeout: 10))
        app.buttons["entry.add"].tap()
        XCTAssertTrue(app.buttons["entry.picker.fuel"].waitForExistence(timeout: 5))
        app.buttons["entry.picker.fuel"].tap()

        XCTAssertTrue(app.textFields["fuel.form.gallons"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entry.form.save"].exists)
    }
}
