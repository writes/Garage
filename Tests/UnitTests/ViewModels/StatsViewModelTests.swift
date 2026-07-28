import Foundation
import Testing
@testable import Garage

@MainActor
struct StatsViewModelTests {
    @Test func load_withNoEntriesAndNoWear_setsHasContentFalse() async {
        let viewModel = StatsViewModel(contentLoader: { _ in
            StatsViewModel.StatsContent(entries: [], wearItems: [])
        })

        await viewModel.load(vehicleId: "vehicle", isPro: true)

        #expect(viewModel.hasContent == false)
        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.wearItems.isEmpty)
    }

    @Test func load_withEntries_setsHasContentTrue() async {
        let viewModel = StatsViewModel(contentLoader: { _ in
            StatsViewModel.StatsContent(entries: [Self.makeEntry()], wearItems: [])
        })

        await viewModel.load(vehicleId: "vehicle", isPro: true)

        #expect(viewModel.hasContent == true)
        #expect(viewModel.entries.count == 1)
    }

    @Test func load_withWearItems_setsHasContentTrue() async {
        let wear = WearItem(type: .tires, percentage: 0.7, rawValue: "7/32")
        let viewModel = StatsViewModel(contentLoader: { _ in
            StatsViewModel.StatsContent(entries: [], wearItems: [wear])
        })

        await viewModel.load(vehicleId: "vehicle", isPro: true)

        #expect(viewModel.hasContent == true)
        #expect(viewModel.wearItems.count == 1)
    }

    private static func makeEntry() -> FirestoreEntry {
        let sampleOdometerReading = 1
        FirestoreEntry(
            id: "entry-1",
            vehicleId: "vehicle",
            userId: "user",
            entryType: .maintenance,
            entryDate: .now,
            odometerReading: sampleOdometerReading,
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
