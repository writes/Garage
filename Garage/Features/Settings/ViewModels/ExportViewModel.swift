import Foundation
import Observation

@MainActor
@Observable
final class ExportViewModel {
    typealias EntryPageFetch = @MainActor (EntryQuery, Int, EntryCursor?) async throws -> EntryPage
    // `internal` (not `private`): ExportViewModel+CSVArtifact.swift's appendCSVPages reads this too.
    static let exportPageSize = 500
    // `internal` (not `private`): ExportViewModel+CSVArtifact.swift's tracking/cleanup helpers
    // need this prefix for the launch-time abandoned-file sweep.
    static let csvFilenamePrefix = "garage-raw-export-"
    static var liveCSVURLs: Set<URL> = []
    /// `internal` (not `private`), same reason: constructed/read/written from the CSV-artifact
    /// extension file's trackCSV/cleanupCSV/cancelActiveCSV helpers.
    struct ActiveCSVArtifact {
        let operationID: UUID
        let writer: CSVExportService.RawExportWriter
        let url: URL
    }
    private let entryService: EntryService
    private let pdfExportService: PDFExportService
    private let csvExportService: CSVExportService
    private let analytics: any AnalyticsTracking
    // A closure so tests can substitute a recorder. The DEFAULT is the real store, never a no-op:
    // a feature whose production path needs every call site to opt in is a feature that ships dead.
    private let recordReviewMoment: @MainActor (ReviewMoment) -> Void
    private let pdfEntryFetch: EntryPageFetch
    // `internal` (not `private`): read by ExportViewModel+CSVArtifact.swift's appendCSVPages.
    let csvPageFetch: EntryPageFetch
    private let csvURLFactory: () -> URL
    // `internal` (not `private`), matching the EntryService+Mutations split precedent:
    // ExportViewModel+PDFArtifact.swift needs these to persist/expose/discard the PDF temp file.
    let pdfURLFactory: () -> URL
    private(set) var pdfAuthorization: PDFExportAuthorization?
    var pdfExportURL: URL?
    static var livePDFURLs: Set<URL> = []
    // `internal` (not `private`): written by ExportViewModel+CSVArtifact.swift's discardCSVExport.
    var csvAuthorization: ExportSessionAuthorization?
    private var observedSession: ExportSessionAuthorization?
    private var activeExportOperationID: UUID?
    // `internal` (not `private`): tracked by ExportViewModel+CSVArtifact.swift's trackCSV/cleanupCSV.
    var activeCSVArtifact: ActiveCSVArtifact?
    private static let recordPDFExcludedSections: Set<ReportSection> = [.photoGallery, .receipts]
    var recordPDFSections: [ReportSection] {
        ReportSection.allCases.filter { !Self.recordPDFExcludedSections.contains($0) }
    }
    var selectedSections: Set<ReportSection>
    var startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date.now) ?? Date.now
    var endDate = Date.now
    private(set) var exportData: Data?
    // `internal` (not `private(set)`): ExportViewModel+CSVArtifact.swift's discardCSVExport clears this.
    var csvExportURL: URL?
    private(set) var error: AppError?
    var isExporting: Bool { activeExportOperationID != nil }
    init(
        entryService: EntryService = .shared,
        pdfExportService: PDFExportService = .shared,
        csvExportService: CSVExportService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        recordReviewMoment: @escaping @MainActor (ReviewMoment) -> Void = { ReviewPromptStore.shared.record($0) },
        pdfEntryFetch: EntryPageFetch? = nil,
        csvPageFetch: EntryPageFetch? = nil,
        csvURLFactory: @escaping () -> URL = {
            FileManager.default.temporaryDirectory
                .appending(path: "garage-raw-export-\(UUID().uuidString).csv")
        },
        pdfURLFactory: @escaping () -> URL = {
            FileManager.default.temporaryDirectory
                .appending(path: "garage-record-pdf-\(UUID().uuidString).pdf")
        }
    ) {
        self.entryService = entryService
        self.pdfExportService = pdfExportService
        self.csvExportService = csvExportService
        self.analytics = analytics
        self.recordReviewMoment = recordReviewMoment
        self.pdfEntryFetch = pdfEntryFetch ?? { query, limit, cursor in
            try await entryService.fetchEntries(query: query, limit: limit, after: cursor)
        }
        self.csvPageFetch = csvPageFetch ?? { query, limit, cursor in
            try await entryService.fetchEntries(query: query, limit: limit, after: cursor)
        }
        self.csvURLFactory = csvURLFactory
        self.pdfURLFactory = pdfURLFactory
        self.selectedSections = Set(ReportSection.allCases).subtracting(Self.recordPDFExcludedSections)
        Self.removeAbandonedCSVExports()
        Self.removeAbandonedPDFExports()
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
            let windowStart = startDate, windowEnd = endDate
            let query = EntryQuery(vehicleId: vehicle.id, startDate: windowStart, endDate: windowEnd)
            var cursor: EntryCursor?, entries: [FirestoreEntry] = []
            repeat {
                guard operationIsCurrent(operationID), authorization() == expectedAuthorization else { return }
                let page = try await pdfEntryFetch(query, Self.exportPageSize, cursor)
                entries += page.entries
                cursor = page.nextCursor
            } while cursor != nil
            let resolvedEntries = filterByDate(entries, start: windowStart, end: windowEnd)
            guard operationIsCurrent(operationID), authorization() == expectedAuthorization else { return }
            // buildReport now renders off the main actor (detached task) and cooperatively yields
            // across a large entry list, so it suspends here — unlike the rest of this function,
            // the MainActor is free to run other work (a session change, a new export) while it's
            // in flight. Land the render into a local first and re-check currency before touching
            // any `self.` state, so a stale/cancelled operation can't resurrect exportData or
            // persist a PDF after discardExportArtifacts() already cleared it.
            let renderedData = try await pdfExportService.buildReport(
                vehicle: vehicle,
                entries: resolvedEntries,
                galleryPhotos: [],
                selectedSections: selectedSections,
                includeReceipts: false
            )
            guard operationIsCurrent(operationID), authorization() == expectedAuthorization else { return }
            exportData = renderedData
            // Persisted before pdfAuthorization is set, so a write failure leaves both
            // authorizedPDFData(for:) and authorizedPDFURL(for:) unauthorized/nil together —
            // no half-authorized state for ExportView to render.
            try persistPDFArtifact()
            pdfAuthorization = expectedAuthorization
            analytics.track(.exportPDF(entryCount: resolvedEntries.count))
            // The dossier is the reason to keep a service log at all — the app's peak-value moment.
            recordReviewMoment(.pdfExported)
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
            Self.removeExportFile(url)
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
        discardPDFExport()
    }
}

