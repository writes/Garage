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
        // `.tires` does not exist — front and rear axles are tracked separately, because an axle
        // is only as good as its most worn tire. And `percentage` is a 0-100 scale: 0.7 here would
        // have meant 0.7% of the tread remaining, not 70%.
        let wear = WearItem(type: .frontTires, percentage: 70, rawValue: "7/32")
        let viewModel = StatsViewModel(contentLoader: { _ in
            StatsViewModel.StatsContent(entries: [], wearItems: [wear])
        })

        await viewModel.load(vehicleId: "vehicle", isPro: true)

        #expect(viewModel.hasContent == true)
        #expect(viewModel.wearItems.count == 1)
    }

    private static func makeEntry() -> FirestoreEntry {
        let sampleOdometerReading = 1
        return FirestoreEntry(
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
