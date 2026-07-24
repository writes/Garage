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
    // `internal`: EntryFormViewModel+EditPrefill.swift's applyExistingEntry sets these four.
    var pendingEntryID: String?
    var pendingCreatedAt: Date?
    /// Set when editing (nil for create). A form's own save() excludes it from lookups it runs
    /// itself (FuelFormView's MPG query) — see excludingEntryID.
    var editingEntryID: String?
    /// Edited entry's odometer at load time — floors validateOdometer (odometerFloor, +EditPrefill).
    var editingEntryOriginalOdometer: Int?
    /// Edited entry's original vehicleId — save() rejects a different vehicle (would silently
    /// reparent the entry + write the odometer to the wrong car).
    var editingEntryVehicleId: String?

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

    /// In edit mode, excludes the entry being edited so it never floors/ceilings itself;
    /// lastKnownOdometer becomes "max of every OTHER entry" (updatedVehicle reuses it).
    func prepare(vehicleId: String) async {
        do {
            lastKnownOdometer = try await entryService
                .fetchLatestOdometer(vehicleId: vehicleId, excludingEntryID: editingEntryID)
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

    // `internal`: applyExistingEntry (EntryFormViewModel+EditPrefill.swift) formats cost the same way.
    static func costString(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1_000_000_000 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    func validateOdometer() -> Bool {
        if let validationError = Validators.odometer(odometerReading, lastKnown: odometerFloor) {
            error = validationError
            return false
        }
        return true
    }

    func save<T: Encodable>(vehicle: Vehicle, entryType: EntryType, details: T) async -> Bool {
        guard !isSaving, let uid = validatedUID(for: vehicle) else { return false }

        let session = syncService.activateSession(uid: uid)
        isSaving = true
        defer { isSaving = false }

        do {
            let entry = try makePendingEntry(vehicle: vehicle, entryType: entryType, details: details, uid: uid)
            // Fresh, NOT the cached lastKnownOdometer: a stale cache (another device's write
            // landing between prepare() and here) could write a ghost currentOdometer matching no
            // entry. The cache stays cached only for the floor/UI hint.
            let freshOtherEntriesMax = try await entryService.fetchLatestOdometer(
                vehicleId: vehicle.id, excludingEntryID: editingEntryID
            )
            let updatedVehicle = Self.updatedVehicle(
                from: vehicle, for: entry, otherEntriesMaxOdometer: freshOtherEntriesMax
            )
            let disposition = try entryService.save(entry, updatingVehicle: updatedVehicle, session: session)
            if disposition == .entryOnlyAcceptedForHermeticStore {
                try await vehicleService.updateVehicle(updatedVehicle)
            }

            // These all rotate only after local acceptance completes.
            pendingEntryID = nil
            pendingCreatedAt = nil
            editingEntryID = nil
            editingEntryOriginalOdometer = nil
            editingEntryVehicleId = nil
            error = nil
            scheduleFirstEntryFollowUp(vehicleId: vehicle.id, entryType: entryType)
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    /// Pre-flight checks for save(): odometer validity, authentication, account ownership, and
    /// that an edit isn't being saved against a DIFFERENT vehicle than it was opened from. Sets
    /// `error` and returns nil on any failure.
    private func validatedUID(for vehicle: Vehicle) -> String? {
        guard validateOdometer(), let uid = userID() else {
            if userID() == nil { error = .auth("Not authenticated") }
            return nil
        }
        guard vehicle.userId == uid else {
            error = .auth("This vehicle belongs to a different account.")
            return nil
        }
        guard editingEntryVehicleId == nil || editingEntryVehicleId == vehicle.id else {
            error = .validation("This entry belongs to a different vehicle. Reopen it from that vehicle's log.")
            return nil
        }
        return uid
    }

    private func makePendingEntry<T: Encodable>(
        vehicle: Vehicle, entryType: EntryType, details: T, uid: String
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
            // Edit keeps the original createdAt (pendingCreatedAt) instead of resetting to "now".
            createdAt: pendingCreatedAt ?? .now,
            updatedAt: .now
        )
    }

    private func scheduleFirstEntryFollowUp(vehicleId: String, entryType: EntryType) {
        let firstEntryFollowUp = firstEntryFollowUp
        Task { @MainActor [self, firstEntryFollowUp] in
            await firstEntryFollowUp {
                await self.trackFirstEntryIfNeeded(vehicleId: vehicleId, entryType: entryType)
            }
        }
    }
}

// MARK: - Details-map encoding + first-entry analytics (kept out of the class body, cap)

private extension EntryFormViewModel {
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
