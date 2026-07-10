import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class LogSearchFilterJourneyTests: JourneyTestCase {
    func testSeededLogSearchAndTypeFilterConstrainThenRestoreRows() {
        let app = launchDemo()
        tapTab("Log", in: app)

        let trackRow = app.buttons["log.row.seed-viper-track"]
        let oilRow = app.buttons["log.row.seed-viper-oil"]
        require(trackRow)
        require(oilRow)

        replaceText(in: app.textFields["log.search"], with: "HPDE")
        require(trackRow)
        XCTAssertFalse(oilRow.exists)

        replaceText(in: app.textFields["log.search"], with: "")
        require(oilRow)

        let filter = app.buttons["log.filter"]
        require(filter)
        filter.tap()
        let oilFilter = app.switches["log.filter.oil_change"]
        require(oilFilter)
        oilFilter.tap()
        dismissSheet(in: app, waitingFor: oilFilter)

        require(oilRow)
        XCTAssertFalse(trackRow.exists)
        XCTAssertFalse(app.buttons["log.row.seed-viper-brake"].exists)

        filter.tap()
        require(oilFilter)
        oilFilter.tap()
        dismissSheet(in: app, waitingFor: oilFilter)
        require(trackRow)
        require(oilRow)
    }
}
