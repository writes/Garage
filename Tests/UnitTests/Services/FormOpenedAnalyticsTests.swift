import Foundation
import Testing
@testable import Garage

/// `form_opened` closes the intent side of the activation funnel: `first_vehicle_added` records
/// completion, but nothing recorded that the form was ever opened, so the open -> complete rate
/// was invisible.
///
/// The subtle requirement is that the event reports what ACTUALLY opened. `AppRouter.present`
/// redirects entry sheets to vehicle creation on a zero-vehicle account, and attributing that
/// open to `entry` would misreport the funnel at exactly the Day-0 moment that matters most.
@MainActor
struct FormOpenedAnalyticsTests {
    /// Records every event so ordering and double-emission are both observable.
    private final class AnalyticsSpy: AnalyticsTracking {
        var events: [AnalyticsEvent] = []
        func track(_ event: AnalyticsEvent) { events.append(event) }
        func setEnabled(_: Bool) {}
    }

    private func makeRouter(hasVehicles: Bool) -> (AppRouter, AnalyticsSpy) {
        let spy = AnalyticsSpy()
        return (AppRouter(hasVehicles: { hasVehicles }, analytics: spy), spy)
    }

    // MARK: - Contract

    @Test func formOpened_isInTheNameList_andNamesStayUnique() {
        #expect(AnalyticsEvent.activationFunnelNames.contains("form_opened"))
        #expect(Set(AnalyticsEvent.allNames).count == AnalyticsEvent.allNames.count)
    }

    @Test func formOpened_definitionCarriesFormAndSchemaVersion() {
        let definition = AnalyticsEvent.formOpened(form: .vehicle).definition
        #expect(definition.name == "form_opened")
        #expect(definition.parameters.contains(.form(.vehicle)))
        #expect(definition.parameters.contains(.schemaVersion(1)))
        #expect(definition.firebaseParameters["form"] as? String == "vehicle")
    }

    @Test func everyFormKind_rendersAScalarRawValue() {
        for kind in FormKind.allCases {
            let params = AnalyticsEvent.formOpened(form: kind).definition.firebaseParameters
            #expect(params["form"] as? String == kind.rawValue)
        }
    }

    // MARK: - Routing with vehicles present

    @Test func withVehicles_eachSheetReportsItself() {
        let cases: [(AppRouter.Sheet, FormKind)] = [
            (.vehicleForm, .vehicle),
            (.entryPicker, .entryPicker),
            (.entryForm(.fuel), .entry),
            (.voiceQuickAdd, .voiceQuickAdd),
            (.export, .export)
        ]
        for (sheet, expected) in cases {
            let (router, spy) = makeRouter(hasVehicles: true)
            router.present(sheet)
            #expect(spy.events == [.formOpened(form: expected)], "for \(sheet.id)")
        }
    }

    // MARK: - Routing on a zero-vehicle account

    /// The redirect case. Requesting an entry sheet with no vehicles opens vehicle creation, so
    /// the event must say `vehicle` — reporting `entry` would claim the user saw a form they
    /// never saw.
    @Test(arguments: [AppRouter.Sheet.entryPicker, .voiceQuickAdd, .entryForm(.fuel)])
    func withoutVehicles_gatedSheetsReportTheRedirectTarget(sheet: AppRouter.Sheet) {
        let (router, spy) = makeRouter(hasVehicles: false)
        router.present(sheet)
        #expect(router.activeSheet == .vehicleForm)
        #expect(spy.events == [.formOpened(form: .vehicle)])
    }

    @Test func withoutVehicles_ungatedSheetsAreNotRedirected() {
        let (router, spy) = makeRouter(hasVehicles: false)
        router.present(.export)
        #expect(router.activeSheet == .export)
        #expect(spy.events == [.formOpened(form: .export)])
    }

    // MARK: - Paywall exclusion

    /// The paywall reports `paywall_viewed` from its own onAppear. Emitting `form_opened` for it
    /// as well would double-count a single impression and corrupt paywall conversion.
    @Test func paywall_doesNotEmitFormOpened() {
        for hasVehicles in [true, false] {
            let (router, spy) = makeRouter(hasVehicles: hasVehicles)
            router.present(.subscription(.settings))
            #expect(spy.events.isEmpty, "paywall must not double-count (hasVehicles=\(hasVehicles))")
            #expect(router.activeSheet == .subscription(.settings))
        }
    }

    // MARK: - Indirect presentation paths

    @Test func voicePrefilledForm_reportsThroughTheSamePath() {
        let (router, spy) = makeRouter(hasVehicles: true)
        router.presentVoicePrefilledForm(
            VoiceEntryProposal(
                entryType: .fuel,
                odometerReading: nil,
                cost: nil,
                shopName: nil,
                isDiy: nil,
                entryDate: nil,
                notes: nil
            )
        )
        #expect(spy.events == [.formOpened(form: .entry)])
    }

    @Test func openingAFormTwice_emitsTwice_soRepeatIntentIsVisible() {
        let (router, spy) = makeRouter(hasVehicles: true)
        router.present(.vehicleForm)
        router.dismissSheet()
        router.present(.vehicleForm)
        #expect(spy.events.count == 2)
    }
}
