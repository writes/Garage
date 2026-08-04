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
        // Reveal first: Sign Out is the LAST row of the Settings form, and on the smallest canvas
        // (375x667 — what iPad compatibility mode renders) it sits below the fold, behind the tab
        // bar. A real user scrolls the form to it; a bare hittable-wait just times out.
        let signOut = app.buttons["settings.signout"]
        revealAndTap(signOut, in: app)

        require(app.buttons["login.googleButton"])
        XCTAssertFalse(app.tabBars.buttons["Dashboard"].exists)
    }
}
