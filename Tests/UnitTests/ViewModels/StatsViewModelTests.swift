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

    /// The regression guard for the empty state itself. `hasContent` is false for BOTH "this owner
    /// has no data" and "the fetch has not come back yet", so the view can only tell them apart via
    /// `isLoading`. Without it, every owner WITH data is told "No stats data yet" until the fetch
    /// resolves — the exact flash the empty state was meant to remove.
    /// .timeLimit because the assertions sit between two continuations: a regression that never
    /// starts the fetch should fail in a minute, not hold a CI runner (see the picker-test 2h14m).
    @Test(.timeLimit(.minutes(1))) func load_whileFetchIsInFlight_reportsLoadingNotEmpty() async {
        let loader = GatedContentLoader(content: .init(entries: [Self.makeEntry()], wearItems: []))
        let viewModel = StatsViewModel(contentLoader: { try await loader.load(vehicleId: $0) })

        let load = Task { await viewModel.load(vehicleId: "vehicle", isPro: true) }
        await loader.waitForLoadStart()

        #expect(viewModel.isLoading == true)
        #expect(viewModel.hasContent == false)

        loader.finishCurrentLoad()
        await load.value

        #expect(viewModel.isLoading == false)
        #expect(viewModel.hasContent == true)
    }

    @Test func load_whenTheFetchFails_clearsLoadingAndSurfacesTheError() async {
        struct Boom: Error {}
        let viewModel = StatsViewModel(contentLoader: { _ in throw Boom() })

        await viewModel.load(vehicleId: "vehicle", isPro: true)

        #expect(viewModel.isLoading == false)
        #expect(viewModel.error != nil)
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

/// Continuation-gated loader so a test can observe `load()` mid-flight — the same pattern
/// `LogViewModelTests.GatedPageFetcher` uses. Queues rather than single fields so that a regression
/// starting a second load while the first is pending fails fast instead of stranding a continuation.
@MainActor
private final class GatedContentLoader {
    private let content: StatsViewModel.StatsContent
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(content: StatsViewModel.StatsContent) {
        self.content = content
    }

    func load(vehicleId: String) async throws -> StatsViewModel.StatsContent {
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { pendingContinuations.append($0) }
        return content
    }

    /// Suspends until a load() call is in flight and not yet released.
    func waitForLoadStart() async {
        guard pendingContinuations.isEmpty else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    /// Releases the oldest still-suspended load() call (FIFO).
    func finishCurrentLoad() {
        guard !pendingContinuations.isEmpty else { return }
        pendingContinuations.removeFirst().resume()
    }
}
