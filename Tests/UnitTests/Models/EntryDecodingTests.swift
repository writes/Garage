import Foundation
import Testing
@testable import Garage

struct EntryDecodingTests {
    @Test func firestoredEntry_roundTripsJSON() throws {
        let original = FirestoreEntry(
            id: "entry",
            vehicleId: "vehicle",
            userId: "user",
            entryType: .oilChange,
            entryDate: .now,
            odometerReading: 12345,
            cost: 120.0,
            isDiy: true,
            shopName: nil,
            notes: "Fresh oil",
            attachmentPaths: ["receipt.pdf"],
            isResolved: nil,
            details: ["oilBrand": AnyCodable("Mobil 1")],
            createdAt: .now,
            updatedAt: .now
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FirestoreEntry.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.entryType == .oilChange)
        #expect(decoded.odometerReading == 12345)
    }
}
