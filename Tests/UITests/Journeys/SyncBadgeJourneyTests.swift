import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class SyncBadgeJourneyTests: JourneyTestCase {
    func testDemoSyncBadgeNeverClaimsServerFreshnessWithoutBackendEvidence() {
        let app = launchDemo()
        let badge = app.staticTexts["sync.badge"]
        require(badge)
        XCTAssertTrue(
            ["Checking log sync", "Offline"].contains(badge.label),
            "Expected demo sync badge to avoid claiming server freshness; observed: \(badge.label)"
        )
    }
}
