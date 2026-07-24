import XCTest

@MainActor
extension XCTestCase {
    func tapWhenHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected hittable \(element)", file: file, line: line)
        guard result == .completed else { return }
        element.tap()
    }
}

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
        // The switcher's accessibilityValue announces the vehicle NAME (a11y sweep replaced the
        // raw Firestore id, which VoiceOver users heard as a UUID).
        let vehicleLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Viper ACR"),
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
        tapWhenHittable(field)
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
        tapWhenHittable(tab)
    }

    func revealAndTap(_ element: XCUIElement, in app: XCUIApplication) {
        require(element)
        for _ in 0..<3 where !element.isHittable {
            app.swipeUp()
        }
        tapWhenHittable(element)
    }

    func returnToGarage(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons["Garage"]
        tapWhenHittable(backButton)
    }

    func dismissSheet(in app: XCUIApplication, waitingFor element: XCUIElement) {
        let close = app.buttons["sheet.dismiss"]
        tapWhenHittable(close)
        requireGone(element)
    }

    func dismissSheetIfPresented(in app: XCUIApplication) {
        let close = app.buttons["sheet.dismiss"]
        guard close.waitForExistence(timeout: 5) else { return }
        tapWhenHittable(close, timeout: 5)
        requireGone(close)
    }

    func requireText(containing text: String, in app: XCUIApplication) {
        let matchingText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", text)
        ).firstMatch
        require(matchingText)
    }
}
