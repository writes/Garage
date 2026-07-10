import Foundation

@MainActor
final class CSVExportService {
    static let shared = CSVExportService()

    private init() {}

    func export(entries: [FirestoreEntry]) -> Data {
        let header = "id,type,date,odometer,cost,isDIY,shopName,notes,attachments,details\r\n"
        let rows = entries.map {
            [
                $0.id,
                $0.entryType.rawValue,
                $0.entryDate.ISO8601Format(),
                String($0.odometerReading),
                String($0.cost ?? 0),
                String($0.isDiy ?? false),
                Self.safeFreeText($0.shopName ?? ""),
                Self.safeFreeText($0.notes ?? ""),
                $0.attachmentPaths.joined(separator: "|"),
                Self.safeFreeText(Self.detailsText($0.details))
            ].map(Self.escapedField).joined(separator: ",")
        }
        return Data((header + rows.joined(separator: "\r\n")).utf8)
    }

    static func safeFreeText(_ value: String) -> String {
        guard let first = value.first, "=+-@".contains(first) else { return value }
        return "'" + value
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
