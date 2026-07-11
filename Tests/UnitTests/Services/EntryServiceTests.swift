import Foundation
import Testing
@testable import Garage

@MainActor
struct EntryServiceTests {
    @Test func filter_matchesNotesAndType() {
        let oil = FirestoreEntry(
            id: "oil",
            vehicleId: "vehicle",
            userId: "user",
            entryType: .oilChange,
            entryDate: .now,
            odometerReading: 100,
            cost: 10,
            isDiy: true,
            shopName: nil,
            notes: "Mobil 1 service",
            attachmentPaths: [],
            isResolved: nil,
            details: [:],
            createdAt: nil,
            updatedAt: nil
        )
        let fuel = FirestoreEntry(
            id: "fuel",
            vehicleId: "vehicle",
            userId: "user",
            entryType: .fuel,
            entryDate: .now,
            odometerReading: 200,
            cost: 30,
            isDiy: nil,
            shopName: nil,
            notes: "Station visit",
            attachmentPaths: [],
            isResolved: nil,
            details: [:],
            createdAt: nil,
            updatedAt: nil
        )

        let filtered = EntryService.filter([oil, fuel], with: "mobil")

        #expect(filtered.map(\.id) == ["oil"])
    }

    @Test func fetchEntries_subsetsTypesForVehicle() async throws {
        let service = EntryService(testEntries: [
            entry(id: "fuel", type: .fuel, odometer: 30_000, date: 300),
            entry(id: "oil", type: .oilChange, odometer: 29_000, date: 200),
            entry(id: "repair", type: .repair, odometer: 28_000, date: 100),
            entry(id: "other", type: .fuel, odometer: 1, date: 400, vehicleId: "other")
        ])
        let query = EntryQuery(
            vehicleId: "vehicle",
            entryTypes: [.fuel, .oilChange],
            searchText: ""
        )

        let entries = try await service.fetchEntries(query: query)

        #expect(entries.map(\.id) == ["fuel", "oil"])
    }

    @Test func latestOdometerAndFuelEntry_useTheirDedicatedOrdering() async throws {
        let service = EntryService(testEntries: [
            entry(id: "older-fuel", type: .fuel, odometer: 31_000, date: 100),
            entry(id: "latest-fuel", type: .fuel, odometer: 30_000, date: 300),
            entry(id: "highest-odometer", type: .repair, odometer: 32_000, date: 200)
        ])

        let odometer = try await service.fetchLatestOdometer(vehicleId: "vehicle")
        let lastFuel = try await service.lastFuelEntry(vehicleId: "vehicle")

        #expect(odometer == 32_000)
        #expect(lastFuel?.id == "latest-fuel")
    }

    @Test func fetchEntries_pagesStablyAcrossEqualTimestampBoundaries() async throws {
        let entries = (0..<1_203).map { index in
            entry(
                id: String(format: "entry-%04d", index),
                type: .maintenance,
                odometer: index,
                date: paginationDate(for: index)
            )
        }
        let service = EntryService(testEntries: Array(entries.reversed()))
        var cursor: EntryCursor?
        var pageCounts: [Int] = []
        var collectedIDs: [String] = []

        repeat {
            let page = try await service.fetchEntries(
                query: EntryQuery(vehicleId: "vehicle"),
                limit: 500,
                after: cursor
            )
            pageCounts.append(page.entries.count)
            collectedIDs.append(contentsOf: page.entries.map(\.id))
            cursor = page.nextCursor
        } while cursor != nil

        let expectedIDs = entries
            .sorted {
                if $0.entryDate != $1.entryDate {
                    return $0.entryDate > $1.entryDate
                }
                return $0.id > $1.id
            }
            .map(\.id)

        #expect(pageCounts == [500, 500, 203])
        #expect(collectedIDs.count == 1_203)
        #expect(Set(collectedIDs).count == 1_203)
        #expect(collectedIDs == expectedIDs)
    }

    private func entry(
        id: String,
        type: EntryType,
        odometer: Int,
        date: TimeInterval,
        vehicleId: String = "vehicle"
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: id,
            vehicleId: vehicleId,
            userId: "user",
            entryType: type,
            entryDate: Date(timeIntervalSince1970: date),
            odometerReading: odometer,
            cost: nil,
            isDiy: nil,
            shopName: nil,
            notes: nil,
            attachmentPaths: [],
            isResolved: nil,
            details: [:],
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func paginationDate(for index: Int) -> TimeInterval {
        if (495...505).contains(index) {
            return 1_999_505
        }
        if (995...1_005).contains(index) {
            return 1_999_005
        }
        return 2_000_000 - Double(index)
    }
}
