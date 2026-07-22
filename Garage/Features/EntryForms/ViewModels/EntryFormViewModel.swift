import Foundation
import Observation

@MainActor
@Observable
final class EntryFormViewModel {
    typealias FirstEntryFollowUp = @MainActor @Sendable (
        @MainActor @Sendable () async -> Void
    ) async -> Void

    private let entryService: EntryService
    private let vehicleService: VehicleService
    private let syncService: SyncService
    private let userID: () -> String?
    private let analytics: any AnalyticsTracking
    private let firstEntryFollowUp: FirstEntryFollowUp

    var syncServiceIdentity: ObjectIdentifier { ObjectIdentifier(syncService) }

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
    private var pendingEntryID: String?

    init(
        entryService: EntryService = .shared,
        vehicleService: VehicleService = .shared,
        syncService: SyncService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        firstEntryFollowUp: @escaping FirstEntryFollowUp = { operation in
            await operation()
        },
        userID: @escaping () -> String? = {
            AppRuntime.isLocalDemoMode ? AppRuntime.demoUserId : AuthService.shared.uid
        }
    ) {
        self.entryService = entryService
        self.vehicleService = vehicleService
        self.syncService = syncService
        self.analytics = analytics
        self.firstEntryFollowUp = firstEntryFollowUp
        self.userID = userID
    }

    func prepare(vehicleId: String) async {
        do {
            lastKnownOdometer = try await entryService.fetchLatestOdometer(vehicleId: vehicleId)
        } catch {
            self.error = AppError(from: error)
        }
    }

    /// Seeds the shared fields from a voice proposal. The user reviews every value before saving,
    /// so this only prefills — it never commits. Type-specific details are left for the form.
    func applyVoicePrefill(_ proposal: VoiceEntryProposal) {
        entryDate = proposal.resolvedDate(default: entryDate)
        if let odometer = proposal.odometerReading, odometer > 0 {
            odometerReading = String(odometer)
        }
        if let spokenCost = proposal.cost, spokenCost > 0 {
            cost = Self.costString(spokenCost)
        }
        if let shop = proposal.shopName?.trimmed, !shop.isEmpty {
            shopName = shop
            isDiy = false
        } else if let spokenIsDiy = proposal.isDiy {
            isDiy = spokenIsDiy
        }
        if let spokenNotes = proposal.notes?.trimmed, !spokenNotes.isEmpty {
            notes = spokenNotes
        }
    }

    private static func costString(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1_000_000_000 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
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
        guard !isSaving else { return false }
        guard validateOdometer(), let uid = userID() else {
            if userID() == nil { error = .auth("Not authenticated") }
            return false
        }
        guard vehicle.userId == uid else {
            error = .auth("This vehicle belongs to a different account.")
            return false
        }

        let session = syncService.activateSession(uid: uid)
        isSaving = true
        defer { isSaving = false }

        do {
            let entry = try makePendingEntry(vehicle: vehicle, entryType: entryType, details: details, uid: uid)
            let updatedVehicle = Self.updatedVehicle(from: vehicle, for: entry)
            let disposition = try entryService.save(
                entry,
                updatingVehicle: updatedVehicle,
                session: session
            )
            if disposition == .entryOnlyAcceptedForHermeticStore {
                try await vehicleService.updateVehicle(updatedVehicle)
            }

            // The ID rotates only after the local acceptance path has completed.
            pendingEntryID = nil
            error = nil
            scheduleFirstEntryFollowUp(vehicleId: vehicle.id, entryType: entryType)
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    private func makePendingEntry<T: Encodable>(
        vehicle: Vehicle,
        entryType: EntryType,
        details: T,
        uid: String
    ) throws -> FirestoreEntry {
        let entryID = pendingEntryID ?? UUID().uuidString
        pendingEntryID = entryID
        let detailsMap = try Self.makeAnyCodableMap(from: details)
        return FirestoreEntry(
            id: entryID,
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
    }

    private static func updatedVehicle(from vehicle: Vehicle, for entry: FirestoreEntry) -> Vehicle {
        var updatedVehicle = vehicle
        updatedVehicle.currentOdometer = entry.odometerReading
        updatedVehicle.updatedAt = .now
        return updatedVehicle
    }

    private func scheduleFirstEntryFollowUp(vehicleId: String, entryType: EntryType) {
        let firstEntryFollowUp = firstEntryFollowUp
        Task { @MainActor [self, firstEntryFollowUp] in
            await firstEntryFollowUp {
                await self.trackFirstEntryIfNeeded(vehicleId: vehicleId, entryType: entryType)
            }
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
