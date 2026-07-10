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
}
