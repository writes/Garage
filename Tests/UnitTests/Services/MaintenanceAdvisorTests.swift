import Foundation
import Testing
@testable import Garage

/// The first thing in the app that tells an owner something they did not already know. That makes
/// being wrong expensive in both directions: a false "overdue" trains people to ignore the screen,
/// and a missed one is the reason they installed a service tracker.
struct MaintenanceAdvisorTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func entry(_ type: EntryType, odometer: Int, daysAgo: Double) -> FirestoreEntry {
        FirestoreEntry(
            id: UUID().uuidString, vehicleId: "v", userId: "u", entryType: type,
            entryDate: now.addingTimeInterval(-daysAgo * day),
            odometerReading: odometer, cost: nil, isDiy: nil, shopName: nil, notes: nil,
            attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }

    private func status(
        _ item: MaintenanceItem, _ entries: [FirestoreEntry], odometer: Int?
    ) -> MaintenanceDue {
        MaintenanceAdvisor.status(for: item, entries: entries, currentOdometer: odometer, now: now)
    }

    /// "Never logged" is NOT "overdue". A car serviced last week by a previous owner is not late,
    /// and the app has no way to know it was — claiming otherwise is a confident lie on day one.
    @Test func anItemWithNoHistoryIsNeverLoggedRatherThanOverdue() {
        let due = status(.oilAndFilter, [], odometer: 50_000)
        #expect(due.status == .neverLogged)
        #expect(due.milesPastDue == nil)
        #expect(due.lastServicedAt == nil)
    }

    @Test func anItemInsideBothIntervalsIsFine() {
        let entries = [entry(.oilChange, odometer: 49_000, daysAgo: 30)]
        #expect(status(.oilAndFilter, entries, odometer: 50_000).status == .upToDate)
    }

    @Test func exceedingTheMileageIntervalIsOverdue() {
        let entries = [entry(.oilChange, odometer: 40_000, daysAgo: 30)]
        let due = status(.oilAndFilter, entries, odometer: 50_000)
        #expect(due.status == .overdue)
        #expect(due.milesPastDue == 5_000)
    }

    /// "5,000 miles or 6 months" means either alone is enough. Requiring both would let a car that
    /// sits in a garage all year go indefinitely without an oil change.
    @Test func exceedingTheTimeIntervalIsOverdueEvenWithFewMiles() {
        let entries = [entry(.oilChange, odometer: 49_900, daysAgo: 400)]
        #expect(status(.oilAndFilter, entries, odometer: 50_000).status == .overdue)
    }

    @Test func approachingTheMileageIntervalIsDueSoon() {
        // 4,800 of a 5,000-mile interval — inside the last tenth.
        let entries = [entry(.oilChange, odometer: 45_200, daysAgo: 10)]
        let due = status(.oilAndFilter, entries, odometer: 50_000)
        #expect(due.status == .dueSoon)
        #expect(due.milesPastDue == -200)
    }

    /// A zero odometer means "not recorded", not "mile zero". Measuring from it would report every
    /// vehicle as tens of thousands of miles overdue the moment one entry lacked a reading.
    @Test func aMissingOdometerYieldsNoMileageVerdictRatherThanAHugeOne() {
        let entries = [entry(.oilChange, odometer: 0, daysAgo: 10)]
        let due = status(.oilAndFilter, entries, odometer: 50_000)
        #expect(due.milesPastDue == nil)
        #expect(due.status == .upToDate)
    }

    @Test func aMissingCurrentOdometerFallsBackToTheTimeIntervalAlone() {
        let recent = [entry(.oilChange, odometer: 45_000, daysAgo: 10)]
        #expect(status(.oilAndFilter, recent, odometer: nil).status == .upToDate)

        let old = [entry(.oilChange, odometer: 45_000, daysAgo: 400)]
        #expect(status(.oilAndFilter, old, odometer: nil).status == .overdue)
    }

    @Test func theMostRecentServiceIsTheBaselineNotTheFirst() {
        let entries = [
            entry(.oilChange, odometer: 30_000, daysAgo: 500),
            entry(.oilChange, odometer: 49_000, daysAgo: 20)
        ]
        #expect(status(.oilAndFilter, entries, odometer: 50_000).status == .upToDate)
    }

    /// Each item is cleared only by its own entry type — a tire rotation must not reset the oil.
    @Test func anUnrelatedEntryTypeDoesNotClearAnItem() {
        let entries = [entry(.tire, odometer: 49_900, daysAgo: 1)]
        #expect(status(.oilAndFilter, entries, odometer: 50_000).status == .neverLogged)
        #expect(status(.tireRotation, entries, odometer: 50_000).status == .upToDate)
    }

    // MARK: - The list

    @Test func healthyItemsAreLeftOffTheList() {
        let entries = MaintenanceItem.allCases.map { entry($0.clearedBy, odometer: 49_900, daysAgo: 1) }
        #expect(MaintenanceAdvisor.attentionNeeded(entries: entries, currentOdometer: 50_000, now: now).isEmpty)
    }

    @Test func overdueSortsAheadOfDueSoonWhichSortsAheadOfNeverLogged() {
        let entries = [
            entry(.oilChange, odometer: 40_000, daysAgo: 10),   // overdue on miles
            entry(.tire, odometer: 44_500, daysAgo: 10)         // 5,500 of 6,000 — due soon
            // brake and alignment absent -> neverLogged
        ]
        let list = MaintenanceAdvisor.attentionNeeded(entries: entries, currentOdometer: 50_000, now: now)
        #expect(list.map(\.status) == [.overdue, .dueSoon, .neverLogged, .neverLogged])
        #expect(list.first?.item == .oilAndFilter)
    }

    /// Swift's sort is not stable, so without an explicit tiebreak two equally-overdue items could
    /// swap places between renders.
    @Test func theListOrderIsDeterministic() {
        let entries = [
            entry(.oilChange, odometer: 40_000, daysAgo: 10),
            entry(.tire, odometer: 40_000, daysAgo: 10)
        ]
        let first = MaintenanceAdvisor
            .attentionNeeded(entries: entries, currentOdometer: 50_000, now: now)
            .map(\.item)
        for _ in 0..<20 {
            let repeated = MaintenanceAdvisor
                .attentionNeeded(entries: entries, currentOdometer: 50_000, now: now)
                .map(\.item)
            #expect(repeated == first)
        }
    }

    @Test func everyItemIsClearedByADistinctEntryType() {
        let types = MaintenanceItem.allCases.map(\.clearedBy)
        #expect(Set(types).count == types.count)
    }
}
