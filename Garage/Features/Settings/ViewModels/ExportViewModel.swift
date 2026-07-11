import Foundation
import Observation

@MainActor
@Observable
final class ExportViewModel {
    private static let csvPageSize = 500

    private let entryService: EntryService
    private let galleryService: GalleryService
    private let pdfExportService: PDFExportService
    private let csvExportService: CSVExportService

    var selectedSections = Set(ReportSection.allCases)
    var startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date.now) ?? Date.now
    var endDate = Date.now
    var includeGalleryPhotos = true
    var includeReceipts = true
    private(set) var exportData: Data?
    private(set) var csvExportURL: URL?
    private(set) var error: AppError?

    init(
        entryService: EntryService = .shared,
        galleryService: GalleryService = .shared,
        pdfExportService: PDFExportService = .shared,
        csvExportService: CSVExportService = .shared
    ) {
        self.entryService = entryService
        self.galleryService = galleryService
        self.pdfExportService = pdfExportService
        self.csvExportService = csvExportService
    }

    func buildPDF(vehicle: Vehicle) async {
        do {
            async let entries = entryService.fetchEntries(query: EntryQuery(vehicleId: vehicle.id), limit: 200)
            async let photos = galleryService.fetchPhotos(vehicleId: vehicle.id)
            let resolvedEntries = filterByDate(try await entries)
            let resolvedPhotos = includeGalleryPhotos ? try await photos : []
            exportData = try pdfExportService.buildReport(
                vehicle: vehicle,
                entries: resolvedEntries,
                galleryPhotos: resolvedPhotos,
                selectedSections: selectedSections,
                includeReceipts: includeReceipts
            )
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }

    func buildCSV(vehicle: Vehicle) async {
        discardCSVExport()
        let url = FileManager.default.temporaryDirectory
            .appending(path: "garage-raw-export-\(UUID().uuidString).csv")

        do {
            let writer = try csvExportService.makeRawExportWriter(at: url)
            var didFinish = false
            defer {
                if !didFinish {
                    writer.cancel()
                }
            }

            var cursor: EntryCursor?
            repeat {
                let page = try await entryService.fetchEntries(
                    query: EntryQuery(vehicleId: vehicle.id),
                    limit: Self.csvPageSize,
                    after: cursor
                )
                try writer.append(entries: page.entries)
                cursor = page.nextCursor
            } while cursor != nil

            try writer.finish()
            didFinish = true
            csvExportURL = url
            exportData = nil
            error = nil
        } catch {
            try? FileManager.default.removeItem(at: url)
            self.error = AppError(from: error)
        }
    }

    private func discardCSVExport() {
        guard let csvExportURL else { return }
        try? FileManager.default.removeItem(at: csvExportURL)
        self.csvExportURL = nil
    }

    private func filterByDate(_ entries: [FirestoreEntry]) -> [FirestoreEntry] {
        entries.filter { entry in
            entry.entryDate >= startDate && entry.entryDate <= endDate
        }
    }
}
