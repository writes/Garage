import XCTest

@MainActor
final class AuthFlowTests: XCTestCase {
    func testLocalDemoLaunchesToTheRealGarageShell() {
        let app = XCUIApplication()
        app.launchArguments = ["LOCAL_DEMO_MODE"]
        app.launch()

        XCTAssertTrue(app.buttons["entry.add"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["sync.badge"].exists)
    }
}
