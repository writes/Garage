import Foundation

struct MaintenanceEntry: Codable, Sendable, Equatable {
    var item: MaintenanceItemKind
    var otherLabel: String?
    var nextDueMileage: Int?
    var nextDueDate: Date?
    var symptomDescription: String?
    var resolutionDescription: String?
    var status: ServiceStatus
}

enum MaintenanceItemKind: String, Codable, CaseIterable, Sendable {
    case airFilter = "air_filter"
    case cabinAirFilter = "cabin_air_filter"
    case fuelSystemService = "fuel_system_service"
    case rotateBalanceTires = "rotate_balance_tires"
    case sparkPlugs = "spark_plugs"
    case transmissionService = "transmission_service"
    case differentialService = "differential_service"
    case wiperBlades = "wiper_blades"
    case batteryReplaced = "battery_replaced"
    case radiatorCoolingSystem = "radiator_cooling_system"
    case beltsAndHoses = "belts_and_hoses"
    case brakeFluidFlush = "brake_fluid_flush"
    case coolantFlush = "coolant_flush"
    case other
}

enum ServiceStatus: String, Codable, CaseIterable, Sendable {
    case unresolved
    case inProgress = "in_progress"
    case resolved
}
