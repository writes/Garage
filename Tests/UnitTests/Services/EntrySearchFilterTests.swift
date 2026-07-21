import Testing
@testable import Garage

struct EntrySearchFilterTests {
    private func entry(
        notes: String? = nil,
        shop: String? = nil,
        details: [String: AnyCodable] = [:],
        type: EntryType = .trackDay
    ) -> FirestoreEntry {
        FirestoreEntry(
            id: "e", vehicleId: "v", userId: "u", entryType: type, entryDate: .now,
            odometerReading: 1, cost: nil, isDiy: nil, shopName: shop, notes: notes,
            attachmentPaths: [], isResolved: nil, details: details, createdAt: nil, updatedAt: nil
        )
    }

    @Test func matchesUserVisibleValuesNotesAndHumanizedKeys() {
        let e = entry(
            notes: "HPDE shakedown",
            details: ["venue": AnyCodable("Willow Springs"), "eventType": AnyCodable("HPDE")]
        )
        #expect(EntryService.filter([e], with: "willow").count == 1)     // detail value
        #expect(EntryService.filter([e], with: "shakedown").count == 1)  // notes
        #expect(EntryService.filter([e], with: "event type").count == 1) // humanized key
    }

    @Test func doesNotMatchInternalRepresentationTokens() {
        let e = entry(details: ["venue": AnyCodable("Willow Springs")])
        // These would all match the old `details.description` (raw dict + CodableValue enum).
        #expect(EntryService.filter([e], with: "AnyCodable").isEmpty)
        #expect(EntryService.filter([e], with: "CodableValue").isEmpty)
        #expect(EntryService.filter([e], with: "string").isEmpty)
        #expect(EntryService.filter([e], with: "venue").count == 1) // humanized "Venue" still matches
    }

    @Test func emptyOrWhitespaceQueryReturnsAllEntries() {
        let entries = [entry(notes: "a"), entry(notes: "b")]
        #expect(EntryService.filter(entries, with: "").count == 2)
        #expect(EntryService.filter(entries, with: "   ").count == 2)
    }

    @Test func matchesShopName() {
        let e = entry(shop: "Willow Springs")
        #expect(EntryService.filter([e], with: "willow").count == 1)
    }
}