private extension ExportViewModel {
    func filterByDate(_ entries: [FirestoreEntry], start: Date, end: Date) -> [FirestoreEntry] {
        entries.filter { $0.entryDate >= start && $0.entryDate <= end }
    }
}

// MARK: - Operation-lifetime tracking shared by buildPDF, buildCSV, and both artifact extensions

extension ExportViewModel {
    func operationIsCurrent(_ operationID: UUID) -> Bool {
        activeExportOperationID == operationID
    }
    func finishOperation(ifCurrent operationID: UUID) {
        if operationIsCurrent(operationID) { activeExportOperationID = nil }
    }
}

// MARK: - Shared temp-export-file plumbing (not `private extension`: ExportViewModel+PDFArtifact.swift calls both)

extension ExportViewModel {
    /// Shared by the CSV sweep above and the PDF sweep in ExportViewModel+PDFArtifact.swift: on
    /// launch, delete any temp export file left behind by a prior process death (crash, force
    /// quit) that never got a chance to run discardExportArtifacts().
    static func removeAbandonedExports(prefix: String, extension fileExtension: String, liveURLs: Set<URL>) {
        let directory = FileManager.default.temporaryDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in urls where url.lastPathComponent.hasPrefix(prefix)
            && url.pathExtension == fileExtension && !liveURLs.contains(url) {
            removeExportFile(url)
        }
    }

    static func removeExportFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) } catch {
            AppLogger.shared.error("Failed to remove a temporary export file.")
        }
    }
}
