import XCTest

/// Hermetic UI-routing journey: LOCAL_DEMO_MODE only; no live Firebase or RevenueCat evidence.
@MainActor
final class EntryCreateJourneyTests: JourneyTestCase {
    func testFuelEntryPersistsToLogAndDashboardWithinDemoSession() {
        let app = launchDemo(pro: true)
        openFuelForm(in: app)
        require(app.staticTexts["Highest recorded: 18,240 mi"])

        replaceText(in: app.textFields["fuel.form.gallons"], with: "12.4")
        replaceText(in: app.textFields["fuel.form.price"], with: "4.10")
        replaceText(in: app.textFields["fuel.form.total"], with: "50.84")
        replaceText(in: app.textFields["fuel.form.station"], with: "Journey Fuel Station")
        replaceText(in: app.textFields["entry.form.odometer"], with: "18275")
        dismissKeyboard(in: app)

        let save = app.buttons["entry.form.save"]
        revealAndTap(save, in: app)
        requireGone(save)
        dismissSheetIfPresented(in: app)

        tapTab("Log", in: app)
        require(app.staticTexts["entry.row.odometer.18275"])

        tapTab("Dashboard", in: app)
        require(app.staticTexts["entry.row.odometer.18275"])
    }

    func testRegressiveOdometerShowsValidationAndDoesNotSave() {
        let app = launchDemo(pro: true)
        openFuelForm(in: app)
        require(app.staticTexts["Highest recorded: 18,240 mi"])

        replaceText(in: app.textFields["entry.form.odometer"], with: "100")
        dismissKeyboard(in: app)
        revealAndTap(app.buttons["entry.form.save"], in: app)

        requireText(containing: "Odometer conflicts with the 18,240 mi entry", in: app)
        XCTAssertTrue(app.buttons["entry.form.save"].exists)
        XCTAssertFalse(app.staticTexts["entry.row.odometer.100"].exists)
    }

    func testFuelEntryFormRetainsSaveAndHidesAttachmentPersistenceUI() {
        let app = launchDemo(pro: true)
        openFuelForm(in: app)

        let activeForm = app.otherElements["entry.form.sheet"]
        require(activeForm)

        let save = activeForm.buttons["entry.form.save"]
        require(save)
        assertAttachmentPersistenceUIIsAbsent(in: activeForm)
        revealAndTap(save, in: app)
    }

    private func openFuelForm(in app: XCUIApplication) {
        let addEntry = app.buttons["entry.add"]
        tapWhenHittable(addEntry)
        let fuel = app.buttons["entry.picker.fuel"]
        tapWhenHittable(fuel)
        require(app.textFields["fuel.form.gallons"])
    }

    private func assertAttachmentPersistenceUIIsAbsent(in activeForm: XCUIElement) {
        for (description, element) in knownAttachmentElements(in: activeForm) {
            XCTAssertFalse(element.exists, "Unexpected \(description) in the fuel entry form.")
        }

        XCTAssertEqual(
            attachmentPersistenceControls(in: activeForm).count,
            0,
            "No attachment-persistence control may be reachable from the fuel entry form."
        )
        XCTAssertEqual(
            attachmentPresentation(in: activeForm).count,
            0,
            "No pending attachment heading, description, or filename may be presented in the fuel entry form."
        )
    }

    private func knownAttachmentElements(in activeForm: XCUIElement) -> [(String, XCUIElement)] {
        [
            ("Add Photo control", activeForm.buttons["Add Photo"]),
            ("Add PDF control", activeForm.buttons["Add PDF"]),
            ("Attachments heading", activeForm.staticTexts["Attachments"]),
            (
                "pending attachment description",
                activeForm.staticTexts["Receipts, invoices, and related photos show up here after selection."]
            ),
            ("pending photo filename", activeForm.staticTexts["photo-pending.jpg"]),
            ("pending PDF filename", activeForm.staticTexts["pending-receipt.pdf"])
        ]
    }

    private func attachmentPersistenceControls(in activeForm: XCUIElement) -> XCUIElementQuery {
        activeForm.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ " +
                    "OR label CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
                "attachment",
                "photo",
                "pdf",
                "attachment"
            )
        )
    }

    private func attachmentPresentation(in activeForm: XCUIElement) -> XCUIElementQuery {
        activeForm.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ " +
                    "OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "attachment",
                "receipt",
                "photo",
                "pdf"
            )
        )
    }
}
