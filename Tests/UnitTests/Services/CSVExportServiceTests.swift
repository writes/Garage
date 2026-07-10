import Foundation
import Testing
@testable import Garage

@MainActor
struct CSVExportServiceTests {
    @Test func export_quotesCommasQuotesAndNewlinesWithoutChangingText() {
        let csv = export(
            shopName: "M\" Dealer, Inc.",
            notes: "First line\nSecond line",
            cost: 12.5
        )

        #expect(csv.hasPrefix("id,type,date,odometer,cost,isDIY,shopName,notes,attachments,details\r\n"))
        #expect(csv.contains("\"M\"\" Dealer, Inc.\""))
        #expect(csv.contains("\"First line\nSecond line\""))
    }

    @Test func export_neutralizesFormulaTextButLeavesNegativeNumbersRaw() {
        let csv = export(shopName: "=SUM(A1:A2)", notes: "+formula", cost: -42.5)

        #expect(csv.contains("'=SUM(A1:A2)"))
        #expect(csv.contains("'+formula"))
        #expect(csv.contains(",-42.5,"))
        #expect(CSVExportService.safeFreeText("-free text") == "'-free text")
        #expect(CSVExportService.safeFreeText("@free text") == "'@free text")
    }

    private func export(shopName: String, notes: String, cost: Double) -> String {
        let entry = FirestoreEntry(
            id: "entry",
            vehicleId: "vehicle",
            userId: "user",
            entryType: .fuel,
            entryDate: Date(timeIntervalSince1970: 0),
            odometerReading: 10,
            cost: cost,
            isDiy: false,
            shopName: shopName,
            notes: notes,
            attachmentPaths: [],
            isResolved: nil,
            details: ["comment": AnyCodable("preserved, detail")],
            createdAt: nil,
            updatedAt: nil
        )
        let data = CSVExportService.shared.export(entries: [entry])
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
