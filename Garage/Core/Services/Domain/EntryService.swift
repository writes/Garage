import FirebaseFirestore
import Observation
@MainActor struct EntryServiceDependencies { let encodeEntry: (FirestoreEntry) throws -> [String: Any]
    let encodeVehicle: (Vehicle) throws -> [String: Any]
    let batchSubmitter: any AtomicBatchSubmitting
    let syncService: SyncService
    let acknowledgementSink: @Sendable (SyncEvidenceToken, String?) -> Void
    // Seam for the optimistic + compensating revision bumps around a batch submit; @MainActor
    // @Sendable matches this file's other cross-actor callback fields (see acknowledgementSink).
    // `var`, not `let`: an assigned `let` is EXCLUDED from the memberwise init, which is what
    // hermetic tests use to inject a spy store.
    var bumpRevision: @MainActor @Sendable (String) -> Void = { VehicleDataRevisionStore.shared.bump(vehicleId: $0) }
}
enum EntrySaveDisposition: Sendable, Equatable { case atomicEntryAndVehicleAccepted, entryOnlyAcceptedForHermeticStore }
struct EntryPage { let entries: [FirestoreEntry], nextCursor: EntryCursor? }
// `internal` (not `fileprivate`), unlike the type's original single-file home: pagination
// helpers now live in EntryService+Paging.swift and need to read/construct these fields.
struct EntryCursor { let document: DocumentSnapshot?
    let entryDate: Date, documentID: String }
