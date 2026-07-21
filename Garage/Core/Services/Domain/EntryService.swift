import FirebaseFirestore
import Observation
@MainActor struct EntryServiceDependencies { let encodeEntry: (FirestoreEntry) throws -> [String: Any]
    let encodeVehicle: (Vehicle) throws -> [String: Any]
    let batchSubmitter: any AtomicBatchSubmitting
    let syncService: SyncService
    let acknowledgementSink: @Sendable (SyncEvidenceToken, String?) -> Void
}
enum EntrySaveDisposition: Sendable, Equatable { case atomicEntryAndVehicleAccepted, entryOnlyAcceptedForHermeticStore }
struct EntryPage { let entries: [FirestoreEntry], nextCursor: EntryCursor? }
struct EntryCursor { fileprivate let document: DocumentSnapshot?
    fileprivate let entryDate: Date, documentID: String }
@MainActor @Observable final class EntryService { static let shared = EntryService()
    private let liveDependenciesProvider: () -> EntryServiceDependencies
    private let isLocalDemoMode: () -> Bool
    private var testEntries: [FirestoreEntry]?
#if DEBUG
    private let hermeticSaveFailure: ((FirestoreEntry) -> Error?)?
    private let usesHermeticSave: Bool
#endif
    private init() {
        isLocalDemoMode = { AppRuntime.isLocalDemoMode }
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
         hermeticSaveFailure: @escaping (FirestoreEntry) -> Error? = { _ in nil }, usesHermeticSave: Bool = true) {
        self.testEntries = testEntries
        isLocalDemoMode = { false }
        self.hermeticSaveFailure = hermeticSaveFailure
        self.usesHermeticSave = usesHermeticSave
        liveDependenciesProvider = {
            guard let dependencies else { fatalError("Hermetic EntryService must not resolve live dependencies") }
            return dependencies
        }
    }
    init(dependencies: EntryServiceDependencies) {
        testEntries = nil
        isLocalDemoMode = { false }
        hermeticSaveFailure = nil
        usesHermeticSave = false
        liveDependenciesProvider = { dependencies }
    }
#endif
    private var firestore: FirestoreService { FirestoreService.shared }
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
        guard entry.vehicleId == vehicle.id, vehicle.currentOdometer == entry.odometerReading else {
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
        let acknowledgementSink = dependencies.acknowledgementSink
        do {
            try dependencies.batchSubmitter.submitBatch(writes) { [evidence, acknowledgementSink] message in
                acknowledgementSink(evidence, message)
            }
        } catch {
            dependencies.syncService.rollbackMutation(evidence)
            dependencies.syncService.recordFailure(session: session, message: error.localizedDescription)
            throw error
        }
        return .atomicEntryAndVehicleAccepted
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
        return try snapshot.documents.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
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
            .order(by: "entryDate", descending: true).limit(to: limit)
        if !query.entryTypes.isEmpty && query.entryTypes.count < EntryType.allCases.count {
            request = request.whereField("entryType", in: query.entryTypes.map(\.rawValue))
        }
        if let document = cursor?.document { request = request.start(afterDocument: document) }
        let snapshot = try await request.getDocuments()
        let entries = try snapshot.documents.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
        let nextCursor = snapshot.documents.count == limit
            ? Self.cursor(document: snapshot.documents.last, entry: entries.last) : nil
        return EntryPage(entries: Self.filter(entries, with: query.searchText), nextCursor: nextCursor)
    }
    func fetchLatestOdometer(vehicleId: String) async throws -> Int? {
        if let testEntries { return Self.latestOdometer(in: testEntries, vehicleId: vehicleId) }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            let entries = DemoSessionStore.shared.entries(for: vehicleId)
            return Self.latestOdometer(in: entries, vehicleId: vehicleId)
        }
#endif
        let snapshot = try await firestore.db.collection(
            FirestorePaths.vehicleEntries(vehicleId: vehicleId)
        ).order(by: "odometerReading", descending: true).limit(to: 1).getDocuments()
        return try snapshot.documents.first.map {
            try firestore.decode(FirestoreEntry.self, from: $0.data()).odometerReading
        }
    }
    func lastFuelEntry(vehicleId: String) async throws -> FirestoreEntry? {
        if let testEntries { return Self.latestFuelEntry(in: testEntries, vehicleId: vehicleId) }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            let entries = DemoSessionStore.shared.entries(for: vehicleId)
            return Self.latestFuelEntry(in: entries, vehicleId: vehicleId)
        }
#endif
        let snapshot = try await firestore.db.collection(
            FirestorePaths.vehicleEntries(vehicleId: vehicleId)
        ).whereField("entryType", isEqualTo: EntryType.fuel.rawValue)
            .order(by: "entryDate", descending: true).limit(to: 1).getDocuments()
        return try snapshot.documents.first.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
    }
    nonisolated static func filter(_ entries: [FirestoreEntry], with searchText: String) -> [FirestoreEntry] {
        guard searchText.isNotEmpty else { return entries }
        let lowered = searchText.lowercased()
        return entries.filter {
            $0.notes?.lowercased().contains(lowered) == true ||
                $0.entryType.displayName.lowercased().contains(lowered) ||
                $0.details.description.lowercased().contains(lowered)
        }
    }
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
    static func page(_ entries: [FirestoreEntry], matching query: EntryQuery,
                     limit: Int, after cursor: EntryCursor?) -> EntryPage {
        let forVehicle = entries.filter { $0.vehicleId == query.vehicleId }
        let matching = query.entryTypes.isEmpty
            ? forVehicle : forVehicle.filter { query.entryTypes.contains($0.entryType) }
        let ordered = matching.sorted(by: Self.isOrderedBefore)
        let remaining = cursor.map { cursor in ordered.filter { Self.isAfter($0, cursor: cursor) } } ?? ordered
        let page = Array(remaining.prefix(limit))
        return EntryPage(
            entries: filter(page, with: query.searchText),
            nextCursor: page.count == limit ? Self.cursor(for: page.last) : nil
        )
    }
    static func cursor(document: DocumentSnapshot?, entry: FirestoreEntry?) -> EntryCursor? {
        guard let document, let entry else { return nil }
        return EntryCursor(document: document, entryDate: entry.entryDate, documentID: document.documentID)
    }
    static func cursor(for entry: FirestoreEntry?) -> EntryCursor? {
        guard let entry else { return nil }
        return EntryCursor(document: nil, entryDate: entry.entryDate, documentID: entry.id)
    }
    static func isOrderedBefore(_ lhs: FirestoreEntry, _ rhs: FirestoreEntry) -> Bool {
        lhs.entryDate != rhs.entryDate ? lhs.entryDate > rhs.entryDate : lhs.id > rhs.id
    }
    static func isAfter(_ entry: FirestoreEntry, cursor: EntryCursor) -> Bool {
        entry.entryDate != cursor.entryDate ? entry.entryDate < cursor.entryDate : entry.id < cursor.documentID
    }
    nonisolated static func latestOdometer(in entries: [FirestoreEntry], vehicleId: String) -> Int? {
        entries.filter { $0.vehicleId == vehicleId }.map(\.odometerReading).max()
    }
    nonisolated static func latestFuelEntry(in entries: [FirestoreEntry], vehicleId: String) -> FirestoreEntry? {
        entries.filter { $0.vehicleId == vehicleId && $0.entryType == .fuel }.max { $0.entryDate < $1.entryDate }
    }
}
