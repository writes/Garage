import Foundation
import Testing
import TPPDF
@testable import Garage

struct PDFExportServiceTests {
    @Test func shouldInclude_mapsEveryEntryCategoryToItsReportSection() {
        let mappings: [(EntryType, ReportSection)] = [
            (.oilChange, .oilHistory), (.oilConsumption, .oilHistory), (.oilAnalysis, .oilHistory),
            (.fuel, .maintenanceHistory), (.maintenance, .maintenanceHistory), (.repair, .maintenanceHistory),
            (.tire, .tireHistory), (.brake, .brakeHistory), (.alignment, .alignmentRecords),
            (.trackDay, .trackDays), (.upgrade, .upgrades), (.dmeReport, .maintenanceHistory)
        ]

        for (type, section) in mappings {
            #expect(PDFExportService.shouldInclude(entry: entry(type: type), selectedSections: [section]))
            #expect(!PDFExportService.shouldInclude(entry: entry(type: type), selectedSections: []))
        }
    }

    @Test func temporaryReportFile_isRemovedAfterSuccessfulOperation() throws {
        var url: URL?

        _ = try PDFExportService.withTemporaryReportFile { temporaryURL in
            url = temporaryURL
            try Data("report".utf8).write(to: temporaryURL)
            return temporaryURL
        }

        #expect(url.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false)
    }

    @Test func temporaryReportFile_isRemovedAfterFailingOperation() {
        var url: URL?

        do {
            _ = try PDFExportService.withTemporaryReportFile { temporaryURL in
                url = temporaryURL
                try Data("partial report".utf8).write(to: temporaryURL)
                throw PDFTestError.failed
            }
            Issue.record("Expected temporary report operation to throw")
        } catch {
            #expect(error as? PDFTestError == .failed)
        }

        #expect(url.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false)
    }

    // MARK: - Scale/threading refactor coverage (audit-flagged: rendering thousands of entries
    // used to run synchronously on the main actor). buildDocument is the pure page-model-building
    // seam PDFExportService.buildReport delegates to; these exercise it directly (still off any
    // actor — buildDocument is nonisolated) plus a real TPPDF render, without needing the
    // MainActor-isolated `.shared` singleton.

    @Test func buildDocument_rendersNonEmptyDataForALargeSyntheticEntrySet() async throws {
        let document = await PDFExportService.buildDocument(
            vehicle: vehicle,
            entries: syntheticEntries(count: 2_000),
            galleryPhotos: [],
            selectedSections: Set(ReportSection.allCases),
            includeReceipts: false
        )

        let data = try PDFGenerator(document: document).generateData()

        #expect(!data.isEmpty)
    }

    @Test func buildDocument_pageCountIsStableAcrossRepeatedRendersOfTheSameEntries() async throws {
        let entries = syntheticEntries(count: 2_000)
        let sections = Set(ReportSection.allCases)

        let first = try await renderedPageCount(entries: entries, sections: sections)
        let second = try await renderedPageCount(entries: entries, sections: sections)

        #expect(first == second)
        #expect(first > 1)
    }

    private func renderedPageCount(entries: [FirestoreEntry], sections: Set<ReportSection>) async throws -> Int {
        let document = await PDFExportService.buildDocument(
            vehicle: vehicle,
            entries: entries,
            galleryPhotos: [],
            selectedSections: sections,
            includeReceipts: false
        )
        let generator = PDFGenerator(document: document)
        _ = try generator.generateData()
        return generator.totalPages
    }

    private var vehicle: Vehicle {
        Vehicle(
            id: "vehicle", userId: "user", nickname: "Test Vehicle", make: "Garage",
            model: "Test", year: 2026, currentOdometer: 12_000
        )
    }

    private func syntheticEntries(count: Int) -> [FirestoreEntry] {
        (0..<count).map { index in
            FirestoreEntry(
                id: "entry-\(index)", vehicleId: "vehicle", userId: "user",
                entryType: EntryType.allCases[index % EntryType.allCases.count],
                entryDate: Date(timeIntervalSince1970: Double(index) * 86_400),
                odometerReading: index, cost: nil, isDiy: nil, shopName: nil,
                notes: index.isMultiple(of: 3) ? "Synthetic note for entry \(index) covering routine service." : nil,
                attachmentPaths: [], isResolved: nil, details: [:], createdAt: nil, updatedAt: nil
            )
        }
    }

    private func entry(type: EntryType) -> FirestoreEntry {
        FirestoreEntry(
            id: type.rawValue,
            vehicleId: "vehicle",
            userId: "user",
            entryType: type,
            entryDate: .now,
            odometerReading: 1,
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

private enum PDFTestError: Error, Equatable {
    case failed
}
