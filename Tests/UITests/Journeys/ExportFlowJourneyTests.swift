import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class ExportFlowJourneyTests: JourneyTestCase {
    func testFreeDemoBuildsAndSharesCSVWhilePDFRemainsGated() {
        let app = launchDemo()
        openExport(in: app)

        require(app.staticTexts["Raw data export — free forever"])
        require(app.buttons["export.buildCSV"])
        require(app.buttons["export.gate.cta"])
        XCTAssertFalse(app.buttons["export.buildPDF"].exists)

        revealAndTap(app.buttons["export.buildCSV"], in: app)
        require(app.descendants(matching: .any)["export.shareCSV"])
    }

    func testProDemoBuildsShareableCSVExport() {
        let app = launchDemo(pro: true)
        openExport(in: app)

        require(app.buttons["export.buildPDF"])
        XCTAssertFalse(app.buttons["export.gate.cta"].exists)
        revealAndTap(app.buttons["export.buildCSV"], in: app)
        require(app.descendants(matching: .any)["export.shareCSV"])
    }

    private func openExport(in app: XCUIApplication) {
        tapTab("Settings", in: app)
        let export = app.buttons["settings.export"]
        tapWhenHittable(export)
    }
}
