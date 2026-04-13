import Foundation

struct Reminder: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var vehicleId: String
    var title: String
    var entryType: EntryType?
    var dueDate: Date?
    var dueMileage: Int?
    var repeatIntervalMonths: Int?
    var repeatIntervalMiles: Int?
    var notes: String?
    var isProFeature: Bool = false
    var createdAt: Date?
}
