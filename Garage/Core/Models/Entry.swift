import Foundation

enum EntryType: String, Codable, CaseIterable, Equatable, Sendable {
    case oilChange = "oil_change"
    case oilConsumption = "oil_consumption"
    case oilAnalysis = "oil_analysis"
    case fuel
    case tire
    case brake
    case alignment
    case maintenance
    case repair
    case trackDay = "track_day"
    case upgrade
    case dmeReport = "dme_report"

    var displayName: String {
        switch self {
        case .oilChange: return "Oil Change"
        case .oilConsumption: return "Oil Consumption"
        case .oilAnalysis: return "Oil Analysis"
        case .fuel: return "Fuel Fill-up"
        case .tire: return "Tire Service"
        case .brake: return "Brake Service"
        case .alignment: return "Wheel Alignment"
        case .maintenance: return "Maintenance"
        case .repair: return "Repair"
        case .trackDay: return "Track Day"
        case .upgrade: return "Upgrade"
        case .dmeReport: return "DME Report"
        }
    }

    var icon: String {
        switch self {
        case .oilChange, .oilConsumption: return "drop.fill"
        case .oilAnalysis: return "flask.fill"
        case .fuel: return "fuelpump.fill"
        case .tire: return "circle.circle"
        case .brake: return "stop.circle.fill"
        case .alignment: return "arrow.left.and.right"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .repair: return "wrench.fill"
        case .trackDay: return "flag.checkered"
        case .upgrade: return "bolt.fill"
        case .dmeReport: return "doc.text.fill"
        }
    }
}

protocol EntryProtocol: Codable, Identifiable, Sendable {
    var id: String { get }
    var vehicleId: String { get }
    var userId: String { get }
    var entryType: EntryType { get }
    var entryDate: Date { get }
    var odometerReading: Int { get }
    var cost: Double? { get }
    var isDiy: Bool? { get }
    var shopName: String? { get }
    var notes: String? { get }
    var attachmentPaths: [String] { get }
}

struct FirestoreEntry: EntryProtocol, Equatable {
    var id: String
    var vehicleId: String
    var userId: String
    var entryType: EntryType
    var entryDate: Date
    var odometerReading: Int
    var cost: Double?
    var isDiy: Bool?
    var shopName: String?
    var notes: String?
    var attachmentPaths: [String]
    var isResolved: Bool?
    var details: [String: AnyCodable]
    var createdAt: Date?
    var updatedAt: Date?
}

struct EntryQuery: Sendable, Equatable {
    var vehicleId: String
    var entryTypes: Set<EntryType> = []
    var searchText: String = ""
}
