import XCTest

@MainActor
final class EntryCreationTests: XCTestCase {
    func testAppLaunchesForEntryCreationFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TEST_MODE"]
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }
}
