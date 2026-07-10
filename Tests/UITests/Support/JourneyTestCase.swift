import XCTest

@MainActor
class JourneyTestCase: XCTestCase {
    static let timeout: TimeInterval = 12

    func launchDemo(pro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = pro
            ? ["LOCAL_DEMO_MODE", "UI_TEST_PRO"]
            : ["LOCAL_DEMO_MODE"]
        app.launch()
        require(app.tabBars.buttons["Dashboard"])
        let vehicleSwitcher = app.buttons["vehicle.switcher"]
        require(vehicleSwitcher)
        let vehicleLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "seed-viper"),
            object: vehicleSwitcher
        )
        XCTAssertEqual(XCTWaiter.wait(for: [vehicleLoaded], timeout: JourneyTestCase.timeout), .completed)
        return app
    }

    func require(
        _ element: XCUIElement,
        timeout: TimeInterval = JourneyTestCase.timeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected \(element)", file: file, line: line)
    }

    func requireGone(
        _ element: XCUIElement,
        timeout: TimeInterval = JourneyTestCase.timeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Expected \(element) to disappear",
            file: file,
            line: line
        )
    }

    func replaceText(in field: XCUIElement, with text: String) {
        require(field)
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        if !text.isEmpty {
            field.typeText(text)
        }
    }

    func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.05)).tap()
    }

    func tapTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        require(tab)
        tab.tap()
    }

    func revealAndTap(_ element: XCUIElement, in app: XCUIApplication) {
        require(element)
        for _ in 0..<3 where !element.isHittable {
            app.swipeUp()
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: JourneyTestCase.timeout), .completed)
        element.tap()
    }

    func returnToGarage(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons["Garage"]
        require(backButton)
        backButton.tap()
    }

    func dismissSheet(in app: XCUIApplication, waitingFor element: XCUIElement) {
        let close = app.buttons["sheet.dismiss"]
        require(close)
        close.tap()
        requireGone(element)
    }

    func dismissSheetIfPresented(in app: XCUIApplication) {
        let close = app.buttons["sheet.dismiss"]
        guard close.waitForExistence(timeout: 5) else { return }
        close.tap()
        requireGone(close)
    }

    func requireText(containing text: String, in app: XCUIApplication) {
        let matchingText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", text)
        ).firstMatch
        require(matchingText)
    }
}
