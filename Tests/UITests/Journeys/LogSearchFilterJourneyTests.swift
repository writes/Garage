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
        tapWhenHittable(filter)
        let oilFilter = app.switches["log.filter.oil_change"]
        tapWhenHittable(oilFilter)
        dismissSheet(in: app, waitingFor: oilFilter)

        require(oilRow)
        XCTAssertFalse(trackRow.exists)
        XCTAssertFalse(app.buttons["log.row.seed-viper-brake"].exists)

        tapWhenHittable(filter)
        tapWhenHittable(oilFilter)
        dismissSheet(in: app, waitingFor: oilFilter)
        require(trackRow)
        require(oilRow)
    }
}
