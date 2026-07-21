import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class ExportFlowJourneyTests: JourneyTestCase {
    func testFreeDemoBuildsAndSharesCSVWhileRecordPDFRemainsGated() {
        let app = launchDemo()
        openExport(in: app)

        require(app.staticTexts["CSV record-data export"])
        require(app.buttons["export.buildCSV"])
        require(app.buttons["export.gate.cta"])
        require(
            app.staticTexts[
                "This CSV contains this vehicle's record history only. " +
                    "Photo and receipt files are not included."
            ]
        )
        requireText(containing: "Upgrade to generate a record PDF.", in: app)
        requireText(containing: "Photo, receipt, and invoice files are not included", in: app)
        requireText(containing: "sharing or saving are unavailable in this beta.", in: app)
        XCTAssertFalse(app.buttons["export.buildPDF"].exists)
        assertMediaTogglesAreUnavailable(in: app)
        assertLegacyExportCopyIsUnavailable(in: app)

        revealAndTap(app.buttons["export.buildCSV"], in: app)
        require(app.descendants(matching: .any)["export.shareCSV"])
    }

    func testProDemoShowsBoundedRecordPDFAndShareableCSVExport() {
        let app = launchDemo(pro: true)
        openExport(in: app)

        require(app.buttons["export.buildPDF"])
        XCTAssertFalse(app.buttons["export.gate.cta"].exists)
        require(
            app.staticTexts[
                "This record-only PDF does not include photo, receipt, " +
                    "or invoice files. Sharing and saving are unavailable in this beta."
            ]
        )
        assertMediaTogglesAreUnavailable(in: app)
        assertLegacyExportCopyIsUnavailable(in: app)
        revealAndTap(app.buttons["export.buildCSV"], in: app)
        require(app.descendants(matching: .any)["export.shareCSV"])
        revealAndTap(app.buttons["export.buildPDF"], in: app)
        require(app.descendants(matching: .any)["export.pdfResult"])
    }

    private func openExport(in app: XCUIApplication) {
        tapTab("Settings", in: app)
        let export = app.buttons["settings.export"]
        tapWhenHittable(export)
    }

    private func assertMediaTogglesAreUnavailable(in app: XCUIApplication) {
        XCTAssertFalse(app.switches["Photo gallery"].exists)
        XCTAssertFalse(app.switches["Receipts & invoices"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["export.toggle.galleryPhotos"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["export.toggle.photoGallery"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["export.toggle.receipts"].exists)
    }

    private func assertLegacyExportCopyIsUnavailable(in app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts["Include gallery photos"].exists)
        XCTAssertFalse(app.staticTexts["Include receipts and invoices"].exists)
        XCTAssertFalse(app.buttons["Build PDF Report"].exists)
        XCTAssertFalse(app.staticTexts["PDF reports are part of Pro"].exists)
        XCTAssertFalse(app.staticTexts["Upgrade to generate PDF report exports."].exists)
    }
}