@MainActor @Observable final class EntryService { static let shared = EntryService()
    // `internal` (not `private`), matching the EntryCursor precedent above: EntryService+Mutations.swift
    // needs these to route deleteEntry through the same testEntries/demo/live modes as save().
    let liveDependenciesProvider: () -> EntryServiceDependencies
    let isLocalDemoMode: () -> Bool
    // `internal`: EntryService+Mutations.swift's cascadeDeleteAttachments uses this. Service-layer
    // (not view-layer) cascade — review BLOCKER: LogView's swipe-delete called deleteEntry
    // directly and never went through EntryDetailView's (now-removed) cascade, orphaning
    // attachments. Putting it here means every caller gets it for free.
    let entryAttachmentService: EntryAttachmentService
    /// `internal`: used by EntryService+Mutations.swift's cascadeDeleteWear. A closure rather than
    /// the service so a hermetic test can observe the cascade without Firestore.
    var wearCascade: @MainActor (String, [String]) async -> Void = { vehicleId, ids in
        WearService.shared.deleteSnapshots(ids: ids, vehicleId: vehicleId)
    }
    var testEntries: [FirestoreEntry]?
#if DEBUG
    private let hermeticSaveFailure: ((FirestoreEntry) -> Error?)?
    let usesHermeticSave: Bool
#endif
    private init() {
        isLocalDemoMode = { AppRuntime.isLocalDemoMode }
        entryAttachmentService = .shared
#if DEBUG
        hermeticSaveFailure = nil
        usesHermeticSave = false
#endif
        liveDependenciesProvider = {
            let firestore = FirestoreService.shared
            return EntryServiceDependencies(
                encodeEntry: { try firestore.encode($0) }, encodeVehicle: { try firestore.encode($0) },
                batchSubmitter: firestore, syncService: SyncServiceProvider.production.resolve(),
                acknowledgementSink: { token, message in
                    Task { @MainActor in
                        SyncServiceProvider.production.resolve().recordAcknowledgement(token, message: message)
                    }
                }
            )
        }
    }
#if DEBUG
    init(testEntries: [FirestoreEntry], dependencies: EntryServiceDependencies? = nil,
         hermeticSaveFailure: @escaping (FirestoreEntry) -> Error? = { _ in nil }, usesHermeticSave: Bool = true,
         entryAttachmentService: EntryAttachmentService = .shared) {
        self.testEntries = testEntries
        isLocalDemoMode = { false }
        self.hermeticSaveFailure = hermeticSaveFailure
        self.usesHermeticSave = usesHermeticSave
        self.entryAttachmentService = entryAttachmentService
        liveDependenciesProvider = {
            guard let dependencies else { fatalError("Hermetic EntryService must not resolve live dependencies") }
            return dependencies
        }
    }
    init(dependencies: EntryServiceDependencies, entryAttachmentService: EntryAttachmentService = .shared) {
        testEntries = nil
        isLocalDemoMode = { false }
        hermeticSaveFailure = nil
        usesHermeticSave = false
        self.entryAttachmentService = entryAttachmentService
        liveDependenciesProvider = { dependencies }
    }
#endif
    var firestore: FirestoreService { FirestoreService.shared }
    func save(_ entry: FirestoreEntry,
              updatingVehicle vehicle: Vehicle, session: SyncSessionToken) throws -> EntrySaveDisposition {
        if var testEntries {
#if DEBUG
            if !usesHermeticSave { return try saveLive(entry, updatingVehicle: vehicle, session: session) }
            if let error = hermeticSaveFailure?(entry) { throw error }
#endif
            if let index = testEntries.firstIndex(where: { $0.id == entry.id }) {
                testEntries[index] = entry
            } else {
                testEntries.append(entry)
            }
            self.testEntries = testEntries
            return .entryOnlyAcceptedForHermeticStore
        }
#if DEBUG
        if isLocalDemoMode() {
            DemoSessionStore.shared.save(entry)
            return .entryOnlyAcceptedForHermeticStore
        }
#endif
        return try saveLive(entry, updatingVehicle: vehicle, session: session)
    }
    private func saveLive(_ entry: FirestoreEntry,
                          updatingVehicle vehicle: Vehicle, session: SyncSessionToken) throws -> EntrySaveDisposition {
        let dependencies = liveDependenciesProvider()
        guard dependencies.syncService.isActive(session),
              session.uid == entry.userId,
              entry.userId == vehicle.userId else {
            throw AppError.auth("The active account no longer owns this entry.")
        }
        // VALIDATION-SEMANTICS CHANGE (relaxed from `==`): editing a non-max-odometer entry
        // passes an `updatedVehicle.currentOdometer` that's the RECOMPUTED max across every
        // OTHER entry (EntryFormViewModel.updatedVehicle), which is >= — and can be strictly
        // greater than — the edited entry's own odometerReading whenever another entry still
        // outranks it. `==` assumed every save's entry IS the vehicle's new max, true only for
        // create. `>=` still rejects the entry-is-ahead-of-the-vehicle corruption signal `==` was
        // guarding against; it just no longer requires the entry being saved to BE the max.
        guard entry.vehicleId == vehicle.id, vehicle.currentOdometer >= entry.odometerReading else {
            throw AppError.validation("The entry must update its matching vehicle odometer.")
        }
        let entryData: [String: Any], encodedVehicle: [String: Any]
        do {
            entryData = try dependencies.encodeEntry(entry)
            encodedVehicle = try dependencies.encodeVehicle(vehicle)
        } catch {
            dependencies.syncService.recordFailure(session: session, message: error.localizedDescription)
            throw error
        }
        let vehicleData = try vehiclePatch(
            from: encodedVehicle, session: session, syncService: dependencies.syncService)
        guard let evidence = dependencies.syncService.registerMutation(session: session) else {
            throw AppError.auth("The active account changed before this entry could be saved.")
        }
        let writes = [
            AtomicBatchWrite(
                path: "\(FirestorePaths.vehicleEntries(vehicleId: entry.vehicleId))/\(entry.id)",
                data: entryData
            ),
            AtomicBatchWrite(path: "\(FirestorePaths.vehicles)/\(vehicle.id)", data: vehicleData)
        ]
        do {
            try dependencies.batchSubmitter.submitBatch(writes, completion: Self.submissionCompletion(
                evidence: evidence, vehicleId: entry.vehicleId, dependencies: dependencies))
        } catch {
            dependencies.syncService.rollbackMutation(evidence)
            dependencies.syncService.recordFailure(session: session, message: error.localizedDescription)
            throw error
        }
        // Optimistic: `submitBatch` only reports LOCAL acceptance here. A later backend rejection
        // is compensated in submissionCompletion above, which bumps again on a non-nil message.
        dependencies.bumpRevision(entry.vehicleId)
        return .atomicEntryAndVehicleAccepted
    }
    private static func submissionCompletion(
        evidence: SyncEvidenceToken, vehicleId: String, dependencies: EntryServiceDependencies
    ) -> @Sendable (String?) -> Void {
        let sink = dependencies.acknowledgementSink
        let bump = dependencies.bumpRevision
        return { message in
            sink(evidence, message)
            guard let message else { return }
            AppLogger.shared.error("Entry submission rejected after optimistic acceptance: \(message)")
            Task { @MainActor in bump(vehicleId) }
        }
    }
    func fetchRecent(vehicleId: String, limit: Int = Constants.dashboardRecentLimit) async throws -> [FirestoreEntry] {
        if let testEntries {
            return Array(
                testEntries.filter { $0.vehicleId == vehicleId }
                    .sorted { $0.entryDate > $1.entryDate }
                    .prefix(limit)
            )
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode { return Array(DemoSessionStore.shared.entries(for: vehicleId).prefix(limit)) }
#endif
        let snapshot = try await firestore.db.collection(
            FirestorePaths.vehicleEntries(vehicleId: vehicleId)
        ).order(by: "entryDate", descending: true).limit(to: limit).getDocuments()
        return await Self.decodeTolerantly(snapshot.documents, using: firestore)
    }
    func fetchEntries(query: EntryQuery, limit: Int = Constants.pageSize) async throws -> [FirestoreEntry] {
        try await fetchEntries(query: query, limit: limit, after: nil).entries
    }
    func fetchEntries(query: EntryQuery, limit: Int, after cursor: EntryCursor?) async throws -> EntryPage {
        if let testEntries { return Self.page(testEntries, matching: query, limit: limit, after: cursor) }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            let entries = DemoSessionStore.shared.entries(for: query.vehicleId)
            return Self.page(entries, matching: query, limit: limit, after: cursor)
        }
#endif
        var request: Query = firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: query.vehicleId))
        // Date-range filters and the order share one field ("entryDate"), so no composite index is needed;
        // combining them with the "entryType" `in` filter below WOULD require one — exports pass no entryTypes.
        request = query.startDate.map { request.whereField("entryDate", isGreaterThanOrEqualTo: $0) } ?? request
        request = query.endDate.map { request.whereField("entryDate", isLessThanOrEqualTo: $0) } ?? request
        // limit+1 sentinel (#4): one extra doc reveals whether more history remains without a
        // wasted round-trip when the vehicle's history is an exact multiple of the page size.
        request = request.order(by: "entryDate", descending: true).limit(to: limit + 1)
        if !query.entryTypes.isEmpty && query.entryTypes.count < EntryType.allCases.count {
            request = request.whereField("entryType", in: query.entryTypes.map(\.rawValue))
        }
        if let document = cursor?.document { request = request.start(afterDocument: document) }
        let snapshot = try await request.getDocuments()
        let hasMore = snapshot.documents.count > limit
        let pageDocuments = snapshot.documents.prefix(limit)
        // Chunked + tolerant decode (#22 + entry-decode hardening): yields every 50 docs, and one
        // undecodable document is skipped rather than throwing the page away.
        let entries = await Self.decodeTolerantly(pageDocuments, using: firestore)
        // The cursor deliberately anchors on the last DOCUMENT consumed, not the last decoded
        // entry: resuming after a skipped corrupt document is what stops paging from looping on
        // it. When nothing in the page decoded, cursor(document:entry:) falls back to the
        // document's raw entryDate so history is paged past the damage rather than truncated at it.
        let nextCursor = hasMore ? Self.cursor(document: pageDocuments.last, entry: entries.last) : nil
        return EntryPage(entries: Self.filter(entries, with: query.searchText), nextCursor: nextCursor)
    }
    // fetchLatestOdometer / lastFuelEntry (both with an excludingEntryID overload for edit-in-
    // place) moved to EntryService+Paging.swift, alongside the in-memory helpers they share —
    // split out to stay under the file cap.
}
extension EntryService {
    private func vehiclePatch(
        from encodedVehicle: [String: Any], session: SyncSessionToken, syncService: SyncService
    ) throws -> [String: Any] {
        guard let currentOdometer = encodedVehicle["currentOdometer"],
              let updatedAt = encodedVehicle["updatedAt"] else {
            let message = "Vehicle sync patch is missing currentOdometer or updatedAt."
            syncService.recordFailure(session: session, message: message)
            throw AppError.database(message)
        }
        return ["currentOdometer": currentOdometer, "updatedAt": updatedAt]
    }
}
