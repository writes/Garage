import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class ProfilePersistenceJourneyTests: JourneyTestCase {
    func testDemoProfilePersistsAfterNavigatingAwayAndReturning() {
        let app = launchDemo()
        tapTab("Settings", in: app)
        let profile = app.buttons["settings.profile"]
        tapWhenHittable(profile)

        replaceText(in: app.textFields["profile.name"], with: "Journey Driver")
        replaceText(in: app.textFields["profile.phone"], with: "555-0199")
        dismissKeyboard(in: app)
        let save = app.buttons["profile.save"]
        tapWhenHittable(save)

        let settingsBack = app.navigationBars.buttons["Settings"]
        tapWhenHittable(settingsBack)
        tapWhenHittable(profile)

        let name = app.textFields["profile.name"]
        let phone = app.textFields["profile.phone"]
        require(name)
        require(phone)
        XCTAssertEqual(name.value as? String, "Journey Driver")
        XCTAssertEqual(phone.value as? String, "555-0199")
    }
}
