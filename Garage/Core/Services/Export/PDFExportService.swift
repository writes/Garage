import Foundation
import TPPDF

@MainActor
final class PDFExportService {
    static let shared = PDFExportService()

    private init() {}

    func buildReport(
        vehicle: Vehicle,
        entries: [FirestoreEntry],
        galleryPhotos: [GalleryPhoto],
        selectedSections: Set<ReportSection>,
        includeReceipts: Bool
    ) throws -> Data {
        let document = PDFDocument(format: .a4)
        if selectedSections.contains(.vehicleInfo) {
            document.set(font: Font.boldSystemFont(ofSize: 22))
            document.add(.contentLeft, text: vehicle.displayName)
            document.set(font: Font.systemFont(ofSize: 12))
            document.add(.contentLeft, text: "Current odometer: \(vehicle.currentOdometer.formatted()) mi")
        }

        if selectedSections.contains(.vehicleHistoryPlaceholder) {
            document.add(.contentLeft, text: "Vehicle History: Not connected")
        }

        for entry in entries where shouldInclude(entry: entry, selectedSections: selectedSections) {
            document.add(
                .contentLeft,
                text: "\(entry.entryType.displayName) • \(entry.entryDate.shortDisplay)"
            )
            if let notes = entry.notes, notes.isNotEmpty {
                document.add(.contentLeft, text: notes)
            }
        }

        if selectedSections.contains(.photoGallery) && !galleryPhotos.isEmpty {
            document.add(.contentLeft, text: "Selected Gallery Photos")
        }

        if includeReceipts && selectedSections.contains(.receipts) {
            document.add(.contentLeft, text: "Receipts and invoices included separately")
        }

        let url = FileManager.default.temporaryDirectory.appending(path: "garage-report-\(UUID().uuidString).pdf")
        let generator = PDFGenerator(document: document)
        try generator.generate(to: url)
        return try Data(contentsOf: url)
    }

    private func shouldInclude(entry: FirestoreEntry, selectedSections: Set<ReportSection>) -> Bool {
        switch entry.entryType {
        case .oilChange, .oilConsumption, .oilAnalysis:
            return selectedSections.contains(.oilHistory)
        case .fuel, .maintenance, .repair:
            return selectedSections.contains(.maintenanceHistory)
        case .tire:
            return selectedSections.contains(.tireHistory)
        case .brake:
            return selectedSections.contains(.brakeHistory)
        case .alignment:
            return selectedSections.contains(.alignmentRecords)
        case .trackDay:
            return selectedSections.contains(.trackDays)
        case .upgrade:
            return selectedSections.contains(.upgrades)
        case .dmeReport:
            return selectedSections.contains(.maintenanceHistory)
        }
    }
}
