import Foundation

/// One neighbouring entry on a vehicle's timeline, and the reading it recorded. Carried into the
/// rejection message so "conflicts" points at a record the owner can go and look at, rather than
/// at a bare number with no provenance.
struct OdometerBoundary: Equatable, Sendable {
    let reading: Int
    let entryDate: Date
}

/// The legal range for an odometer reading AT A GIVEN DATE — not "at least the highest number this
/// vehicle has ever shown".
///
/// The old floor was the maximum reading across every entry regardless of date, which made
/// backfilling history impossible: a receipt from two years ago is legitimately below today's
/// reading, and the form hard-rejected it (and the receipt path went further, substituting the
/// inflated floor for the mileage actually printed on the receipt). Only a genuine timeline
/// contradiction is an error — a reading below an EARLIER-dated entry's, or above a LATER-dated
/// one's. "Below today's maximum but consistent for its own date" is legal, and not even unusual.
struct OdometerBounds: Equatable, Sendable {
    /// Highest reading among entries dated at or before the chosen date. A reading below this
    /// claims the car un-drove itself.
    var earlier: OdometerBoundary?
    /// Lowest reading among entries dated after the chosen date. A reading above this claims the
    /// car drove further by that date than it had by a later one.
    var later: OdometerBoundary?
}

enum Validators {
    static func nonEmpty(_ value: String, fieldName: String) -> AppError? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .validation("\(fieldName) is required.")
            : nil
    }

    static func positiveInteger(_ value: String, fieldName: String) -> AppError? {
        guard let number = Int(value), number > 0 else {
            return .validation("\(fieldName) must be greater than zero.")
        }
        return nil
    }

    /// Rejects only what the vehicle's own history contradicts. Both bounds are optional and are
    /// independently absent when there is no entry on that side of the chosen date, which is the
    /// common case for the first entries a vehicle ever gets.
    static func odometer(_ value: String, bounds: OdometerBounds) -> AppError? {
        if let error = positiveInteger(value, fieldName: "Odometer") {
            return error
        }

        guard let number = Int(value) else {
            return .validation("Odometer must be a whole number.")
        }

        if let earlier = bounds.earlier, number < earlier.reading {
            return conflict(with: earlier)
        }
        if let later = bounds.later, number > later.reading {
            return conflict(with: later)
        }

        return nil
    }

    /// Names the conflicting entry rather than restating a limit. "Odometer must be at least
    /// 92,000" left the owner with no way to tell WHICH record disagreed with the one being typed,
    /// which is exactly the information needed to decide whether the new entry or the old one is
    /// the mistake.
    private static func conflict(with boundary: OdometerBoundary) -> AppError {
        // Formatters.shortDate is the app's one date presentation (medium style, "Mar 3, 2024" in
        // en_US) — the same rendering the owner sees on the entry row this points at.
        let date = Formatters.shortDate.string(from: boundary.entryDate)
        return .validation("Odometer conflicts with the \(boundary.reading.formatted()) mi entry on \(date).")
    }
}
