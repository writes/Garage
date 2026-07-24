import Foundation
import Testing
@testable import Garage
@MainActor
struct ExportPDFPaginationTests {
    @Test func buildPDF_exportsAllEntriesAcrossMultiplePages() async {
        let fetch = EntryPageFetchProbe()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let entries = recentEntries(count: 600)
        let firstPage = Array(entries.prefix(500)), secondPage = Array(entries[500...])
        let viewModel = ExportViewModel(analytics: analytics, pdfEntryFetch: fetch.load)
        let task = Task {
            await viewModel.buildPDF(vehicle: vehicle, authorization: { pdfAuthorization })
        }
        await fetch.waitUntilCalled()
        fetch.resolveNext(EntryPage(entries: firstPage, nextCursor: EntryService.cursor(for: firstPage.last)))
        await fetch.waitUntilCalled(2)
        fetch.resolveNext(EntryPage(entries: secondPage, nextCursor: nil))
        await task.value
        #expect(fetch.calls == 2 && viewModel.error == nil)
        #expect(viewModel.exportData?.isEmpty == false)
        #expect(analytics.events == [.exportPDF(entryCount: 600)])
    }
    @Test func buildPDF_carriesDateWindowBoundsOnEveryPageQuery() async {
        let fetch = EntryPageFetchProbe()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = ExportViewModel(analytics: analytics, pdfEntryFetch: fetch.load)
        viewModel.startDate = Date(timeIntervalSince1970: 1_000)
        viewModel.endDate = Date(timeIntervalSince1970: 2_000)
        let inWindow = makeEntry(id: "in-window", date: Date(timeIntervalSince1970: 1_500))
        let task = Task {
            await viewModel.buildPDF(vehicle: vehicle, authorization: { pdfAuthorization })
        }
        await fetch.waitUntilCalled()
        fetch.resolveNext(EntryPage(entries: [inWindow], nextCursor: EntryService.cursor(for: inWindow)))
        await fetch.waitUntilCalled(2)
        fetch.resolveNext(EntryPage(entries: [], nextCursor: nil))
        await task.value
        let expectedQuery = EntryQuery(
            vehicleId: vehicle.id,
            startDate: Date(timeIntervalSince1970: 1_000), endDate: Date(timeIntervalSince1970: 2_000)
        )
        #expect(fetch.queries == [expectedQuery, expectedQuery])
        #expect(viewModel.exportData?.isEmpty == false)
        #expect(analytics.events == [.exportPDF(entryCount: 1)])
    }
    private var vehicle: Vehicle {
        Vehicle(id: "vehicle", userId: "user", nickname: "Test Vehicle", make: "Garage",
                model: "Test", year: 2026, currentOdometer: 0)
    }
    private var pdfAuthorization: PDFExportAuthorization {
        .init(session: ExportSessionAuthorization(
            authenticationRevision: 1, subscriptionRevision: 1,
            vehicleID: vehicle.id, vehicleOwnerID: vehicle.userId
        ))
    }
    private func recentEntries(count: Int) -> [FirestoreEntry] {
        let now = Date.now.timeIntervalSince1970
        return (0..<count).map {
            makeEntry(id: String(format: "entry-%04d", $0), date: Date(timeIntervalSince1970: now - Double($0)))
        }
    }
}
@MainActor
struct EntryServiceDateBoundsTests {
    @Test func fetchEntries_appliesInclusiveDateBounds() async throws {
        let service = EntryService(testEntries: [
            makeEntry(id: "before", date: Date(timeIntervalSince1970: 99)),
            makeEntry(id: "start", date: Date(timeIntervalSince1970: 100)),
            makeEntry(id: "inside", date: Date(timeIntervalSince1970: 150)),
            makeEntry(id: "end", date: Date(timeIntervalSince1970: 200)),
            makeEntry(id: "after", date: Date(timeIntervalSince1970: 201))
        ])
        let entries = try await service.fetchEntries(query: EntryQuery(
            vehicleId: "vehicle",
            startDate: Date(timeIntervalSince1970: 100), endDate: Date(timeIntervalSince1970: 200)
        ))
        #expect(entries.map(\.id) == ["end", "inside", "start"])
    }
}
private func makeEntry(id: String, date: Date) -> FirestoreEntry {
    FirestoreEntry(
        id: id, vehicleId: "vehicle", userId: "user", entryType: .maintenance,
        entryDate: date, odometerReading: 0, cost: nil, isDiy: nil, shopName: nil, notes: nil,
        attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
    )
}
