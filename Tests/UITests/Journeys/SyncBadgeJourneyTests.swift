import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class SyncBadgeJourneyTests: JourneyTestCase {
    func testDemoSyncBadgeIsPresentAndDeterministicallyUpToDate() {
        let app = launchDemo()
        let badge = app.staticTexts["sync.badge"]
        require(badge)
        XCTAssertEqual(badge.label, "Up to date")
    }
}
