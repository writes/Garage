import Foundation

@MainActor
final class CSVExportService {
    static let shared = CSVExportService()

    private init() {}

    func export(entries: [FirestoreEntry]) -> Data {
        let header = "id,type,date,odometer,cost,isDIY,shopName,notes,attachments,details\n"
        let rows = entries.map {
            [
                $0.id,
                $0.entryType.rawValue,
                $0.entryDate.ISO8601Format(),
                String($0.odometerReading),
                String($0.cost ?? 0),
                String($0.isDiy ?? false),
                ($0.shopName ?? "").replacingOccurrences(of: ",", with: " "),
                ($0.notes ?? "").replacingOccurrences(of: ",", with: " "),
                $0.attachmentPaths.joined(separator: "|"),
                String(describing: $0.details).replacingOccurrences(of: ",", with: ";")
            ].joined(separator: ",")
        }
        return Data((header + rows.joined(separator: "\n")).utf8)
    }
}
