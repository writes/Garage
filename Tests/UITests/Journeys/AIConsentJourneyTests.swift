import XCTest

/// Hermetic UI-routing journey for the first-use AI consent gate (App Review 5.1.2(i)).
/// LOCAL_DEMO_MODE only; no live Firebase, Claude, or RevenueCat evidence.
///
/// Demo/UI-test profiles are seeded ALREADY CONSENTED so the other journeys never meet the gate;
/// `UI_TEST_AI_CONSENT_UNSET` seeds the opposite for the ones that have to drive it.
@MainActor
final class AIConsentJourneyTests: JourneyTestCase {
    /// Continue is NOT tapped here: it proceeds with the parked action, which starts the real
    /// microphone and raises a system speech-permission alert that would outlive this test and
    /// block the next journey. The grant leg is driven from the Settings switch below, and the
    /// sheet's own Continue path is covered in AIConsentTests.
    func testUnconsentedVoiceEntryPromptsAndNotNowLeavesNoConsent() {
        let app = launchDemo(pro: true, extraArguments: ["UI_TEST_AI_CONSENT_UNSET"])
        openVoiceSheet(in: app)

        tapWhenHittable(app.buttons["voice.mic"])
        let consentContinue = app.buttons["ai.consent.continue"]
        require(consentContinue)
        XCTAssertTrue(app.buttons["ai.consent.notNow"].exists)

        tapWhenHittable(app.buttons["ai.consent.notNow"])
        requireGone(consentContinue)

        // Nothing was stored, so the very next upload-bearing tap asks again.
        tapWhenHittable(app.buttons["voice.mic"])
        require(consentContinue)
        tapWhenHittable(app.buttons["ai.consent.notNow"])
        requireGone(consentContinue)

        dismissSheetIfPresented(in: app)
        tapTab("Settings", in: app)
        let consentSwitch = app.switches["settings.aiConsent"]
        require(consentSwitch)
        requireSwitchValue(consentSwitch, "0")
    }

    /// A consented account never sees the sheet again — the whole point of a ONE-time gate.
    func testConsentedVoiceEntryNeverShowsTheSheet() {
        let app = launchDemo(pro: true)
        openVoiceSheet(in: app)

        tapWhenHittable(app.buttons["voice.mic"])

        XCTAssertFalse(app.buttons["ai.consent.continue"].waitForExistence(timeout: 3))
        // Passing the gate starts the real recogniser, which raises the system speech-permission
        // alert. Terminate here so it cannot outlive this test and interrupt the next journey.
        app.terminate()
    }

    func testSettingsSwitchGrantsAndRevokesConsent() {
        let app = launchDemo(pro: true, extraArguments: ["UI_TEST_AI_CONSENT_UNSET"])
        tapTab("Settings", in: app)

        let consentSwitch = app.switches["settings.aiConsent"]
        require(consentSwitch)
        flip(consentSwitch)
        requireSwitchValue(consentSwitch, "1")

        flip(consentSwitch)
        requireSwitchValue(consentSwitch, "0")
    }

    /// The guard on the other journeys: without a launch override the demo profile is already
    /// consented, so no existing flow can be interrupted by the gate.
    func testDemoProfileIsSeededAlreadyConsented() {
        let app = launchDemo(pro: true)
        tapTab("Settings", in: app)

        let consentSwitch = app.switches["settings.aiConsent"]
        require(consentSwitch)
        requireSwitchValue(consentSwitch, "1")
    }

    private func openVoiceSheet(in app: XCUIApplication) {
        tapWhenHittable(app.buttons["entry.add"])
        tapWhenHittable(app.buttons["entry.picker.voice"])
        require(app.buttons["voice.mic"])
    }

    /// The identified element is the whole List ROW; only the inner control responds to a tap, and
    /// the row's centre lands on the label, which does nothing.
    private func flip(_ toggleRow: XCUIElement) {
        tapWhenHittable(toggleRow.switches.firstMatch)
    }

    /// The write is a Task hop behind the tap, so the switch settles asynchronously.
    private func requireSwitchValue(
        _ element: XCUIElement,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [settled], timeout: JourneyTestCase.timeout),
            .completed,
            "Expected switch value \(expected), got \(String(describing: element.value))",
            file: file,
            line: line
        )
    }
}
