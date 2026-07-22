import Foundation
import Observation

@MainActor
@Observable
final class ExportViewModel {
    typealias EntryPageFetch = @MainActor (EntryQuery, Int, EntryCursor?) async throws -> EntryPage
    private static let exportPageSize = 500
    private static let csvFilenamePrefix = "garage-raw-export-"
    private static var liveCSVURLs: Set<URL> = []
    private struct ActiveCSVArtifact {
        let operationID: UUID
        let writer: CSVExportService.RawExportWriter
        let url: URL
    }
    private let entryService: EntryService
    private let pdfExportService: PDFExportService
    private let csvExportService: CSVExportService
    private let analytics: any AnalyticsTracking
    private let pdfEntryFetch: EntryPageFetch
    private let csvPageFetch: EntryPageFetch
    private let csvURLFactory: () -> URL
    private var pdfAuthorization: PDFExportAuthorization?
    private var csvAuthorization: ExportSessionAuthorization?
    private var observedSession: ExportSessionAuthorization?
    private var activeExportOperationID: UUID?
    private var activeCSVArtifact: ActiveCSVArtifact?
    private static let recordPDFExcludedSections: Set<ReportSection> = [.photoGallery, .receipts]
    var recordPDFSections: [ReportSection] {
        ReportSection.allCases.filter { !Self.recordPDFExcludedSections.contains($0) }
    }
    var selectedSections: Set<ReportSection>
    var startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date.now) ?? Date.now
    var endDate = Date.now
    private(set) var exportData: Data?
    private(set) var csvExportURL: URL?
    private(set) var error: AppError?
    var isExporting: Bool { activeExportOperationID != nil }
    init(
        entryService: EntryService = .shared,
        pdfExportService: PDFExportService = .shared,
        csvExportService: CSVExportService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        pdfEntryFetch: EntryPageFetch? = nil,
        csvPageFetch: EntryPageFetch? = nil,
        csvURLFactory: @escaping () -> URL = {
            FileManager.default.temporaryDirectory
                .appending(path: "garage-raw-export-\(UUID().uuidString).csv")
        }
    ) {
        self.entryService = entryService
        self.pdfExportService = pdfExportService
        self.csvExportService = csvExportService
        self.analytics = analytics
        self.pdfEntryFetch = pdfEntryFetch ?? { query, limit, cursor in
            try await entryService.fetchEntries(query: query, limit: limit, after: cursor)
        }
        self.csvPageFetch = csvPageFetch ?? { query, limit, cursor in
            try await entryService.fetchEntries(query: query, limit: limit, after: cursor)
        }
        self.csvURLFactory = csvURLFactory
        self.selectedSections = Set(ReportSection.allCases).subtracting(Self.recordPDFExcludedSections)
        Self.removeAbandonedCSVExports()
    }
    isolated deinit { discardExportArtifacts() }
    func buildPDF(
        vehicle: Vehicle,
        authorization: @MainActor () -> PDFExportAuthorization?
    ) async {
        guard !isExporting else { return }
        discardExportArtifacts()
        guard let expectedAuthorization = authorization() else { return }
        let operationID = UUID()
        activeExportOperationID = operationID
        defer { finishOperation(ifCurrent: operationID) }
        do {
            let query = EntryQuery(vehicleId: vehicle.id, startDate: startDate, endDate: endDate)
            var cursor: EntryCursor?, entries: [FirestoreEntry] = []
            repeat {
                guard operationIsCurrent(operationID), authorization() == expectedAuthorization else { return }
                let page = try await pdfEntryFetch(query, Self.exportPageSize, cursor)
                entries += page.entries
                cursor = page.nextCursor
            } while cursor != nil
            let resolvedEntries = filterByDate(entries)
            guard operationIsCurrent(operationID), authorization() == expectedAuthorization else { return }
            exportData = try pdfExportService.buildReport(
                vehicle: vehicle,
                entries: resolvedEntries,
                galleryPhotos: [],
                selectedSections: selectedSections,
                includeReceipts: false
            )
            pdfAuthorization = expectedAuthorization
            analytics.track(.exportPDF(entryCount: resolvedEntries.count))
        } catch {
            guard operationIsCurrent(operationID), authorization() == expectedAuthorization else { return }
            self.error = AppError(from: error)
        }
    }
    func buildCSV(
        vehicle: Vehicle,
        authorization: @MainActor () -> ExportSessionAuthorization?
    ) async {
        guard !isExporting else { return }
        discardExportArtifacts()
        guard let expectedAuthorization = authorization() else { return }
        let operationID = UUID()
        activeExportOperationID = operationID
        defer { finishOperation(ifCurrent: operationID) }
        let url = csvURLFactory()
        do {
            let writer = try csvExportService.makeRawExportWriter(at: url)
            var didFinish = false
            trackCSV(writer: writer, url: url, operationID: operationID)
            defer {
                if !didFinish { cleanupCSV(writer: writer, url: url, operationID: operationID) }
            }
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            guard let entryCount = try await appendCSVPages(
                vehicleID: vehicle.id, writer: writer, operationID: operationID,
                expectedAuthorization: expectedAuthorization, authorization: authorization
            ) else { return }
            try writer.finish()
            guard operationIsCurrent(operationID),
                  authorization() == expectedAuthorization else { return }
            didFinish = true
            releaseActiveCSV(ifCurrent: operationID)
            csvExportURL = url
            csvAuthorization = expectedAuthorization
            exportData = nil
            pdfAuthorization = nil
            analytics.track(.exportCSV(entryCount: entryCount))
        } catch {
            Self.removeCSVFile(url)
            guard operationIsCurrent(operationID),
                  authorization() == expectedAuthorization else { return }
            self.error = AppError(from: error)
        }
    }
    func authorizedPDFData(for authorization: PDFExportAuthorization?) -> Data? {
        guard let authorization, pdfAuthorization == authorization else { return nil }
        return exportData
    }
    func authorizedCSVURL(for authorization: ExportSessionAuthorization?) -> URL? {
        guard let authorization, csvAuthorization == authorization else { return nil }
        return csvExportURL
    }

    func sessionChanged(to authorization: ExportSessionAuthorization?) {
        guard observedSession != authorization else { return }
        observedSession = authorization
        discardExportArtifacts()
    }

    func discardExportArtifacts() {
        activeExportOperationID = nil
        cancelActiveCSV()
        exportData = nil
        pdfAuthorization = nil
        error = nil
        discardCSVExport()
    }
}

