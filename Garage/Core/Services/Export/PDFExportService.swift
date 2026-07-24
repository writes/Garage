import Foundation
import TPPDF

@MainActor
final class PDFExportService {
    static let shared = PDFExportService()

    private init() {}

    /// Entries folded into the TPPDF document model between cooperative yields. Audit finding:
    /// building the document model and running PDFGenerator.generate() used to happen
    /// synchronously on the main actor, which could visibly freeze the UI for vehicles with
    /// thousands of entries. `nonisolated`: read from the detached render task below, which
    /// carries no actor affinity.
    nonisolated private static let entryChunkSize = 200

    /// Builds the resale-ready PDF report entirely off the main actor. Every parameter here
    /// (`Vehicle`, `[FirestoreEntry]`, `[GalleryPhoto]`, `Set<ReportSection>`, `Bool`) is Sendable,
    /// and the TPPDF `PDFDocument`/`PDFGenerator` this constructs (plus the `UIFont`/`UIColor`
    /// they use internally) are created and consumed entirely inside the detached task below — no
    /// MainActor-isolated or non-Sendable state crosses the boundary. Mirrors
    /// `OilAnalysisPDFPreflighter.preflight`'s and `AttachmentPicker.readPDFData`'s
    /// `Task.detached` precedent. Pagination, fonts, and layout are byte-for-byte unchanged from
    /// before this refactor — only where and how the work is scheduled changed.
    nonisolated func buildReport(
        vehicle: Vehicle,
        entries: [FirestoreEntry],
        galleryPhotos: [GalleryPhoto],
        selectedSections: Set<ReportSection>,
        includeReceipts: Bool
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { @Sendable () async throws -> Data in
            try await Self.renderReport(
                vehicle: vehicle,
                entries: entries,
                galleryPhotos: galleryPhotos,
                selectedSections: selectedSections,
                includeReceipts: includeReceipts
            )
        }.value
    }

    /// Document-build + render pass. Runs once inside the detached task created by `buildReport`
    /// above; `buildDocument` is where the cooperative yielding happens, since TPPDF's
    /// `generate(to:)` is a single opaque call into the third-party layout/render engine with no
    /// public per-page hook to yield inside. That single call now always runs off the main actor,
    /// so it no longer blocks the UI regardless of its own internal duration.
    nonisolated private static func renderReport(
        vehicle: Vehicle,
        entries: [FirestoreEntry],
        galleryPhotos: [GalleryPhoto],
        selectedSections: Set<ReportSection>,
        includeReceipts: Bool
    ) async throws -> Data {
        let document = await buildDocument(
            vehicle: vehicle,
            entries: entries,
            galleryPhotos: galleryPhotos,
            selectedSections: selectedSections,
            includeReceipts: includeReceipts
        )
        return try withTemporaryReportFile { url in
            let generator = PDFGenerator(document: document)
            try generator.generate(to: url)
            return try Data(contentsOf: url)
        }
    }

    /// Builds the TPPDF document model — no rendering yet. Split out as its own pure-function seam
    /// (page-model building) so it's unit-testable without PDFGenerator's file-writing side
    /// effects, and so a huge entry list is folded in bounded chunks (`entryChunkSize` entries per
    /// chunk, `Task.yield()` between chunks) rather than one long synchronous pass. Identical
    /// add()/section logic to the pre-refactor synchronous version — only the yielding is new.
    nonisolated static func buildDocument(
        vehicle: Vehicle,
        entries: [FirestoreEntry],
        galleryPhotos: [GalleryPhoto],
        selectedSections: Set<ReportSection>,
        includeReceipts: Bool
    ) async -> PDFDocument {
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

        var sinceYield = 0
        for entry in entries where shouldInclude(entry: entry, selectedSections: selectedSections) {
            document.add(
                .contentLeft,
                text: "\(entry.entryType.displayName) • \(entry.entryDate.shortDisplay)"
            )
            if let notes = entry.notes, notes.isNotEmpty {
                document.add(.contentLeft, text: notes)
            }
            sinceYield += 1
            if sinceYield >= entryChunkSize {
                sinceYield = 0
                await Task.yield()
            }
        }

        if selectedSections.contains(.photoGallery) && !galleryPhotos.isEmpty {
            document.add(.contentLeft, text: "Selected Gallery Photos")
        }

        if includeReceipts && selectedSections.contains(.receipts) {
            document.add(.contentLeft, text: "Receipts and invoices included separately")
        }

        return document
    }

    nonisolated static func withTemporaryReportFile<T>(_ operation: (URL) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory.appending(path: "garage-report-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        return try operation(url)
    }

    nonisolated static func shouldInclude(entry: FirestoreEntry, selectedSections: Set<ReportSection>) -> Bool {
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
