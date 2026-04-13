import FirebaseFirestore
import Observation

@MainActor
@Observable
final class EntryService {
    static let shared = EntryService()

    private let firestore = FirestoreService.shared

    private init() {}

    func save(_ entry: FirestoreEntry) async throws {
        let reference = firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: entry.vehicleId))
            .document(entry.id)
        try await reference.setData(firestore.encode(entry), merge: true)
    }

    func fetchRecent(vehicleId: String, limit: Int = Constants.dashboardRecentLimit) async throws -> [FirestoreEntry] {
        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: vehicleId))
            .order(by: "entryDate", descending: true)
            .limit(to: limit)
            .getDocuments()

        return try snapshot.documents.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
    }

    func fetchEntries(query: EntryQuery, limit: Int = Constants.pageSize) async throws -> [FirestoreEntry] {
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
        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: vehicleId))
            .order(by: "odometerReading", descending: true)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first.map { document in
            try firestore.decode(FirestoreEntry.self, from: document.data()).odometerReading
        }
    }

    func lastFuelEntry(vehicleId: String) async throws -> FirestoreEntry? {
        let snapshot = try await firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: vehicleId))
            .whereField("entryType", isEqualTo: EntryType.fuel.rawValue)
            .order(by: "entryDate", descending: true)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
    }

    static func filter(_ entries: [FirestoreEntry], with searchText: String) -> [FirestoreEntry] {
        guard searchText.isNotEmpty else { return entries }
        let lowered = searchText.lowercased()
        return entries.filter { entry in
            entry.notes?.lowercased().contains(lowered) == true
                || entry.entryType.displayName.lowercased().contains(lowered)
                || entry.details.description.lowercased().contains(lowered)
        }
    }
}