private extension ExportViewModel {
    private func operationIsCurrent(_ operationID: UUID) -> Bool {
        activeExportOperationID == operationID
    }
    private func finishOperation(ifCurrent operationID: UUID) {
        if operationIsCurrent(operationID) { activeExportOperationID = nil }
    }
    private func trackCSV(writer: CSVExportService.RawExportWriter, url: URL, operationID: UUID) {
        activeCSVArtifact = .init(operationID: operationID, writer: writer, url: url)
        Self.liveCSVURLs.insert(url)
    }
    private func releaseActiveCSV(ifCurrent operationID: UUID) {
        if activeCSVArtifact?.operationID == operationID { activeCSVArtifact = nil }
    }

    private func cancelActiveCSV() {
        guard let artifact = activeCSVArtifact else { return }
        cleanupCSV(writer: artifact.writer, url: artifact.url, operationID: artifact.operationID)
    }

    private func cleanupCSV(
        writer: CSVExportService.RawExportWriter, url: URL, operationID: UUID
    ) {
        writer.cancel()
        releaseActiveCSV(ifCurrent: operationID)
        Self.liveCSVURLs.remove(url)
        Self.removeCSVFile(url)
    }

    private func appendCSVPages(
        vehicleID: String,
        writer: CSVExportService.RawExportWriter,
        operationID: UUID,
        expectedAuthorization: ExportSessionAuthorization,
        authorization: @MainActor () -> ExportSessionAuthorization?
    ) async throws -> Int? {
        var cursor: EntryCursor?
        var entryCount = 0
        repeat {
            guard operationIsCurrent(operationID),
                  authorization() == expectedAuthorization else { return nil }
            let page = try await csvPageFetch(
                EntryQuery(vehicleId: vehicleID), Self.exportPageSize, cursor
            )
            guard operationIsCurrent(operationID),
                  authorization() == expectedAuthorization else { return nil }
            try writer.append(entries: page.entries)
            entryCount += page.entries.count
            cursor = page.nextCursor
        } while cursor != nil
        return entryCount
    }

    private func discardCSVExport() {
        csvAuthorization = nil
        guard let csvExportURL else { return }
        Self.liveCSVURLs.remove(csvExportURL)
        Self.removeCSVFile(csvExportURL)
        self.csvExportURL = nil
    }

    private static func removeAbandonedCSVExports() {
        let directory = FileManager.default.temporaryDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in urls where url.lastPathComponent.hasPrefix(csvFilenamePrefix)
            && url.pathExtension == "csv" && !liveCSVURLs.contains(url) {
            removeCSVFile(url)
        }
    }

    private static func removeCSVFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch {
            AppLogger.shared.error("Failed to remove a temporary CSV export.")
        }
    }

    private func filterByDate(_ entries: [FirestoreEntry]) -> [FirestoreEntry] {
        entries.filter { $0.entryDate >= startDate && $0.entryDate <= endDate }
    }
}
