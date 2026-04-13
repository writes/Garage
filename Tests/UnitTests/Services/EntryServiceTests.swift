import Foundation
import Testing
@testable import Garage

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
}
