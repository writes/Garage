import Foundation
import Testing
@testable import Garage

@MainActor
struct ExportViewModelTests {
    @Test func initialState_hasNoExportData() {
        let viewModel = ExportViewModel()

        #expect(viewModel.exportData == nil)
        #expect(viewModel.error == nil)
    }

    @Test func buildCSV_exportsAllPagesAndEntireHistory() async throws {
        let entries = csvEntries()
        let entryService = EntryService(testEntries: Array(entries.reversed()))
        let viewModel = ExportViewModel(entryService: entryService)

        await viewModel.buildCSV(vehicle: vehicle)

        #expect(viewModel.error == nil)
        guard let url = viewModel.csvExportURL else {
            Issue.record("Expected a retrievable CSV export URL")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let csv = try String(contentsOf: url, encoding: .utf8)
        let rows = csv.components(separatedBy: "\r\n").filter(\.isNotEmpty)
        let ids = rows.dropFirst().map { $0.components(separatedBy: ",")[1] }
        let expectedIDs = entries
            .sorted {
                if $0.entryDate != $1.entryDate {
                    return $0.entryDate > $1.entryDate
                }
                return $0.id < $1.id
            }
            .map(\.id)

        #expect(url.pathExtension == "csv")
        #expect(rows.count == 1_204)
        #expect(ids.count == 1_203)
        #expect(Set(ids).count == 1_203)
        #expect(ids == expectedIDs)
        #expect(ids.contains("entry-1202"))
    }

    private var vehicle: Vehicle {
        Vehicle(
            id: "vehicle",
            userId: "user",
            nickname: "Test Vehicle",
            make: "Garage",
            model: "Test",
            year: 2026,
            currentOdometer: 0
        )
    }

    private func csvEntries() -> [FirestoreEntry] {
        let now = Date.now.timeIntervalSince1970
        return (0..<1_203).map { index in
            FirestoreEntry(
                id: String(format: "entry-%04d", index),
                vehicleId: "vehicle",
                userId: "user",
                entryType: .maintenance,
                entryDate: Date(timeIntervalSince1970: csvDate(for: index, now: now)),
                odometerReading: index,
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

    private func csvDate(for index: Int, now: TimeInterval) -> TimeInterval {
        if (495...505).contains(index) {
            return now - 495
        }
        if (995...1_005).contains(index) {
            return now - 995
        }
        if index == 1_202 {
            return now - 63_072_000
        }
        return now - Double(index)
    }
}
