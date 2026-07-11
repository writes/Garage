import Foundation

@MainActor
final class CSVExportService {
    static let shared = CSVExportService()

    private init() {}

    func export(entries: [FirestoreEntry]) -> Data {
        var data = Data(Self.rawSchemaHeader.utf8)
        Self.append(entries, to: &data)
        return data
    }

    func makeRawExportWriter(at url: URL) throws -> RawExportWriter {
        try RawExportWriter(url: url)
    }

    @MainActor
    final class RawExportWriter {
        private let handle: FileHandle
        private var isClosed = false

        init(url: URL) throws {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: Data(CSVExportService.rawSchemaHeader.utf8))
        }

        func append(entries: [FirestoreEntry]) throws {
            guard !isClosed else { return }
            var pageData = Data()
            CSVExportService.append(entries, to: &pageData)
            try handle.write(contentsOf: pageData)
        }

        func finish() throws {
            guard !isClosed else { return }
            try handle.close()
            isClosed = true
        }

        func cancel() {
            guard !isClosed else { return }
            try? handle.close()
            isClosed = true
        }
    }

    private static let rawSchemaHeader = [
        "schema_version",
        "id",
        "vehicleId",
        "userId",
        "entryType",
        "entryDate",
        "odometerReading",
        "cost",
        "isDiy",
        "shopName",
        "notes",
        "attachmentPaths",
        "isResolved",
        "details",
        "createdAt",
        "updatedAt"
    ].joined(separator: ",") + "\r\n"

    private static func append(_ entries: [FirestoreEntry], to data: inout Data) {
        for entry in entries {
            data.append(contentsOf: row(for: entry).utf8)
            data.append(contentsOf: "\r\n".utf8)
        }
    }

    private static func row(for entry: FirestoreEntry) -> String {
        let cost = entry.cost.map { String($0) } ?? ""
        let isDiy = entry.isDiy.map { String($0) } ?? ""
        let attachmentPaths = entry.attachmentPaths.map(safeFreeText).joined(separator: "|")
        let isResolved = entry.isResolved.map { String($0) } ?? ""
        let details = safeFreeText(detailsText(entry.details))
        let values: [String] = [
            "2",
            entry.id,
            entry.vehicleId,
            entry.userId,
            entry.entryType.rawValue,
            entry.entryDate.ISO8601Format(),
            String(entry.odometerReading),
            cost,
            isDiy,
            safeFreeText(entry.shopName ?? ""),
            safeFreeText(entry.notes ?? ""),
            attachmentPaths,
            isResolved,
            details,
            entry.createdAt?.ISO8601Format() ?? "",
            entry.updatedAt?.ISO8601Format() ?? ""
        ]
        return values.map(escapedField).joined(separator: ",")
    }

    static func safeFreeText(_ value: String) -> String {
        let leadingCharacters = value.prefix(while: Self.isLeadingWhitespaceOrControl)
        let firstMeaningfulCharacter = value.dropFirst(leadingCharacters.count).first
        let containsSpreadsheetControlPrefix = leadingCharacters.contains { "\t\r\n".contains($0) }

        guard containsSpreadsheetControlPrefix
                || (firstMeaningfulCharacter.map { "=+-@".contains($0) } ?? false)
        else { return value }
        return "'" + value
    }

    private static func isLeadingWhitespaceOrControl(_ character: Character) -> Bool {
        character.isWhitespace || character.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains)
    }

    private static func escapedField(_ value: String) -> String {
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: ",\"\r\n")) != nil else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func detailsText(_ details: [String: AnyCodable]) -> String {
        guard let data = try? JSONEncoder().encode(details), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
