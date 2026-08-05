import Foundation
import Testing
@testable import Garage

@MainActor
struct EntryServiceQueryTests {
    @Test func filter_matchesNotesAndType() {
        let oil = makeEntry(id: "oil", type: .oilChange, notes: "Mobil 1 service")
        let fuel = makeEntry(id: "fuel", type: .fuel, notes: "Station visit")
        #expect(EntryService.filter([oil, fuel], with: "mobil").map(\.id) == ["oil"])
    }
    @Test func fetchEntries_subsetsTypesForVehicle() async throws {
        let service = EntryService(testEntries: [
            makeEntry(id: "fuel", type: .fuel, odometer: 30_000, date: 300),
            makeEntry(id: "oil", type: .oilChange, odometer: 29_000, date: 200),
            makeEntry(id: "repair", type: .repair, odometer: 28_000, date: 100),
            makeEntry(id: "other", type: .fuel, odometer: 1, date: 400, vehicleId: "other")
        ])
        let entries = try await service.fetchEntries(
            query: EntryQuery(vehicleId: "vehicle", entryTypes: [.fuel, .oilChange], searchText: "")
        )
        #expect(entries.map(\.id) == ["fuel", "oil"])
    }
    @Test func latestOdometerAndFuelEntry_useTheirDedicatedOrdering() async throws {
        let service = EntryService(testEntries: [
            makeEntry(id: "older-fuel", type: .fuel, odometer: 31_000, date: 100),
            makeEntry(id: "latest-fuel", type: .fuel, odometer: 30_000, date: 300),
            makeEntry(id: "highest-odometer", type: .repair, odometer: 32_000, date: 200)
        ])
        let odometer = try await service.fetchLatestOdometer(vehicleId: "vehicle")
        let fuel = try await service.lastFuelEntry(vehicleId: "vehicle", before: Date(timeIntervalSince1970: 1_000))
        #expect(odometer == 32_000)
        #expect(fuel?.id == "latest-fuel")
    }
    // Edit-in-place (review finding): editing the entry that holds the vehicle's current max
    // odometer, or the most recent fuel fill-up, must not have that entry find ITSELF as the
    // "other entry" to floor/compare against.
    @Test func fetchLatestOdometer_excludingEntryID_skipsTheExcludedEvenWhenItIsTheMax() async throws {
        let service = EntryService(testEntries: [
            makeEntry(id: "high", odometer: 30_000, date: 300),
            makeEntry(id: "mid", odometer: 20_000, date: 200)
        ])
        let excludingHigh = try await service.fetchLatestOdometer(vehicleId: "vehicle", excludingEntryID: "high")
        let includingAll = try await service.fetchLatestOdometer(vehicleId: "vehicle")
        #expect(excludingHigh == 20_000)
        #expect(includingAll == 30_000)
    }
    @Test func lastFuelEntry_excludingEntryID_skipsTheEditedEntryItself() async throws {
        let service = EntryService(testEntries: [
            makeEntry(id: "fuel-a", type: .fuel, odometer: 10_000, date: 100),
            makeEntry(id: "fuel-b", type: .fuel, odometer: 10_300, date: 200)
        ])
        let farFuture = Date(timeIntervalSince1970: 1_000)
        let excludingSelf = try await service.lastFuelEntry(
            vehicleId: "vehicle", before: farFuture, excludingEntryID: "fuel-b"
        )
        let includingAll = try await service.lastFuelEntry(vehicleId: "vehicle", before: farFuture)
        #expect(excludingSelf?.id == "fuel-a")
        #expect(includingAll?.id == "fuel-b")
    }
    // Review MAJOR: editing a non-latest fuel entry must find the entry chronologically BEFORE
    // it, never one that's actually later — an unbounded "newest OTHER entry" lookup would have
    // picked "late" here, corrupting MPG against a fill-up that hasn't happened yet.
    @Test func lastFuelEntry_editingAMiddleEntryFindsThePriorFillUpNotAFutureOne() async throws {
        let service = EntryService(testEntries: [
            makeEntry(id: "early", type: .fuel, odometer: 9_000, date: 100),
            makeEntry(id: "middle", type: .fuel, odometer: 9_300, date: 200),
            makeEntry(id: "late", type: .fuel, odometer: 9_600, date: 300)
        ])
        let previous = try await service.lastFuelEntry(
            vehicleId: "vehicle", before: Date(timeIntervalSince1970: 200), excludingEntryID: "middle"
        )
        #expect(previous?.id == "early")
    }
    @Test func fetchEntries_pagesStablyAcrossEqualTimestampBoundaries() async throws {
        let entries = (0..<1_203).map {
            makeEntry(
                id: String(format: "entry-%04d", $0),
                type: .maintenance, odometer: $0, date: paginationDate(for: $0)
            )
        }
        let service = EntryService(testEntries: Array(entries.reversed()))
        var cursor: EntryCursor?
        var counts: [Int] = []
        var ids: [String] = []
        repeat {
            let page = try await service.fetchEntries(
                query: EntryQuery(vehicleId: "vehicle"),
                limit: 500,
                after: cursor
            )
            counts.append(page.entries.count)
            ids += page.entries.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil
        let expected = entries.sorted {
            $0.entryDate != $1.entryDate ? $0.entryDate > $1.entryDate : $0.id > $1.id
        }.map(\.id)
        // A dataset that isn't an exact multiple of the page size (1_203, not 1_000 or 1_500)
        // exercises the same "final short page" path whether or not the limit+1 sentinel (#4)
        // overfetches — the sentinel only changes behavior exactly AT a page-size boundary.
        #expect(counts == [500, 500, 203])
        #expect(ids.count == 1_203 && Set(ids).count == 1_203)
        #expect(ids == expected)
    }
    /// The odometer-bounds window saturation defect. The live query's page limit is applied by
    /// Firestore BEFORE the client-side "reading actually recorded" filter, so a contiguous block of
    /// zero-reading entries longer than one page returned nothing usable — the real floor sitting
    /// just past the zeros went unseen and a contradictory reading was admitted. A range filter on
    /// odometerReading cannot fix it server-side (two range fields, plus a composite index that is
    /// not deployed), so the loop pages past an all-unrecorded page instead. This is that rule.
    @Test func odometerBoundsPaging_continuesOnlyThroughAFullPageWithNothingRecorded() {
        let window = EntryService.odometerBoundsWindow
        let unrecorded: [FirestoreEntry] = []
        let recorded = [makeEntry(id: "recorded", odometer: 50_000, date: 100)]

        // The regression: a full page that yielded no reading at all must cost another round trip.
        #expect(EntryService.needsAnotherOdometerPage(recorded: unrecorded, pageCount: window))
        // A short page means that side's history is exhausted — nothing further to skip past.
        #expect(!EntryService.needsAnotherOdometerPage(recorded: unrecorded, pageCount: window - 1))
        #expect(!EntryService.needsAnotherOdometerPage(recorded: unrecorded, pageCount: 0))
        // Any recorded reading is the bound; the common case stays at exactly one read.
        #expect(!EntryService.needsAnotherOdometerPage(recorded: recorded, pageCount: window))
        #expect(!EntryService.needsAnotherOdometerPage(recorded: recorded, pageCount: 1))
    }
    @Test func fetchEntries_exactMultipleOfPageSizeReportsNoMoreHistory() async throws {
        // The #4 regression case: a vehicle's history is precisely one page. Without the
        // limit+1 sentinel this dangled a nextCursor pointing at an empty next page.
        let entries = (0..<500).map {
            makeEntry(id: String(format: "entry-%04d", $0), type: .maintenance, odometer: $0, date: Double($0))
        }
        let service = EntryService(testEntries: entries)
        let page = try await service.fetchEntries(query: EntryQuery(vehicleId: "vehicle"), limit: 500, after: nil)
        #expect(page.entries.count == 500)
        #expect(page.nextCursor == nil)
    }
}

private extension EntryServiceQueryTests {
    func makeEntry(
        id: String = "entry",
        type: EntryType = .fuel, odometer: Int = 12_100, date: TimeInterval = 100,
        vehicleId: String = "vehicle", notes: String? = nil
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: id, vehicleId: vehicleId, userId: "user", entryType: type,
            entryDate: Date(timeIntervalSince1970: date), odometerReading: odometer, cost: nil,
            isDiy: nil, shopName: nil, notes: notes, attachmentPaths: [], isResolved: nil,
            details: [:], createdAt: nil, updatedAt: nil
        )
    }
    func paginationDate(for index: Int) -> TimeInterval {
        if (495...505).contains(index) { return 1_999_505 }
        if (995...1_005).contains(index) { return 1_999_005 }
        return 2_000_000 - Double(index)
    }
}
