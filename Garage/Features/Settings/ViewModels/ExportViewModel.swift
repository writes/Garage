import Foundation
import Observation

@MainActor
@Observable
final class ExportViewModel {
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
        do {
            let entries = filterByDate(
                try await entryService.fetchEntries(query: EntryQuery(vehicleId: vehicle.id), limit: 500)
            )
            exportData = csvExportService.export(entries: entries)
            error = nil
        } catch {
            self.error = AppError(from: error)
        }
    }

    private func filterByDate(_ entries: [FirestoreEntry]) -> [FirestoreEntry] {
        entries.filter { entry in
            entry.entryDate >= startDate && entry.entryDate <= endDate
        }
    }
}
