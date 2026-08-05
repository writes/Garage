import Foundation
import Testing
@testable import Garage

/// What an odometer reading is allowed to be depends on the DATE it is logged for — not on the
/// highest number the vehicle has ever shown.
///
/// The old floor was that highest-ever number, with no date predicate anywhere in its lookup. That
/// made the single most valuable thing a service tracker can do — entering the history you already
/// have — impossible: a two-year-old receipt is legitimately below today's reading, and the form
/// hard-rejected it. Worse, the floor was derived once when the form opened and never again, so
/// moving the date picker changed nothing.
@MainActor
struct OdometerTimelineBoundsTests {
    private let vehicleId = "vehicle"
    /// 2024-01-01T00:00:00Z, with the rest expressed as offsets so the ordering is obvious.
    private let january = Date(timeIntervalSince1970: 1_704_067_200)
    private var june: Date { january.addingTimeInterval(150 * 86_400) }
    private var december: Date { january.addingTimeInterval(330 * 86_400) }

    // MARK: - Creating an entry

    /// The reported defect: backfilling old history. Every existing entry is dated AFTER the one
    /// being written, so nothing contradicts a much lower reading — and the vehicle's max-ever
    /// number (still loaded, still shown as the hint) is not a floor.
    @Test func aBackdatedReadingFarBelowTheVehiclesHighestIsAccepted() async {
        let form = form([entry("a", on: june, odometer: 60_000), entry("b", on: december, odometer: 80_000)])
        form.entryDate = january
        await form.prepare(vehicleId: vehicleId)
        form.odometerReading = "40000"

        #expect(form.lastKnownOdometer == 80_000) // the hint is still the max-ever reading
        #expect(form.odometerBounds.earlier == nil)
        #expect(form.odometerBounds.later?.reading == 60_000)
        #expect(form.validateOdometer())
    }

