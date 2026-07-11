import Foundation
import Observation

@MainActor
@Observable
final class EntryFormViewModel {
    private let entryService: EntryService
    private let vehicleService: VehicleService
    private let userID: () -> String?
    private let analytics: any AnalyticsTracking

    var entryDate = Date.now
    var odometerReading = ""
    var cost = ""
    var isDiy = true
    var shopName = ""
    var notes = ""
    var attachmentPaths: [String] = []
    var lastKnownOdometer: Int?
    private(set) var isSaving = false
    private(set) var error: AppError?

    init(
        entryService: EntryService = .shared,
        vehicleService: VehicleService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        userID: @escaping () -> String? = {
            AppRuntime.isLocalDemoMode ? AppRuntime.demoUserId : AuthService.shared.uid
        }
    ) {
        self.entryService = entryService
        self.vehicleService = vehicleService
        self.analytics = analytics
        self.userID = userID
    }

    func prepare(vehicleId: String) async {
        do {
            lastKnownOdometer = try await entryService.fetchLatestOdometer(vehicleId: vehicleId)
        } catch {
            self.error = AppError(from: error)
        }
    }

    func validateOdometer() -> Bool {
        if let validationError = Validators.odometer(odometerReading, lastKnown: lastKnownOdometer) {
            error = validationError
            return false
        }
        return true
    }

    func save<T: Encodable>(
        vehicle: Vehicle,
        entryType: EntryType,
        details: T
    ) async -> Bool {
        guard validateOdometer(), let uid = userID() else {
            if userID() == nil {
                error = .auth("Not authenticated")
            }
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let detailsMap = try Self.makeAnyCodableMap(from: details)
            let entry = FirestoreEntry(
                id: UUID().uuidString,
                vehicleId: vehicle.id,
                userId: uid,
                entryType: entryType,
                entryDate: entryDate,
                odometerReading: Int(odometerReading) ?? 0,
                cost: Double(cost),
                isDiy: isDiy,
                shopName: isDiy ? nil : shopName.trimmed,
                notes: notes.trimmed.isEmpty ? nil : notes.trimmed,
                attachmentPaths: attachmentPaths,
                isResolved: nil,
                details: detailsMap,
                createdAt: .now,
                updatedAt: .now
            )
            try await entryService.save(entry)

            var updatedVehicle = vehicle
            updatedVehicle.currentOdometer = entry.odometerReading
            updatedVehicle.updatedAt = .now
            try await vehicleService.updateVehicle(updatedVehicle)

            await trackFirstEntryIfNeeded(vehicleId: vehicle.id, entryType: entryType)

            error = nil
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    private static func makeAnyCodableMap<T: Encodable>(from value: T) throws -> [String: AnyCodable] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.mapValues(Self.wrap(any:))
    }

    private func trackFirstEntryIfNeeded(vehicleId: String, entryType: EntryType) async {
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

    private static func wrap(any: Any) -> AnyCodable {
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
