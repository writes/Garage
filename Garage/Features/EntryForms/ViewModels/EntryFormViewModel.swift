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
    let receiptQuickAddService: any ReceiptQuickAddCalling
    // Defaults to the real store, never a no-op — see ExportViewModel for the reasoning.
    private let recordReviewMoment: @MainActor (ReviewMoment) -> Void
    private let suppressReviewPrompt: @MainActor () -> Void
    // `internal`: called by +DetailsEncoding.swift's recordWear. A closure rather than the service
    // so a hermetic test can capture the snapshots without touching Firestore.
    let wearService: @MainActor (WearSnapshotFactory.WearWrite, String) async throws -> Void
    let entryAttachmentService: EntryAttachmentService
    private let syncService: SyncService
    private let userID: () -> String?
    // `internal`: read by scheduleFirstEntryFollowUp in +DetailsEncoding.swift.
    let firstEntryFollowUp: FirstEntryFollowUp

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
    // AI-seeding flags: set by applyVoicePrefill/applyReceiptPrefill (+ReceiptPrefill.swift),
    // consumed by finishSaveTracking to close the matching funnel event. Never both true — a
    // form is seeded by at most one AI source. receiptAttachmentNeedsPro is true when a receipt
    // scan had an attachment the user was too-free-to-stage at prefill time (EntryFormScaffold
    // reads it for the upsell hint line).
    var wasVoiceSeeded = false
    var wasReceiptSeeded = false
    var receiptAttachmentNeedsPro = false
    // Receipt extensions own this transient token; it is cleared before the best-effort confirm task starts.
    var receiptConfirmationToken: String?
    var receiptPrefillRawFields: Set<ReceiptPrefillField> = []
    var receiptPrefillSeededFields: Set<ReceiptPrefillField> = []
    var receiptPrefillEffectiveSeed: ReceiptPrefillEffectiveSeed?
    /// Edited entry's odometer at load time — floors validateOdometer (odometerFloor, +EditPrefill).
    var editingEntryOriginalOdometer: Int?
    /// Edited entry's original vehicleId — save() rejects a different vehicle.
    var editingEntryVehicleId: String?

    init(
        entryService: EntryService = .shared,
        vehicleService: VehicleService = .shared,
        syncService: SyncService = .shared,
        entryAttachmentService: EntryAttachmentService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        receiptQuickAddService: any ReceiptQuickAddCalling = ReceiptQuickAddService.shared,
        recordReviewMoment: @escaping @MainActor (ReviewMoment) -> Void = {
            ReviewPromptStore.shared.record($0)
        },
        suppressReviewPrompt: @escaping @MainActor () -> Void = {
            ReviewPromptStore.shared.suppressForSession()
        },
        wearService: @escaping @MainActor (WearSnapshotFactory.WearWrite, String) async throws -> Void = {
            try WearService.shared.apply($0, vehicleId: $1)
        },
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
        self.receiptQuickAddService = receiptQuickAddService
        self.recordReviewMoment = recordReviewMoment
        self.suppressReviewPrompt = suppressReviewPrompt
        self.wearService = wearService
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

    func validateOdometer() -> Bool {
        if let validationError = Validators.odometer(odometerReading, lastKnown: odometerFloor) {
            error = validationError
            return false
        }
        return true
    }

    /// `followUp` runs INSIDE the `isSaving` window, before the scaffold is told the save
    /// succeeded. Forms that write follow-on records (wear snapshots) used to do it after `save`
    /// returned, which left the Save button live and `isSaving` false across that write — a second
    /// tap in that window passed the reentrancy guard, allocated a fresh entry id, and wrote a
    /// DUPLICATE entry. Keeping the work in here closes the window.
    func save<T: Encodable>(
        vehicle: Vehicle,
        entryType: EntryType,
        details: T,
        followUp: (_ entryID: String) async -> Void = { _ in }
    ) async -> Bool {
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
                from: vehicle, for: entry, otherEntriesMaxOdometer: freshOtherEntriesMax,
                isEditingExistingEntry: editingEntryID != nil
            )
            let disposition = try entryService.save(entry, updatingVehicle: updatedVehicle, session: session)
            if disposition == .entryOnlyAcceptedForHermeticStore {
                try await vehicleService.updateVehicle(updatedVehicle)
            }
            await applyQueuedAttachmentRemovals()

            let wasEdit = editingEntryID != nil
            // These all rotate only after local acceptance completes.
            pendingEntryID = nil
            pendingCreatedAt = nil
            editingEntryID = nil
            editingEntryOriginalOdometer = nil
            editingEntryVehicleId = nil
            error = nil
            await followUp(entryID)
            finishSaveTracking(vehicleId: vehicle.id, entryType: entryType, wasEdit: wasEdit)
            recordReviewMoment(.entryLogged)
            return true
        } catch {
            self.error = AppError(from: error)
            // A save that failed is the worst possible moment to ask for a rating, and the user is
            // likely to hit a value moment (a retry that works) minutes later — so the whole
            // session is taken off the table, not just this call.
            suppressReviewPrompt()
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

}
