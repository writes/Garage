import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class RemindersGateJourneyTests: JourneyTestCase {
    func testFreeDemoShowsReminderProGate() {
        let app = launchDemo()
        tapTab("Settings", in: app)
        let reminders = app.buttons["settings.reminders"]
        require(reminders)
        reminders.tap()

        require(app.buttons["reminder.gate.cta"])
        XCTAssertFalse(app.textFields["reminder.form.title"].exists)
    }

    func testProDemoCreatesReminderShownOnDashboard() {
        let app = launchDemo(pro: true)
        tapTab("Settings", in: app)
        let reminders = app.buttons["settings.reminders"]
        require(reminders)
        reminders.tap()

        replaceText(in: app.textFields["reminder.form.title"], with: "Journey Reminder")
        replaceText(in: app.textFields["reminder.form.mileage"], with: "19000")
        replaceText(in: app.textFields["reminder.form.months"], with: "6")
        dismissKeyboard(in: app)
        revealAndTap(app.buttons["reminder.form.save"], in: app)
        require(app.staticTexts["reminder.form.saved"])
        XCTAssertEqual(app.textFields["reminder.form.title"].value as? String, "Journey Reminder")

        tapTab("Dashboard", in: app)
        require(app.staticTexts["dashboard.reminder.Journey Reminder"])
    }
}
