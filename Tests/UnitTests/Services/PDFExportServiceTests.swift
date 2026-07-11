import Foundation
import Testing
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
