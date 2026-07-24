import Foundation
import Observation

@MainActor
@Observable
final class EntryFormViewModel {
    typealias FirstEntryFollowUp = @MainActor @Sendable (
        @MainActor @Sendable () async -> Void
    ) async -> Void

    // `internal`: EntryFormViewModel+DetailsEncoding.swift's trackFirstEntryIfNeeded and
    // +Attachments.swift's upload methods use these three (same split-file precedent as
    // pendingEntryID etc. below).
    let entryService: EntryService
    let vehicleService: VehicleService
    let analytics: any AnalyticsTracking
    let entryAttachmentService: EntryAttachmentService
    private let syncService: SyncService
    private let userID: () -> String?
    private let firstEntryFollowUp: FirstEntryFollowUp

    var syncServiceIdentity: ObjectIdentifier { ObjectIdentifier(syncService) }

    var entryDate = Date.now
    var odometerReading = ""
    var cost = ""
    var isDiy = true
    var shopName = ""
    var notes = ""
    var attachmentPaths: [String] = []
    // `internal`: EntryFormViewModel+Attachments.swift's methods and AttachmentPicker (a plain
    // reader, standard internal access) use these three.
    var pendingAttachments: [PendingAttachment] = []
    var queuedAttachmentRemovals: [String] = []
    var uploadingAttachmentID: PendingAttachment.ID?
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
        entryAttachmentService: EntryAttachmentService = .shared,
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
        self.entryAttachmentService = entryAttachmentService
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

        let entryID = pendingEntryID ?? UUID().uuidString
        pendingEntryID = entryID

        do {
            // Uploads FIRST (review-mandated ordering): a failure here aborts before the entry
            // doc/vehicle patch are touched, so nothing is ever half-written. Already-uploaded
            // removals are the mirror image — deferred until AFTER the write succeeds, below.
            try await uploadPendingAttachments(uid: uid, vehicleId: vehicle.id, entryId: entryID)

            let entry = try makePendingEntry(
                entryID: entryID, vehicle: vehicle, entryType: entryType, details: details, uid: uid
            )
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
            await applyQueuedAttachmentRemovals()

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
        entryID: String, vehicle: Vehicle, entryType: EntryType, details: T, uid: String
    ) throws -> FirestoreEntry {
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
