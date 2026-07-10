import FirebaseFirestore
import Observation

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
        if let testEntries {
            return Self.entries(testEntries, matching: query, limit: limit)
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Self.entries(
                DemoSessionStore.shared.entries(for: query.vehicleId),
                matching: query,
                limit: limit
            )
        }
#endif

        var request: Query = firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: query.vehicleId))
            .order(by: "entryDate", descending: true)
            .limit(to: limit)

        if !query.entryTypes.isEmpty && query.entryTypes.count < EntryType.allCases.count {
            request = request.whereField("entryType", in: query.entryTypes.map(\.rawValue))
        }

        let snapshot = try await request.getDocuments()
        let entries = try snapshot.documents.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
        return Self.filter(entries, with: query.searchText)
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

    nonisolated static func entries(
        _ entries: [FirestoreEntry],
        matching query: EntryQuery,
        limit: Int
    ) -> [FirestoreEntry] {
        let forVehicle = entries.filter { $0.vehicleId == query.vehicleId }
        let matchingTypes = query.entryTypes.isEmpty
            ? forVehicle
            : forVehicle.filter { query.entryTypes.contains($0.entryType) }
        return Array(filter(matchingTypes, with: query.searchText).prefix(limit))
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
