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

        let expectedHeader = [
            "schema_version", "id", "vehicleId", "userId", "entryType", "entryDate",
            "odometerReading", "cost", "isDiy", "shopName", "notes", "attachmentPaths",
            "isResolved", "details", "createdAt", "updatedAt"
        ].joined(separator: ",") + "\r\n"

        #expect(csv.hasPrefix(expectedHeader))
        #expect(csv.contains("\"M\"\" Dealer, Inc.\""))
        #expect(csv.contains("\"First line\nSecond line\""))
    }

    @Test func export_neutralizesFormulaTextButLeavesNegativeNumbersRaw() {
        let csv = export(shopName: "=SUM(A1:A2)", notes: "+formula", cost: -12.50)

        #expect(csv.contains("'=SUM(A1:A2)"))
        #expect(csv.contains("'+formula"))
        #expect(csv.contains(",-12.5,"))
        #expect(CSVExportService.safeFreeText("-free text") == "'-free text")
        #expect(CSVExportService.safeFreeText("@free text") == "'@free text")
    }

    @Test func safeFreeText_neutralizesFormulasAfterLeadingWhitespaceOrControls() {
        #expect(CSVExportService.safeFreeText(" =cmd()") == "' =cmd()")
        #expect(CSVExportService.safeFreeText("\t=cmd()") == "'\t=cmd()")
        #expect(CSVExportService.safeFreeText("\r=cmd()") == "'\r=cmd()")
        #expect(CSVExportService.safeFreeText("\n=cmd()") == "'\n=cmd()")
    }

    @Test func export_neutralizesFormulaAttachmentPathsIndividually() {
        let csv = export(
            shopName: "Shop",
            notes: "Notes",
            cost: 12.5,
            attachmentPaths: ["=HYPERLINK(\"https://evil.example\")", "receipt.pdf"]
        )

        #expect(csv.contains("'=HYPERLINK(\"\"https://evil.example\"\")|receipt.pdf"))
    }

    @Test func export_preservesOrderedRawAttachmentPaths() {
        let firstPath = "users/user/entries/entry/receipts/first-receipt.pdf"
        let secondPath = "users/user/entries/entry/photos/second-photo.jpg"
        let csv = export(
            shopName: "Shop",
            notes: "Notes",
            cost: 12.5,
            attachmentPaths: [firstPath, secondPath]
        )

        let rows = csv.components(separatedBy: "\r\n")
        guard rows.count >= 2 else {
            Issue.record("Expected a CSV header and data row.")
            return
        }
        let header = rows[0].components(separatedBy: ",")
        let row = rows[1].components(separatedBy: ",")
        guard let attachmentPathsColumn = header.firstIndex(of: "attachmentPaths"),
              row.indices.contains(attachmentPathsColumn) else {
            Issue.record("Expected attachmentPaths column in CSV export.")
            return
        }

        #expect(row[attachmentPathsColumn] == "\(firstPath)|\(secondPath)")
    }

    @Test func export_usesV2SchemaAndPreservesNullsAsEmptyCells() {
        let entry = FirestoreEntry(
            id: "entry",
            vehicleId: "vehicle",
            userId: "user",
            entryType: .fuel,
            entryDate: Date(timeIntervalSince1970: 0),
            odometerReading: 10,
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
        let csv = String(bytes: CSVExportService.shared.export(entries: [entry]), encoding: .utf8) ?? ""
        let lines = csv.components(separatedBy: "\r\n")
        let header = lines[0].components(separatedBy: ",")
        let row = lines[1].components(separatedBy: ",")
        let values = Dictionary(uniqueKeysWithValues: zip(header, row))

        #expect(header == [
            "schema_version", "id", "vehicleId", "userId", "entryType", "entryDate",
            "odometerReading", "cost", "isDiy", "shopName", "notes", "attachmentPaths",
            "isResolved", "details", "createdAt", "updatedAt"
        ])
        #expect(values["schema_version"] == "2")
        #expect(values["cost"]?.isEmpty == true)
        #expect(values["isDiy"]?.isEmpty == true)
        #expect(values["shopName"]?.isEmpty == true)
        #expect(values["notes"]?.isEmpty == true)
        #expect(values["attachmentPaths"]?.isEmpty == true)
        #expect(values["isResolved"]?.isEmpty == true)
        #expect(values["createdAt"]?.isEmpty == true)
        #expect(values["updatedAt"]?.isEmpty == true)
        #expect(values["details"] == "{}")
    }

    private func export(
        shopName: String,
        notes: String,
        cost: Double,
        attachmentPaths: [String] = []
    ) -> String {
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
            attachmentPaths: attachmentPaths,
            isResolved: nil,
            details: ["comment": AnyCodable("preserved, detail")],
            createdAt: nil,
            updatedAt: nil
        )
        let data = CSVExportService.shared.export(entries: [entry])
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
