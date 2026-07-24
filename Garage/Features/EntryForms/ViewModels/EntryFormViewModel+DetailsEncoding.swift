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
