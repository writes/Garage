import Foundation
import Testing
@testable import Garage
@MainActor
struct ExportViewModelTests {
    @Test func initialState_hasNoExportData() {
        let abandoned = FileManager.default.temporaryDirectory
            .appending(path: "garage-raw-export-test-\(UUID().uuidString).csv")
        #expect(FileManager.default.createFile(atPath: abandoned.path, contents: Data()))
        let viewModel = ExportViewModel()
        #expect(viewModel.exportData == nil && viewModel.error == nil)
        #expect(!viewModel.recordPDFSections.contains(.photoGallery)
            && !viewModel.recordPDFSections.contains(.receipts))
        #expect(viewModel.selectedSections == Set(viewModel.recordPDFSections))
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
    }
    @Test func buildCSV_exportsAllPagesAndEntireHistory() async throws {
        let entries = csvEntries()
        let entryService = EntryService(testEntries: Array(entries.reversed()))
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = ExportViewModel(entryService: entryService, analytics: analytics)
        await viewModel.buildCSV(vehicle: vehicle, authorization: { sessionA })
        #expect(viewModel.error == nil)
        let url = try #require(viewModel.csvExportURL, "Expected a retrievable CSV export URL")
        defer { try? FileManager.default.removeItem(at: url) }
        let csv = try String(contentsOf: url, encoding: .utf8)
        let rows = csv.components(separatedBy: "\r\n").filter(\.isNotEmpty)
        let ids = rows.dropFirst().map { $0.components(separatedBy: ",")[1] }
        let expectedIDs = entries
            .sorted {
                if $0.entryDate != $1.entryDate {
                    return $0.entryDate > $1.entryDate
                }
                return $0.id > $1.id
            }
            .map(\.id)
        #expect(url.pathExtension == "csv")
        #expect(rows.count == 1_204 && ids.count == 1_203 && Set(ids).count == 1_203)
        #expect(ids == expectedIDs && ids.contains("entry-1202"))
        #expect(analytics.events == [.exportCSV(entryCount: 1_203)])
        #expect(analytics.events.map(\.definition) == [
            AnalyticsEventDefinition(name: "export_csv", parameters: [.entryCount(1_203)])])
    }
    @Test func buildPDF_emitsExportEventWithResolvedEntryCountAndSchemaVersion() async {
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = ExportViewModel(
            entryService: EntryService(testEntries: Array(csvEntries().prefix(2))),
            analytics: analytics
        )
        await viewModel.buildPDF(vehicle: vehicle, authorization: { pdfAuthorizationA })
        #expect(viewModel.error == nil)
        #expect(viewModel.exportData?.isEmpty == false)
        #expect(analytics.events == [.exportPDF(entryCount: 2)])
        #expect(analytics.events.map(\.definition) == [
            AnalyticsEventDefinition(name: "export_pdf", parameters: [.entryCount(2)])
        ])
    }
    @Test func deniedBeforeFetchProducesNoPDFAndNoAnalytics() async {
        let fetch = EntryPageFetchProbe()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        let viewModel = ExportViewModel(analytics: analytics, pdfEntryFetch: fetch.load)
        await viewModel.buildPDF(vehicle: vehicle, authorization: { nil })
        #expect(fetch.calls == 0)
        #expect(viewModel.exportData == nil)
        #expect(analytics.events.isEmpty)
    }
    @Test func revocationDuringFetchProducesNoPDFAndNoAnalytics() async {
        let fetch = EntryPageFetchProbe()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        var authorization: PDFExportAuthorization? = pdfAuthorizationA
        let viewModel = ExportViewModel(analytics: analytics, pdfEntryFetch: fetch.load)
        let task = Task {
            await viewModel.buildPDF(vehicle: vehicle, authorization: { authorization })
        }
        await fetch.waitUntilCalled()
        authorization = nil
        fetch.resolve([])
        await task.value
        #expect(fetch.calls == 1)
        #expect(viewModel.exportData == nil)
        #expect(analytics.events.isEmpty)
    }
    private var vehicle: Vehicle {
        Vehicle(id: "vehicle", userId: "user", nickname: "Test Vehicle", make: "Garage",
                model: "Test", year: 2026, currentOdometer: 0)
    }
    private var sessionA: ExportSessionAuthorization {
        ExportSessionAuthorization(authenticationRevision: 1, subscriptionRevision: 1,
                                   vehicleID: vehicle.id, vehicleOwnerID: vehicle.userId)
    }
    private var pdfAuthorizationA: PDFExportAuthorization { .init(session: sessionA) }
    private func csvEntries() -> [FirestoreEntry] {
        let now = Date.now.timeIntervalSince1970
        return (0..<1_203).map { index in
            FirestoreEntry(
                id: String(format: "entry-%04d", index), vehicleId: "vehicle", userId: "user",
                entryType: .maintenance,
                entryDate: Date(timeIntervalSince1970: csvDate(for: index, now: now)),
                odometerReading: index, cost: nil, isDiy: nil, shopName: nil, notes: nil,
                attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
            )
        }
    }
    private func csvDate(for index: Int, now: TimeInterval) -> TimeInterval {
        if (495...505).contains(index) { return now - 495 }
        if (995...1_005).contains(index) { return now - 995 }
        if index == 1_202 { return now - 63_072_000 }
        return now - Double(index)
    }
}
@MainActor
struct ExportSessionIsolationTests {
    @Test func exportAuthorizationRequiresCurrentAuthenticatedOwner() {
        #expect(ExportSessionAuthorization.resolve(
            authenticationRevision: 2, subscriptionRevision: 5, authenticatedUserID: "user-b",
            currentVehicle: vehicleA, requestedVehicle: vehicleA) == nil)
        #expect(ExportSessionAuthorization.resolve(
            authenticationRevision: 1, subscriptionRevision: 3, authenticatedUserID: "user-a",
            currentVehicle: vehicleA, requestedVehicle: vehicleA) == sessionA)
    }
    @Test func paidAccountSwitchDuringPDFFetchPublishesNothing() async {
        let fetch = EntryPageFetchProbe()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        var authorization: PDFExportAuthorization? = .init(session: sessionA)
        let viewModel = ExportViewModel(analytics: analytics, pdfEntryFetch: fetch.load)
        let task = Task {
            await viewModel.buildPDF(vehicle: vehicleA, authorization: { authorization })
        }
        await fetch.waitUntilCalled()
        authorization = .init(session: sessionB)
        fetch.resolve([entryA])
        await task.value
        #expect(fetch.calls == 1 && viewModel.exportData == nil)
        #expect(viewModel.authorizedPDFData(for: authorization) == nil)
        #expect(analytics.events.isEmpty)
    }
    @Test func accountSwitchAfterWrittenCSVPageDeletesPartialOutput() async throws {
        let fetch = EntryPageFetchProbe()
        let analytics = AnalyticsSpy()
        analytics.setEnabled(true)
        var authorization: ExportSessionAuthorization? = sessionA
        let url = tempCSVURL("identity")
        let firstPage = try await EntryService(testEntries: [entryA]).fetchEntries(
            query: EntryQuery(vehicleId: vehicleA.id), limit: 1, after: nil)
        let viewModel = ExportViewModel(
            analytics: analytics,
            csvPageFetch: fetch.load,
            csvURLFactory: { url }
        )
        let task = Task {
            await viewModel.buildCSV(vehicle: vehicleA, authorization: { authorization })
        }
        await fetch.waitUntilCalled()
        fetch.resolveNext(firstPage)
        await fetch.waitUntilCalled(2)
        authorization = sessionB
        viewModel.sessionChanged(to: sessionB)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        fetch.resolveNext(EntryPage(entries: [], nextCursor: nil))
        await task.value
        #expect(fetch.calls == 2 && viewModel.csvExportURL == nil)
        #expect(viewModel.authorizedCSVURL(for: authorization) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(analytics.events.isEmpty)
    }
    @Test func sessionChangeClearsPDFAndDeletesRetainedCSV() async throws {
        let entryService = EntryService(testEntries: [entryA])
        let viewModel = ExportViewModel(entryService: entryService)
        viewModel.sessionChanged(to: sessionA)
        await viewModel.buildPDF(
            vehicle: vehicleA,
            authorization: { PDFExportAuthorization(session: sessionA) }
        )
        #expect(viewModel.authorizedPDFData(for: .init(session: sessionA)) != nil)
        viewModel.sessionChanged(to: sessionB)
        #expect(viewModel.exportData == nil && viewModel.authorizedPDFData(for: .init(session: sessionB)) == nil)
        viewModel.sessionChanged(to: sessionA)
        await viewModel.buildCSV(vehicle: vehicleA, authorization: { sessionA })
        let url = try #require(viewModel.csvExportURL, "Expected session CSV")
        viewModel.sessionChanged(to: sessionB)
        #expect(viewModel.csvExportURL == nil && !FileManager.default.fileExists(atPath: url.path))
    }
    @Test func concurrentCSVBuildIsRejectedWithoutOpeningAnotherFile() async {
        let fetch = EntryPageFetchProbe()
        let analytics = AnalyticsSpy(); analytics.setEnabled(true)
        let firstURL = tempCSVURL("first"), secondURL = tempCSVURL("second")
        let urls = CSVURLSequence([firstURL, secondURL])
        let viewModel = ExportViewModel(
            analytics: analytics, csvPageFetch: fetch.load, csvURLFactory: urls.next)
        let first = Task { await viewModel.buildCSV(vehicle: vehicleA, authorization: { sessionA }) }
        await fetch.waitUntilCalled()
        let second = Task { await viewModel.buildCSV(vehicle: vehicleA, authorization: { sessionA }) }
        await second.value
        #expect(fetch.calls == 1 && urls.calls == 1 && viewModel.isExporting)
        fetch.resolveNext(EntryPage(entries: [entryA], nextCursor: nil)); await first.value
        #expect(viewModel.csvExportURL == firstURL && !viewModel.isExporting)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(!FileManager.default.fileExists(atPath: secondURL.path))
        #expect(analytics.events == [.exportCSV(entryCount: 1)])
        viewModel.discardExportArtifacts()
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
    }
    @Test func teardownDuringCSVFetchDeletesLateOutput() async {
        let fetch = EntryPageFetchProbe()
        let analytics = AnalyticsSpy(); analytics.setEnabled(true)
        let url = tempCSVURL("teardown")
        let viewModel = ExportViewModel(
            analytics: analytics, csvPageFetch: fetch.load, csvURLFactory: { url })
        let task = Task { await viewModel.buildCSV(vehicle: vehicleA, authorization: { sessionA }) }
        await fetch.waitUntilCalled()
        viewModel.discardExportArtifacts()
        #expect(!viewModel.isExporting && !FileManager.default.fileExists(atPath: url.path))
        fetch.resolveNext(EntryPage(entries: [entryA], nextCursor: nil))
        await task.value
        #expect(viewModel.csvExportURL == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(analytics.events.isEmpty)
    }
    private var vehicleA: Vehicle {
        Vehicle(
            id: "vehicle-a", userId: "user-a", nickname: "A", make: "Garage",
            model: "Test", year: 2026, currentOdometer: 1
        )
    }
    private var sessionA: ExportSessionAuthorization {
        .init(authenticationRevision: 1, subscriptionRevision: 3,
              vehicleID: "vehicle-a", vehicleOwnerID: "user-a")
    }
    private var sessionB: ExportSessionAuthorization {
        .init(authenticationRevision: 2, subscriptionRevision: 5,
              vehicleID: "vehicle-b", vehicleOwnerID: "user-b")
    }
    private var entryA: FirestoreEntry {
        FirestoreEntry(
            id: "entry-a", vehicleId: "vehicle-a", userId: "user-a",
            entryType: .maintenance, entryDate: .now, odometerReading: 1,
            cost: nil, isDiy: nil, shopName: nil, notes: "account-a",
            attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
        )
    }
    private func tempCSVURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "garage-export-\(label)-\(UUID().uuidString).csv")
    }
}