    /// The check that survives: a reading below an EARLIER-dated entry is a real contradiction, and
    /// the message names the record it collides with rather than restating a limit.
    @Test func aReadingBelowAnEarlierDatedEntryIsRejectedAndNamesThatEntry() async {
        let form = form([entry("a", on: january, odometer: 50_000)])
        form.entryDate = june
        await form.prepare(vehicleId: vehicleId)
        form.odometerReading = "45000"

        #expect(!form.validateOdometer())
        #expect(form.error == .validation(
            "Odometer conflicts with the 50,000 mi entry on \(Formatters.shortDate.string(from: january))."
        ))
    }

    /// The bound the old max-only floor could not express at all: a backdated entry must not claim
    /// more miles than a LATER one recorded.
    @Test func aReadingAboveALaterDatedEntryIsRejected() async {
        let form = form([entry("a", on: december, odometer: 80_000)])
        form.entryDate = june
        await form.prepare(vehicleId: vehicleId)
        form.odometerReading = "90000"

        #expect(!form.validateOdometer())
        #expect(form.error == .validation(
            "Odometer conflicts with the 80,000 mi entry on \(Formatters.shortDate.string(from: december))."
        ))
    }

    @Test func aReadingBetweenTheTwoNeighbouringEntriesIsAccepted() async {
        let form = form([
            entry("a", on: january, odometer: 50_000), entry("b", on: december, odometer: 80_000)
        ])
        form.entryDate = june
        await form.prepare(vehicleId: vehicleId)
        form.odometerReading = "62000"

        #expect(form.validateOdometer())
    }

    /// A zero reading means "not recorded", never "mile zero". Left in, one legacy zero dated after
    /// the chosen date would pin the ceiling at 0 and reject every reading the owner could type.
    @Test func anEntryWithNoRecordedOdometerBoundsNothing() async {
        let form = form([entry("a", on: december, odometer: 0)])
        form.entryDate = june
        await form.prepare(vehicleId: vehicleId)
        form.odometerReading = "62000"

        #expect(form.odometerBounds.later == nil)
        #expect(form.validateOdometer())
    }

    /// Window saturation (cross-check finding). The live query's page limit applies BEFORE the
    /// client-side zero filter, so a contiguous block of unrecorded readings longer than one page
    /// used to consume the whole window and hide the real floor sitting just beyond it. 26 zeros
    /// against a 25-entry page: the live path pages its cursor past them
    /// (`odometerBoundsMaxPages`), the hermetic path reduces over the whole history, and both must
    /// still see the 50,000-mile baseline.
    @Test func aBlockOfUnrecordedReadingsLongerThanOnePageDoesNotBlindTheFloor() async {
        #expect(EntryService.odometerBoundsMaxPages > 1) // one page alone cannot clear the block
        var history = [entry("baseline", on: january, odometer: 50_000)]
        for index in 0...EntryService.odometerBoundsWindow {
            history.append(entry(
                "zero-\(index)", on: january.addingTimeInterval(Double(index + 1) * 86_400), odometer: 0
            ))
        }
        let form = form(history)
        form.entryDate = june
        await form.prepare(vehicleId: vehicleId)
        form.odometerReading = "40000"

        #expect(history.count == EntryService.odometerBoundsWindow + 2)
        #expect(form.odometerBounds.earlier?.reading == 50_000)
        #expect(!form.validateOdometer())
    }

    // MARK: - Out-of-order responses

    /// Cross-check finding. Two lookups can be in flight after a quick date change, and whichever
    /// finishes LAST must not win. This drives the failing branch specifically: as two separate
    /// guards the catch path had none, so a slow failure for an abandoned date wiped the bounds the
    /// current date's lookup had already installed — silently disabling validation.
    @Test func aLateFailureForAnAbandonedDateNeverWipesTheCurrentBounds() async {
        let vehicle = "stale-guard-vehicle"
        let form = form([entry("a", on: january, odometer: 50_000, vehicle: vehicle)])
        form.entryDate = june
        await form.refreshOdometerBounds(vehicleId: vehicle)
        #expect(form.odometerBounds.earlier?.reading == 50_000)

        // The picker moves while this lookup is in flight, and the lookup then fails: by the time
        // it reports, its answer is for a date the form has already left.
        EntryService.testBoundsInFlightHook = { requested in
            guard requested == vehicle else { return }
            form.entryDate = self.december
            throw AppError.database("bounds unavailable")
        }
        defer { EntryService.testBoundsInFlightHook = nil }
        await form.refreshOdometerBounds(vehicleId: vehicle)

        #expect(form.odometerBounds.earlier?.reading == 50_000)
    }

    // MARK: - The structural half: the range follows the date picker

    /// `prepare()` runs once, when the form opens. Without a re-derivation on every date change the
    /// user backdates the entry, sees the date they wanted, and is still validated against the
    /// range for the date the form happened to open with.
    @Test func changingTheDateReDerivesTheRange() async {
        let form = form([entry("a", on: january, odometer: 50_000)])
        form.entryDate = june
        await form.prepare(vehicleId: vehicleId)
        form.odometerReading = "45000"
        #expect(!form.validateOdometer())

        form.entryDate = january.addingTimeInterval(-86_400)
        // Stale until re-derived — this is exactly the state the shipped form was stuck in.
        #expect(form.odometerBounds.earlier?.reading == 50_000)

        await form.refreshOdometerBounds(vehicleId: vehicleId)

        #expect(form.odometerBounds.earlier == nil)
        #expect(form.odometerBounds.later?.reading == 50_000)
        #expect(form.validateOdometer())
    }

    // MARK: - Editing an existing entry

    /// Edit-mode semantics, unchanged in substance: an entry never bounds itself, so re-saving it
    /// untouched always validates.
    @Test func theEntryBeingEditedIsExcludedFromItsOwnBounds() async {
        let edited = entry("edited", on: june, odometer: 60_000)
        let form = form([edited, entry("a", on: january, odometer: 50_000)])
        form.applyExistingEntry(edited)
        await form.prepare(vehicleId: vehicleId)

        #expect(form.odometerBounds.earlier?.reading == 50_000)
        #expect(form.validateOdometer())
    }

    /// The residual case the old `min(lastKnownOdometer, editingEntryOriginalOdometer)` floor
    /// existed for: history that ALREADY contradicts itself. Enforcing a boundary the saved value
    /// breaks would make the entry impossible to re-save — including to fix the very typo that
    /// caused it — so that boundary is dropped for the edit.
    @Test func aBoundaryTheSavedReadingAlreadyViolatesNeverBlocksTheEdit() async {
        let edited = entry("edited", on: june, odometer: 15_000)
        let form = form([edited, entry("a", on: january, odometer: 20_000)])
        form.applyExistingEntry(edited)
        await form.prepare(vehicleId: vehicleId)

        #expect(form.odometerBounds.earlier?.reading == 20_000) // the raw range still sees it
        #expect(form.validationBounds.earlier == nil)           // the enforced one does not
        #expect(form.validateOdometer())

        form.odometerReading = "12000"
        #expect(form.validateOdometer())
    }

    /// Cross-check finding: the relaxation grandfathers the entry against the timeline it was
    /// ALREADY part of, not against every timeline it could be moved to. Walking that same
    /// 15,000-mile entry forward to December carries it past a 20,000-mile reading it never had to
    /// answer to on its own date, so re-timing withdraws the drop and the full bounds apply.
    @Test func movingAnEditedEntryOntoATimelineItContradictsIsRejected() async {
        let edited = entry("edited", on: june, odometer: 15_000)
        let form = form([edited, entry("a", on: january, odometer: 20_000)])
        form.applyExistingEntry(edited)
        await form.prepare(vehicleId: vehicleId)
        #expect(form.validateOdometer()) // still re-savable on its own date

        form.entryDate = december
        await form.refreshOdometerBounds(vehicleId: vehicleId)

        #expect(form.validationBounds.earlier?.reading == 20_000)
        #expect(!form.validateOdometer())
    }

    /// The relaxation is per-boundary, not a blanket exemption: an edit that introduces a NEW
    /// contradiction is still rejected.
    @Test func anEditThatIntroducesANewContradictionIsStillRejected() async {
        let edited = entry("edited", on: june, odometer: 60_000)
        let form = form([edited, entry("a", on: january, odometer: 50_000)])
        form.applyExistingEntry(edited)
        await form.prepare(vehicleId: vehicleId)

        form.odometerReading = "45000"
        #expect(!form.validateOdometer())
    }

    // MARK: - Fixtures

    /// `vehicle` overrides the suite's id for the one test that arms the process-global in-flight
    /// hook, so a suite running in parallel on another vehicle cannot be caught by it.
    private func entry(
        _ id: String, on date: Date, odometer: Int, vehicle: String? = nil
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: id, vehicleId: vehicle ?? vehicleId, userId: "user", entryType: .maintenance,
            entryDate: date, odometerReading: odometer, cost: nil, isDiy: nil, shopName: nil,
            notes: nil, attachmentPaths: [], isResolved: nil, details: [:],
            createdAt: nil, updatedAt: nil
        )
    }

    private func form(_ entries: [FirestoreEntry]) -> EntryFormViewModel {
        EntryFormViewModel(
            entryService: EntryService(testEntries: entries),
            vehicleService: VehicleService(
                testVehicles: [], purchaseService: PurchaseService(testIsPro: false)
            ),
            syncService: SyncService(monitorFactory: { SyncPassiveMonitor() }),
            analytics: NoopAnalyticsService(), userID: { "user" }
        )
    }
}
