import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class ExportFlowJourneyTests: JourneyTestCase {
    func testFreeDemoShowsExportProGate() {
        let app = launchDemo()
        openExport(in: app)

        require(app.buttons["export.gate.cta"])
        XCTAssertFalse(app.buttons["export.buildCSV"].exists)
    }

    func testProDemoBuildsNonEmptyCSVExport() {
        let app = launchDemo(pro: true)
        openExport(in: app)

        let galleryToggle = app.switches["export.toggle.galleryPhotos"]
        require(galleryToggle)
        galleryToggle.tap()
        revealAndTap(app.buttons["export.buildCSV"], in: app)

        let result = app.staticTexts["export.result"]
        require(result)
        XCTAssertTrue(result.label.contains("bytes"))
        XCTAssertFalse(result.label.contains("0 bytes"))
    }

    private func openExport(in app: XCUIApplication) {
        tapTab("Settings", in: app)
        let export = app.buttons["settings.export"]
        require(export)
        export.tap()
    }
}
