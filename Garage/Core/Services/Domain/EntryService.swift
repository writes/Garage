import FirebaseFirestore
import Observation

struct EntryPage {
    let entries: [FirestoreEntry]
    let nextCursor: EntryCursor?
}

struct EntryCursor {
    fileprivate let document: DocumentSnapshot?
    fileprivate let entryDate: Date
    fileprivate let documentID: String
}

@MainActor
@Observable
final class EntryService {
    static let shared = EntryService()

    private var firestore: FirestoreService { .shared }
    private var testEntries: [FirestoreEntry]?

    private init() {}

#if DEBUG
    init(testEntries: [FirestoreEntry]) {
        self.testEntries = testEntries
    }
#endif

    func save(_ entry: FirestoreEntry) async throws {
        if var testEntries {
            if let index = testEntries.firstIndex(where: { $0.id == entry.id }) {
                testEntries[index] = entry
            } else {
                testEntries.append(entry)
            }
            self.testEntries = testEntries
            return
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            DemoSessionStore.shared.save(entry)
            return
        }
#endif

        let reference = firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: entry.vehicleId))
            .document(entry.id)
        try await reference.setData(firestore.encode(entry), merge: true)
    }

    func fetchRecent(vehicleId: String, limit: Int = Constants.dashboardRecentLimit) async throws -> [FirestoreEntry] {
        if let testEntries {
            return Array(
                testEntries
                    .filter { $0.vehicleId == vehicleId }
                    .sorted { $0.entryDate > $1.entryDate }
                    .prefix(limit)
            )
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Array(DemoSessionStore.shared.entries(for: vehicleId).prefix(limit))
        }
#endif

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: vehicleId))
            .order(by: "entryDate", descending: true)
            .limit(to: limit)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
    }

    func fetchEntries(query: EntryQuery, limit: Int = Constants.pageSize) async throws -> [FirestoreEntry] {
        try await fetchEntries(query: query, limit: limit, after: nil).entries
    }

    func fetchEntries(
        query: EntryQuery,
        limit: Int,
        after cursor: EntryCursor?
    ) async throws -> EntryPage {
        if let testEntries {
            return Self.page(testEntries, matching: query, limit: limit, after: cursor)
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Self.page(
                DemoSessionStore.shared.entries(for: query.vehicleId),
                matching: query,
                limit: limit,
                after: cursor
            )
        }
#endif

        var request: Query = firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: query.vehicleId))
            // Keep the document ID implicit: Firestore tiebreaks `entryDate DESC`
            // with `__name__ DESC`. An explicit ascending ID order needs a mixed-
            // direction composite index; `start(afterDocument:)` remains gapless.
            .order(by: "entryDate", descending: true)
            .limit(to: limit)

        if !query.entryTypes.isEmpty && query.entryTypes.count < EntryType.allCases.count {
            request = request.whereField("entryType", in: query.entryTypes.map(\.rawValue))
        }

        if let document = cursor?.document {
            request = request.start(afterDocument: document)
        }

        let snapshot = try await request.getDocuments()
        let entries = try snapshot.documents.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
        let nextCursor = snapshot.documents.count == limit
            ? Self.cursor(document: snapshot.documents.last, entry: entries.last)
            : nil
        return EntryPage(
            entries: Self.filter(entries, with: query.searchText),
            nextCursor: nextCursor
        )
    }

    func fetchLatestOdometer(vehicleId: String) async throws -> Int? {
        if let testEntries {
            return Self.latestOdometer(in: testEntries, vehicleId: vehicleId)
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Self.latestOdometer(
                in: DemoSessionStore.shared.entries(for: vehicleId),
                vehicleId: vehicleId
            )
        }
#endif

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: vehicleId))
            .order(by: "odometerReading", descending: true)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first.map { document in
            try firestore.decode(FirestoreEntry.self, from: document.data()).odometerReading
        }
    }

    func lastFuelEntry(vehicleId: String) async throws -> FirestoreEntry? {
        if let testEntries {
            return Self.latestFuelEntry(in: testEntries, vehicleId: vehicleId)
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Self.latestFuelEntry(
                in: DemoSessionStore.shared.entries(for: vehicleId),
                vehicleId: vehicleId
            )
        }
#endif

        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: vehicleId))
            .whereField("entryType", isEqualTo: EntryType.fuel.rawValue)
            .order(by: "entryDate", descending: true)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
    }

    nonisolated static func filter(_ entries: [FirestoreEntry], with searchText: String) -> [FirestoreEntry] {
        guard searchText.isNotEmpty else { return entries }
        let lowered = searchText.lowercased()
        return entries.filter { entry in
            entry.notes?.lowercased().contains(lowered) == true
                || entry.entryType.displayName.lowercased().contains(lowered)
                || entry.details.description.lowercased().contains(lowered)
        }
    }

    static func page(
        _ entries: [FirestoreEntry],
        matching query: EntryQuery,
        limit: Int,
        after cursor: EntryCursor?
    ) -> EntryPage {
        let forVehicle = entries.filter { $0.vehicleId == query.vehicleId }
        let matchingTypes = query.entryTypes.isEmpty
            ? forVehicle
            : forVehicle.filter { query.entryTypes.contains($0.entryType) }
        let ordered = matchingTypes.sorted(by: Self.isOrderedBefore)
        let remaining = cursor.map { cursor in
            ordered.filter { Self.isAfter($0, cursor: cursor) }
        } ?? ordered
        let page = Array(remaining.prefix(limit))
        let nextCursor = page.count == limit ? Self.cursor(for: page.last) : nil
        return EntryPage(
            entries: filter(page, with: query.searchText),
            nextCursor: nextCursor
        )
    }

    static func cursor(document: DocumentSnapshot?, entry: FirestoreEntry?) -> EntryCursor? {
        guard let document, let entry else { return nil }
        return EntryCursor(
            document: document,
            entryDate: entry.entryDate,
            documentID: document.documentID
        )
    }

    static func cursor(for entry: FirestoreEntry?) -> EntryCursor? {
        guard let entry else { return nil }
        return EntryCursor(document: nil, entryDate: entry.entryDate, documentID: entry.id)
    }

    static func isOrderedBefore(_ lhs: FirestoreEntry, _ rhs: FirestoreEntry) -> Bool {
        if lhs.entryDate != rhs.entryDate {
            return lhs.entryDate > rhs.entryDate
        }
        return lhs.id > rhs.id
    }

    static func isAfter(_ entry: FirestoreEntry, cursor: EntryCursor) -> Bool {
        if entry.entryDate != cursor.entryDate {
            return entry.entryDate < cursor.entryDate
        }
        return entry.id < cursor.documentID
    }

    nonisolated static func latestOdometer(in entries: [FirestoreEntry], vehicleId: String) -> Int? {
        entries
            .filter { $0.vehicleId == vehicleId }
            .map(\.odometerReading)
            .max()
    }

    nonisolated static func latestFuelEntry(
        in entries: [FirestoreEntry],
        vehicleId: String
    ) -> FirestoreEntry? {
        entries
            .filter { $0.vehicleId == vehicleId && $0.entryType == .fuel }
            .max { $0.entryDate < $1.entryDate }
    }
}
