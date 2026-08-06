import Foundation

/// How long ago the tires currently on the car went on.
///
/// Rubber has a shelf life independent of tread. A set with 6/32 left and eight summers on it is
/// hardening, cracking between the blocks, and losing wet grip long before the wear bars say so —
/// and the wear percentage on the Dashboard, which is the only tire signal the app has ever shown,
/// says nothing about it. The install date has been sitting in the entry log the whole time.
///
/// ## Silence is the conservative direction
///
/// The advisor reads the LATEST `.newInstall`, which can only ever UNDERSTATE age: if the rears
/// were replaced last year and the fronts six years ago, the latest install is one year old and
/// this says nothing. That is the right failure — the app has no reliable per-axle scoping for an
/// install record, and a false "your tires are old" on a set fitted last spring is how an owner
/// learns to ignore the Dashboard.
///
/// Pure and dependency-free so every rule is testable without Firestore or a view.
enum TireAgeAdvisor {
    /// Five years is the point at which manufacturer and NHTSA guidance shifts from "inspect on
    /// wear" to "inspect on age", and it is the earliest figure any of them use. Below it there is
    /// nothing to say, and saying it anyway would put a permanent caption on every tire row.
    static let agingThresholdYears = 5.0

    /// The Gregorian mean year — the same 365.25 the rest of the app's month arithmetic uses, and
    /// exact enough for a figure printed to one decimal place.
    private static let secondsPerYear: TimeInterval = 365.25 * 24 * 60 * 60

    /// Years since the most recent tire installation, or nil when there is nothing worth saying:
    /// no `.newInstall` on record, a set younger than `agingThresholdYears`, or an install dated in
    /// the future (a typo'd entry date must not print a negative age).
    static func yearsSinceNewInstall(entries: [FirestoreEntry], now: Date) -> Double? {
        let installs = entries.filter(Self.isNewInstall).map(\.entryDate)
        guard let latest = installs.max() else { return nil }
        let years = now.timeIntervalSince(latest) / Self.secondsPerYear
        guard years >= Self.agingThresholdYears else { return nil }
        return years
    }

    /// FAILS CLOSED, unlike `MaintenanceAdvisor`'s rotation check. An unreadable tire entry is no
    /// evidence that a new set went on, and treating it as one would date every owner's rubber from
    /// whatever tire record happened to be undecodable.
    private static func isNewInstall(_ entry: FirestoreEntry) -> Bool {
        guard entry.entryType == .tire else { return false }
        return entry.decodedDetails(as: TireActionProbe.self)?.actionType == .newInstall
    }
}
