import Foundation
import Testing
@testable import Garage

@MainActor
struct LogViewModelTests {
    /// One page, not the 500-entry cap: this reload re-runs on every revision bump.
    @Test func reload_fetchesExactlyOnePageOfTheNewestHistory() async {
        let service = EntryService(testEntries: makeEntries(count: 550))
        let viewModel = LogViewModel(entryService: service)

        await viewModel.reload(vehicleId: "vehicle")

        #expect(viewModel.allEntries.count == Constants.logPageSize)
        #expect(viewModel.entries.count == Constants.logPageSize)
        #expect(viewModel.hasMoreEntries)
    }

    @Test func loadMore_appendsTheNextPageAndReappliesTheActiveFilter() async {
        let service = EntryService(testEntries: makeEntries(count: 60))
        let viewModel = LogViewModel(entryService: service)
        await viewModel.reload(vehicleId: "vehicle")
        viewModel.selectedTypes = [.maintenance]
        viewModel.applyFilter()
        let filteredCountBeforeLoadMore = viewModel.entries.count

        await viewModel.loadMore()

        #expect(viewModel.allEntries.count == 60)
        #expect(viewModel.hasMoreEntries == false)
        #expect(viewModel.entries.count > filteredCountBeforeLoadMore)
        #expect(viewModel.entries.allSatisfy { $0.entryType == .maintenance })
    }

    /// Pins BOTH halves of the paging contract: each request asks for exactly one page, and the
    /// next request resumes from the cursor the previous page returned — which the fetch anchors on
    /// the last DOCUMENT it consumed. Deriving a cursor from the loaded entries instead would loop
    /// forever on an undecodable document (the tolerant-decode invariant this cursor exists for).
    @Test func paging_requestsOnePageAtATimeAndResumesFromTheReturnedCursor() async {
        let fetcher = RecordingPageFetcher(entries: makeEntries(count: 120))
        let viewModel = LogViewModel(pageFetch: fetcher.fetch)

        await viewModel.reload(vehicleId: "vehicle")
        let firstPageLastID = viewModel.allEntries.last?.id
        await viewModel.loadMore()

        #expect(fetcher.limits == [Constants.logPageSize, Constants.logPageSize])
        #expect(fetcher.cursorIDs == [nil, firstPageLastID])
        #expect(viewModel.allEntries.count == Constants.logPageSize * 2)
        // No overlap and no gap: page two starts exactly after page one's last document.
        #expect(Set(viewModel.allEntries.map(\.id)).count == viewModel.allEntries.count)
        #expect(viewModel.hasMoreEntries)
    }

    @Test func loadMore_withNoAdditionalHistoryIsANoOp() async {
        let service = EntryService(testEntries: makeEntries(count: 10))
        let viewModel = LogViewModel(entryService: service)
        await viewModel.reload(vehicleId: "vehicle")

        await viewModel.loadMore()

        #expect(viewModel.allEntries.count == 10)
        #expect(viewModel.hasMoreEntries == false)
    }

    @Test func loadMore_concurrentTapsFetchExactlyOncePerInFlightPage() async {
        let fetcher = GatedPageFetcher(pages: [
            EntryPageStub(entries: makeEntries(count: 500), hasNext: true),
            EntryPageStub(entries: makeEntries(count: 50, startingAt: 500), hasNext: false)
        ])
        let viewModel = LogViewModel(pageFetch: fetcher.fetch)

        // Drive the initial reload() through the same gate so the concurrency dance below starts
        // from a known, settled state (loadedVehicleId set, nextCursor pointing at page 2).
        let initialLoad = Task { await viewModel.reload(vehicleId: "vehicle") }
        await fetcher.waitForFetchStart()
        fetcher.finishCurrentFetch()
        await initialLoad.value
        #expect(viewModel.allEntries.count == 500)

        let firstTap = Task { await viewModel.loadMore() }
        await fetcher.waitForFetchStart()
        let secondTap = Task { await viewModel.loadMore() }
        await secondTap.value
        fetcher.finishCurrentFetch()
        await firstTap.value

        #expect(viewModel.allEntries.count == 550)
        #expect(fetcher.fetchCount == 2)
    }

