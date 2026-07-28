import Foundation

/// A small curated dataset of common service intervals, and the rule for deciding what a vehicle
/// is due for.
///
/// The app has been a logbook: it records what the owner already knew they did. This is the first
/// thing that tells them something they did not already know — which is the difference between
/// storage and an assistant, and the reason to open an app that is otherwise used four times a
/// year.
///
/// ## Two deliberate limits, both about honesty
///
/// **Only items with a clean entry-type mapping are tracked.** Spark plugs, coolant, cabin filter
/// and transmission fluid all have well-known intervals, but nothing in the schema records them
/// distinctly — they land in `.maintenance` alongside everything else, and inferring them from
/// free-text notes would produce confident guesses that are frequently wrong. Four items that
/// resolve accurately beat ten where six silently never clear.
///
/// **The intervals are generic and stated as such.** Manufacturer intervals vary by engine, oil
/// spec and duty cycle; a synthetic-oil car may legitimately go twice as far as the figure here.
/// Where a range exists this takes the SHORT end, because the failure modes are not symmetric:
/// nagging someone early costs them an unnecessary check, while telling them late can cost an
/// engine. Every surface that shows this must say the owner's manual wins.
enum MaintenanceItem: String, CaseIterable, Sendable, Equatable {
    case oilAndFilter
    case tireRotation
    case brakeInspection
    case wheelAlignment

    var label: String {
        switch self {
        case .oilAndFilter: return "Oil & filter"
        case .tireRotation: return "Tire rotation"
        case .brakeInspection: return "Brake inspection"
        case .wheelAlignment: return "Wheel alignment"
        }
    }

    /// The entry type that clears this item. One-to-one on purpose — see the note above.
    var clearedBy: EntryType {
        switch self {
        case .oilAndFilter: return .oilChange
        case .tireRotation: return .tire
        case .brakeInspection: return .brake
        case .wheelAlignment: return .alignment
        }
    }

    var intervalMiles: Int {
        switch self {
        case .oilAndFilter: return 5_000
        case .tireRotation: return 6_000
        case .brakeInspection, .wheelAlignment: return 12_000
        }
    }

    var intervalMonths: Int {
        switch self {
        case .oilAndFilter, .tireRotation: return 6
        case .brakeInspection, .wheelAlignment: return 12
        }
    }
}

enum MaintenanceStatus: String, Sendable, Equatable {
    /// Past the interval on mileage, on time, or both.
    case overdue
    /// Inside the last 10% of the interval — close enough to plan around, not yet late.
    case dueSoon
    case upToDate
    /// Never logged, so there is no baseline. Explicitly NOT "overdue": a car whose oil was
    /// changed last week by a previous owner is not overdue, and the app has no way to know.
    case neverLogged
}

struct MaintenanceDue: Identifiable, Sendable, Equatable {
    let item: MaintenanceItem
    let status: MaintenanceStatus
    /// Positive when past due, negative when still remaining. Nil when there is no odometer
    /// baseline to measure from.
    let milesPastDue: Int?
    let dueDate: Date?
    let lastServicedAt: Date?

    var id: String { item.rawValue }
}

enum MaintenanceAdvisor {
    /// Warn inside the last tenth of an interval. Chosen over a fixed 500-mile window so the
    /// warning scales with the item: a tenth of an oil change is 500 miles, a tenth of an
    /// alignment is 1,200, and both read as "coming up" rather than "act now".
    static let dueSoonFraction = 0.1

    static func status(
        for item: MaintenanceItem,
        entries: [FirestoreEntry],
        currentOdometer: Int?,
        now: Date
    ) -> MaintenanceDue {
        let matching = entries
            .filter { $0.entryType == item.clearedBy }
            .sorted { $0.entryDate > $1.entryDate }

        guard let last = matching.first else {
            return MaintenanceDue(
                item: item, status: .neverLogged, milesPastDue: nil,
                dueDate: nil, lastServicedAt: nil
            )
        }

        let dueDate = Calendar.current.date(
            byAdding: .month, value: item.intervalMonths, to: last.entryDate
        )
        // A zero odometer means "not recorded", not "mile zero" — measuring from it would report
        // every car as tens of thousands of miles overdue.
        let milesPastDue: Int? = {
            guard let currentOdometer, currentOdometer > 0, last.odometerReading > 0 else { return nil }
            return (currentOdometer - last.odometerReading) - item.intervalMiles
        }()

        return MaintenanceDue(
            item: item,
            status: resolve(milesPastDue: milesPastDue, dueDate: dueDate, item: item, now: now),
            milesPastDue: milesPastDue,
            dueDate: dueDate,
            lastServicedAt: last.entryDate
        )
    }

    /// Either axis alone is enough to be due — that is what "5,000 miles OR 6 months" means, and
    /// requiring both would let a car that sits all year go indefinitely without an oil change.
    private static func resolve(
        milesPastDue: Int?, dueDate: Date?, item: MaintenanceItem, now: Date
    ) -> MaintenanceStatus {
        let overdueOnMiles = (milesPastDue ?? Int.min) >= 0
        let overdueOnTime = dueDate.map { $0 <= now } ?? false
        if overdueOnMiles || overdueOnTime { return .overdue }

        let warningMiles = Int(Double(item.intervalMiles) * dueSoonFraction)
        let soonOnMiles = milesPastDue.map { $0 >= -warningMiles } ?? false
        let soonOnTime = dueDate.map {
            let warning = Double(item.intervalMonths) * dueSoonFraction * 30.44 * 24 * 60 * 60
            return $0.timeIntervalSince(now) <= warning
        } ?? false
        return soonOnMiles || soonOnTime ? .dueSoon : .upToDate
    }

    /// Everything that wants attention, worst first. `ok` items are dropped — a list of things
    /// that are fine is noise on a screen whose job is to say what needs doing.
    static func attentionNeeded(
        entries: [FirestoreEntry], currentOdometer: Int?, now: Date
    ) -> [MaintenanceDue] {
        MaintenanceItem.allCases
            .map { status(for: $0, entries: entries, currentOdometer: currentOdometer, now: now) }
            .filter { $0.status != .upToDate }
            .sorted { lhs, rhs in
                let left = rank(lhs.status), right = rank(rhs.status)
                if left != right { return left < right }
                // Total order: without this tiebreak, two overdue items could swap between
                // renders, since Swift's sort is not stable.
                return lhs.item.rawValue < rhs.item.rawValue
            }
    }

    private static func rank(_ status: MaintenanceStatus) -> Int {
        switch status {
        case .overdue: return 0
        case .dueSoon: return 1
        case .neverLogged: return 2
        case .upToDate: return 3
        }
    }
}
