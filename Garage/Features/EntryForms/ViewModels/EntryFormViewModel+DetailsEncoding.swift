import Foundation

// Split out of EntryFormViewModel.swift to stay under the file cap (matching the
// +EditPrefill/+Attachments split precedent). `internal`, not `private`, purely because these
// are called from the main file's makePendingEntry/scheduleFirstEntryFollowUp — nothing outside
// EntryFormViewModel itself uses them.
extension EntryFormViewModel {
    static func makeAnyCodableMap<T: Encodable>(from value: T) throws -> [String: AnyCodable] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.mapValues(Self.wrap(any:))
    }

    func trackFirstEntryIfNeeded(vehicleId: String, entryType: EntryType) async {
        guard let vehicles = try? await vehicleService.fetchVehicles() else { return }
        let vehicleIDs = Set(vehicles.map(\.id)).union([vehicleId])
        var entryCount = 0

        for id in vehicleIDs {
            guard let entries = try? await entryService.fetchRecent(vehicleId: id, limit: 2) else { return }
            entryCount += entries.count
            guard entryCount <= 1 else { return }
        }

        guard entryCount == 1 else { return }
        analytics.track(.firstEntryAdded(entryType: entryType))
    }

    /// Persists wear readings taken alongside an entry that has already been accepted.
    ///
    /// Fail-soft on purpose: the entry itself is the user's record and is already saved, so a
    /// failure here must not turn a successful save into a failed one. It costs a dashboard bar,
    /// not data — and it is logged rather than swallowed.
    func recordWear(_ write: WearSnapshotFactory.WearWrite, vehicleId: String) async {
        guard !write.snapshots.isEmpty || !write.clearedIDs.isEmpty else { return }
        do {
            try await wearService(write, vehicleId)
        } catch {
            AppLogger.shared.error("Wear snapshot save failed: \(error.localizedDescription)")
        }
    }

    // `internal`: applyVoicePrefill and applyExistingEntry (+EditPrefill.swift) both format cost
    // this way. Moved here from the main file, which sits on the 250-line cap.
    // The magnitude guard is load-bearing: `Int(_:)` traps above Int64, and a cost arrives from a
    // decoded document or a spoken voice proposal, neither of which is range-checked upstream.
    static func costString(_ value: Double) -> String {
        if value == value.rounded(), value.isFinite, abs(value) < 1_000_000_000 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    static func wrap(any: Any) -> AnyCodable {
        switch any {
        case let value as String:
            return AnyCodable(value)
        case let value as Int:
            return AnyCodable(value)
        case let value as Double:
            return AnyCodable(value)
        case let value as Bool:
            return AnyCodable(value)
        case let value as [String: Any]:
            return AnyCodable(value.mapValues(wrap(any:)))
        case let value as [Any]:
            return AnyCodable(value.map(wrap(any:)))
        default:
            return AnyCodable("")
        }
    }
}
