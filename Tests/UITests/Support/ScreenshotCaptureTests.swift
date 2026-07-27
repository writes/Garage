import XCTest

/// Captures App Store screenshots from the seeded demo build.
///
/// Not a correctness test — it asserts only enough to guarantee a screen actually rendered before
/// the shutter fires, so a blank or half-loaded frame can never be shipped to the product page.
/// Screenshots land as `.keepAlways` attachments in the .xcresult and are extracted by
/// `scripts/release/capture_screenshots.sh`.
///
/// Runs Pro so the gated surfaces (attachments, themes, stats) are populated rather than showing
/// upsell placeholders — the product page should show the product, not the fence around it.
@MainActor
final class ScreenshotCaptureTests: JourneyTestCase {
    /// Ordered so the first three — which Apple renders directly inside search results — carry the
    /// strongest conversion weight: the dashboard, the service history, then the cost story.
    func testCaptureAppStoreScreenshots() {
        let app = launchDemo(pro: true)

        capture(app, named: "01-dashboard")

        tapTab(app, "Log")
        capture(app, named: "02-log")

        tapTab(app, "Stats")
        capture(app, named: "03-stats")

        tapTab(app, "Garage")
        capture(app, named: "04-garage")

        tapTab(app, "Settings")
        capture(app, named: "05-settings")
    }

    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        tapWhenHittable(tab)
        // The shutter must not fire mid-transition; wait for the tab to actually take selection.
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: tab
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selected], timeout: JourneyTestCase.timeout), .completed,
            "\(name) tab never became selected — a screenshot here would capture a transition"
        )
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        _ = app.tabBars.firstMatch.waitForExistence(timeout: JourneyTestCase.timeout)

        // Let transient states settle. The first capture caught the sync badge mid-"Checking log
        // sync", which is honest but reads as a stuck spinner on a product page. Charts also need
        // a beat to draw.
        let syncBadge = app.staticTexts["sync.badge"]
        if syncBadge.exists {
            let settled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label != %@ AND label != %@",
                                       "Checking log sync", "Syncing"),
                object: syncBadge
            )
            _ = XCTWaiter.wait(for: [settled], timeout: 8)
        }
        Thread.sleep(forTimeInterval: 3.0)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
