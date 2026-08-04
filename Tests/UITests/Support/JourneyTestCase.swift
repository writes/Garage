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

    /// `extraArguments` exists for state the demo seeds one way and a journey needs the other way
    /// round (AI consent is seeded GRANTED so the other journeys never meet the first-use gate).
    func launchDemo(pro: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (pro
            ? ["LOCAL_DEMO_MODE", "UI_TEST_PRO"]
            : ["LOCAL_DEMO_MODE"]) + extraArguments
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

    /// `app` is defaulted so the ~20 existing call sites stay unchanged; `XCUIApplication()` is a
    /// proxy for the same target app every journey launches, not a second application.
    ///
    /// Reveals before tapping: the keyboard raised by the PREVIOUS field can cover this one on the
    /// smallest canvas (375x667 — which is exactly what iPad compatibility mode renders), and a
    /// bare `tapWhenHittable` then times out on a field a real user would simply scroll to.
    func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication = XCUIApplication()) {
        revealAndTap(field, in: app)
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        if !text.isEmpty {
            field.typeText(text)
        }
    }

    func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        // Window-anchored, not app-anchored — same coordinate-space constraint as `scrollStep`.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.05)).tap()
    }

    func tapTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        tapWhenHittable(tab)
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
