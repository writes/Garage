import Foundation

enum ReportSection: String, CaseIterable, Codable, Sendable, Identifiable {
    case vehicleInfo = "Vehicle info & specs"
    case photoGallery = "Photo gallery"
    case maintenanceHistory = "Maintenance history"
    case oilHistory = "Oil changes & analysis"
    case trackDays = "Track day log"
    case tireHistory = "Tire history"
    case brakeHistory = "Brake history"
    case alignmentRecords = "Alignment records"
    case upgrades = "Upgrade / modification log"
    case detailing = "Detailing history"
    case spareParts = "Spare parts on hand"
    case wearSummary = "Wear item summary"
    case costSummary = "Cost summary"
    case receipts = "Receipts & invoices"
    case warranties = "Warranty information"
    case recalls = "Recall history"
    case vehicleHistoryPlaceholder = "Vehicle history placeholder"

    var id: String { rawValue }
}
