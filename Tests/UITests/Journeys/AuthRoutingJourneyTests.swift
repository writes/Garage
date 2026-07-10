import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class AuthRoutingJourneyTests: JourneyTestCase {
    func testDemoShellRoutesToLoginAfterSignOut() {
        let app = launchDemo()

        ["Dashboard", "Log", "Garage", "Stats", "Settings"].forEach {
            require(app.tabBars.buttons[$0])
        }

        tapTab("Settings", in: app)
        let signOut = app.buttons["settings.signout"]
        require(signOut)
        signOut.tap()

        require(app.buttons["login.googleButton"])
        XCTAssertFalse(app.tabBars.buttons["Dashboard"].exists)
    }
}
