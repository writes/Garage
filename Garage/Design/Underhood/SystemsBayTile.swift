import Foundation

/// One Systems Bay tile — last fact + interval math only (arm manifest §2.5; UH-A facts-only).
struct SystemsBayTile: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case okay, warn, bad
    }

    let id: String
    let name: String
    let dueText: String
    let lastText: String
    /// 0…1 progress toward the interval; drives the concept's `.bar i` width.
    let progress: Double
    let status: Status
}

enum SystemsBayDeriver {
    /// Builds tiles from the same maintenance advisor the Dashboard already uses — no invented health scores.
    static func tiles(from maintenance: [MaintenanceDue]) -> [SystemsBayTile] {
        maintenance.map { due in
            SystemsBayTile(
                id: due.item.rawValue,
                name: due.item.label,
                dueText: dueLabel(for: due),
                lastText: lastLabel(for: due),
                progress: progress(for: due),
                status: status(for: due.status)
            )
        }
    }

    /// When maintenance is empty but history exists, show the four tracked systems as "no record"
    /// rather than an empty bay — the concept always surfaces the grid.
    static func placeholderTiles() -> [SystemsBayTile] {
        MaintenanceItem.allCases.map { item in
            SystemsBayTile(
                id: item.rawValue,
                name: item.label,
                dueText: "No interval set",
                lastText: "No record yet",
                progress: 0,
                status: .warn
            )
        }
    }

    private static func status(for maintenance: MaintenanceStatus) -> SystemsBayTile.Status {
        switch maintenance {
        case .overdue: return .bad
        case .dueSoon, .neverLogged: return .warn
        case .upToDate: return .okay
        }
    }

    private static func dueLabel(for due: MaintenanceDue) -> String {
        switch due.status {
        case .overdue:
            if let miles = due.milesPastDue, miles > 0 {
                return "\(miles.formatted()) mi over"
            }
            return "Past due"
        case .dueSoon:
            if let miles = due.milesPastDue, miles < 0 {
                return "Due in \(abs(miles).formatted()) mi"
            }
            return "Due soon"
        case .neverLogged:
            return "No record"
        case .upToDate:
            return "Up to date"
        }
    }

    private static func lastLabel(for due: MaintenanceDue) -> String {
        if let date = due.lastServicedAt {
            return "Last @ \(date.shortDisplay)"
        }
        return "Never logged"
    }

    /// Without mileage evidence the bar stays EMPTY — an invented 85% "mostly due" (or 20%
    /// "mostly fine") would present a number the data does not contain (cross-check finding).
    /// The tile's text row already tells the honest story for those states.
    private static func progress(for due: MaintenanceDue) -> Double {
        guard let miles = due.milesPastDue else { return 0 }
        let interval = Double(due.item.intervalMiles)
        guard interval > 0 else { return 0 }
        let traveled = Double(due.item.intervalMiles + miles)
        return min(1, max(0, traveled / interval))
    }
}
