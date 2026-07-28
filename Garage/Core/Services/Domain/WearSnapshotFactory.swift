import Foundation

/// Turns a brake or tire entry into the wear snapshots the Dashboard reads.
///
/// This closes a pipeline that was open at both ends: `WearService.saveSnapshots` existed with
/// zero callers, and both forms hardcoded every wear field to `nil`, so the Dashboard wear section
/// and `WearHistoryChart` were permanently empty for every real user. They looked populated only
/// in demo mode, where `WearService.fetchDashboard` returns `SeedData` instead of reading
/// Firestore — which is why screenshots and manual walkthroughs never caught it.
///
/// Pure and `nonisolated` so the mapping — including the tread-depth scale below, which is a real
/// domain judgement — is testable without Firestore, a form, or a main actor.
enum WearSnapshotFactory {
    /// Tread depth is measured in 32nds of an inch. A new passenger tire is about 10/32"; 2/32" is
    /// the legal minimum in most US states and the point where the wear bars are flush. Percentage
    /// remaining is therefore measured against the *usable* range (10 → 2), not against zero:
    /// reporting a tire at the legal limit as "20% left" would be actively dangerous advice.
    static let newTreadDepth32nds = 10.0
    static let minimumLegalTreadDepth32nds = 2.0

    static func treadPercentage(from reading: String) -> Double? {
        guard let depth = parseTread32nds(reading) else { return nil }
        let usable = newTreadDepth32nds - minimumLegalTreadDepth32nds
        let remaining = (depth - minimumLegalTreadDepth32nds) / usable * 100
        return min(100, max(0, remaining))
    }

    /// No passenger tire is three inches deep. The bound is a sanity filter, not a measurement
    /// rule — its real job is keeping absurd input out of the arithmetic below.
    static let maximumPlausibleTread32nds = 100.0

    /// Accepts "6", "6/32", or "6.5" — all three are how people write tread depth. The denominator
    /// is ignored rather than honoured because "6/32" and "6" mean the same thing to the user, and
    /// silently reinterpreting a stray "6/16" as a different depth would be worse than treating
    /// the numerator as the reading.
    ///
    /// The `isFinite` and upper-bound guards are load-bearing, not defensive dressing. `Double`
    /// parses "1e400" as `+infinity`, and `infinity >= 0` is `true`, so a bare non-negative check
    /// passed it straight through to `Int(_:)` — which TRAPS, crashing the app. A plain 25-digit
    /// number reaches the same trap by exceeding `Int64`, and the decimal keypad can produce one
    /// by itself. Rejecting here means every value downstream is finite and small.
    static func parseTread32nds(_ reading: String) -> Double? {
        let head = reading.split(separator: "/").first.map(String.init) ?? reading
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed),
              value.isFinite,
              value >= 0,
              value <= maximumPlausibleTread32nds else { return nil }
        return value
    }

    /// Deterministic, so re-saving an edited entry OVERWRITES its snapshot instead of adding a
    /// second one. `WearService.saveSnapshots` writes with `setData` at `snapshot.id`, so a fresh
    /// UUID per save meant every edit appended another document: unbounded growth, and two
    /// snapshots sharing one `recordedAt` where the dashboard's "latest wins" tiebreak could hand
    /// the display back to the value the user had just corrected.
    static func snapshotID(entryID: String, item: WearItemType) -> String {
        "\(entryID)-\(item.rawValue)"
    }

    /// The full write for one entry: what to store, and what to remove.
    ///
    /// `clearedIDs` exists because editing is not just adding. If someone records a front-pad
    /// percentage, saves, then edits the entry and empties that field, the snapshot it created
    /// must go — otherwise the dashboard keeps showing a reading the user has explicitly deleted.
    struct WearWrite: Equatable, Sendable {
        var snapshots: [WearSnapshot] = []
        var clearedIDs: [String] = []
    }

    static func write(
        from entry: BrakeEntry,
        vehicleId: String,
        entryId: String,
        odometerReading: Int,
        recordedAt: Date
    ) -> WearWrite {
        let readings: [(WearItemType, Double?)] = [
            (.frontBrakePads, entry.frontPadPct),
            (.rearBrakePads, entry.rearPadPct),
            (.frontRotors, entry.frontRotorPct),
            (.rearRotors, entry.rearRotorPct)
        ]
        return readings.reduce(into: WearWrite()) { write, reading in
            let (type, percentage) = reading
            // `isFinite` first: min/max with NaN silently returns the other operand, so a NaN
            // would otherwise be recorded as a real 0%-remaining reading.
            guard let percentage, percentage.isFinite else {
                write.clearedIDs.append(snapshotID(entryID: entryId, item: type))
                return
            }
            let clamped = min(100, max(0, percentage))
            write.snapshots.append(WearSnapshot(
                id: snapshotID(entryID: entryId, item: type),
                vehicleId: vehicleId,
                entryId: entryId,
                wearItem: type,
                valuePct: clamped,
                valueRaw: "\(Int(clamped.rounded()))%",
                odometerReading: odometerReading,
                recordedAt: recordedAt,
                createdAt: recordedAt
            ))
        }
    }

    /// Front and rear each collapse two corner readings into one bar, because that is the
    /// granularity the Dashboard shows. The WORSE corner wins: an axle is only as good as its most
    /// worn tire, and averaging would hide a single bald corner behind a healthy one.
    static func write(
        from entry: TireEntry,
        vehicleId: String,
        entryId: String,
        odometerReading: Int,
        recordedAt: Date
    ) -> WearWrite {
        let axles: [(WearItemType, [String?])] = [
            (.frontTires, [entry.treadDepthFL, entry.treadDepthFR]),
            (.rearTires, [entry.treadDepthRL, entry.treadDepthRR])
        ]
        return axles.reduce(into: WearWrite()) { write, axle in
            let (type, readings) = axle
            let parsed = readings.compactMap { $0 }.compactMap { reading -> (Double, String)? in
                guard let depth = parseTread32nds(reading),
                      let percentage = treadPercentage(from: reading) else { return nil }
                return (percentage, "\(formatted(depth))/32")
            }
            guard let worst = parsed.min(by: { $0.0 < $1.0 }) else {
                write.clearedIDs.append(snapshotID(entryID: entryId, item: type))
                return
            }
            write.snapshots.append(WearSnapshot(
                id: snapshotID(entryID: entryId, item: type),
                vehicleId: vehicleId,
                entryId: entryId,
                wearItem: type,
                valuePct: worst.0,
                valueRaw: worst.1,
                odometerReading: odometerReading,
                recordedAt: recordedAt,
                createdAt: recordedAt
            ))
        }
    }

    /// `parseTread32nds` has already rejected anything non-finite or above
    /// `maximumPlausibleTread32nds`, so `Int(_:)` here cannot trap. That guarantee lives at the
    /// parse boundary on purpose — it is the only place raw user text enters this type.
    private static func formatted(_ depth: Double) -> String {
        depth == depth.rounded() ? String(Int(depth)) : String(format: "%.1f", depth)
    }
}
