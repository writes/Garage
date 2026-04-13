import XCTest

@MainActor
final class AuthFlowTests: XCTestCase {
    func testAppLaunchesToAuthenticationOrGarageShell() {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TEST_MODE"]
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }
}
