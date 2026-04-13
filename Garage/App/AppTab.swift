import Foundation

enum AppTab: String, CaseIterable, Sendable {
    case dashboard = "Dashboard"
    case log = "Log"
    case garage = "Garage"
    case stats = "Stats"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: return "gauge.open.with.lines.needle.33percent"
        case .log: return "list.bullet.clipboard"
        case .garage: return "car.fill"
        case .stats: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