    @Test func loadMore_duringAnInFlightReloadIsANoOp() async {
        let fetcher = GatedPageFetcher(pages: [
            EntryPageStub(entries: makeEntries(count: 10), hasNext: true),
            EntryPageStub(entries: makeEntries(count: 5, startingAt: 100), hasNext: false)
        ])
        let viewModel = LogViewModel(pageFetch: fetcher.fetch)

        // Settle an initial successful reload so nextCursor/loadedVehicleId are populated (an
        // already-loaded vehicle A).
        let firstReload = Task { await viewModel.reload(vehicleId: "vehicle-a") }
        await fetcher.waitForFetchStart()
        fetcher.finishCurrentFetch()
        await firstReload.value
        #expect(viewModel.hasMoreEntries)
        #expect(fetcher.fetchCount == 1)

        // Start a second reload (e.g. a vehicle switch) and leave it mid-flight (isLoading == true).
        let secondReload = Task { await viewModel.reload(vehicleId: "vehicle-b") }
        await fetcher.waitForFetchStart()
        #expect(fetcher.fetchCount == 2)

        // loadMore() must no-op while isLoading is true, even though nextCursor/loadedVehicleId
        // still hold vehicle A's stale values at this point — the exact race the fix closes.
        await viewModel.loadMore()
        #expect(fetcher.fetchCount == 2)

        fetcher.finishCurrentFetch()
        await secondReload.value
        #expect(viewModel.allEntries.count == 5)
    }
}

private extension LogViewModelTests {
    func makeEntries(count: Int, startingAt offset: Int = 0) -> [FirestoreEntry] {
        (0..<count).map { index in
            let ordinal = offset + index
            return FirestoreEntry(
                id: String(format: "entry-%04d", ordinal),
                vehicleId: "vehicle",
                userId: "user",
                entryType: ordinal.isMultiple(of: 2) ? .maintenance : .fuel,
                entryDate: Date(timeIntervalSince1970: TimeInterval(2_000_000 - ordinal)),
                odometerReading: ordinal,
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
}

/// Records what the view model actually ASKED for (page size + resume cursor) while serving real
/// pages out of the in-memory pager, so the request shape is asserted rather than inferred.
@MainActor
private final class RecordingPageFetcher {
    private let entries: [FirestoreEntry]
    private(set) var limits: [Int] = []
    private(set) var cursorIDs: [String?] = []

    init(entries: [FirestoreEntry]) {
        self.entries = entries
    }

    func fetch(query: EntryQuery, limit: Int, cursor: EntryCursor?) async throws -> EntryPage {
        limits.append(limit)
        cursorIDs.append(cursor?.documentID)
        return EntryService.page(entries, matching: query, limit: limit, after: cursor)
    }
}

/// A single canned page, keyed to whether the pager should report more history after it.
private struct EntryPageStub {
    let entries: [FirestoreEntry]
    let hasNext: Bool
}

/// Deterministic loadMore()/reload() concurrency fake: each fetch() call suspends until released,
/// so a test can observe a call mid-flight before deciding what happens next — the same
/// continuation-gated pattern used by ProfileAnalyticsRaceTests for other view models. FIFO queues
/// (not single fields) so that if a guard regresses and a SECOND fetch starts while the first is
/// still pending, the test gets a clean, fast assertion failure instead of a hung continuation.
@MainActor
private final class GatedPageFetcher {
    private var remainingPages: [EntryPageStub]
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var fetchCount = 0

    init(pages: [EntryPageStub]) {
        remainingPages = pages
    }

    func fetch(query: EntryQuery, limit: Int, cursor: EntryCursor?) async throws -> EntryPage {
        fetchCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { pendingContinuations.append($0) }
        guard !remainingPages.isEmpty else { return EntryPage(entries: [], nextCursor: nil) }
        let page = remainingPages.removeFirst()
        let cursor = page.hasNext ? EntryService.cursor(for: page.entries.last) : nil
        return EntryPage(entries: page.entries, nextCursor: cursor)
    }

    /// Suspends until at least one fetch() call is currently in flight (and not yet released).
    func waitForFetchStart() async {
        guard pendingContinuations.isEmpty else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    /// Releases the oldest still-suspended fetch() call (FIFO), letting it consume the next page.
    func finishCurrentFetch() {
        guard !pendingContinuations.isEmpty else { return }
        pendingContinuations.removeFirst().resume()
    }
}
