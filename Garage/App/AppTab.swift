import Foundation

enum AppTab: String, CaseIterable, Sendable {
    case dashboard = "Dashboard"
    case log = "Log"
    case garage = "Garage"
    case stats = "Stats"
    case settings = "Settings"
    /// Center dock action in the Underhood arm (arm manifest §2.1). Presents the entry picker —
    /// not a destination screen — so analytics maps it to `.dashboard` and selection never rests here.
    case record = "Record"
    /// Export/dossier surface in the Underhood arm (arm manifest §2.1). Control reaches the same
    /// view through Settings → Export; analytics maps here to `.settings` so the event stream matches.
    case handover = "Handover"

    var icon: String {
        switch self {
        case .dashboard: return "gauge.open.with.lines.needle.33percent"
        case .log: return "list.bullet.clipboard"
        case .garage: return "car.fill"
        case .stats: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        case .record: return "plus"
        case .handover: return "doc.richtext"
        }
    }

    /// Tabs the shipped control arm surfaces. Explicit rather than `allCases` so new Underhood-only
    /// identities cannot leak into control when the enum grows.
    static let controlTabs: [AppTab] = [.dashboard, .log, .garage, .stats, .settings]
}
