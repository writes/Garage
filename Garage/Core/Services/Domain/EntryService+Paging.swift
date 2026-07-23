import FirebaseFirestore

// MARK: - In-memory pagination + filtering (hermetic testEntries and local-demo backing)

extension EntryService {
    static func page(_ entries: [FirestoreEntry], matching query: EntryQuery,
                     limit: Int, after cursor: EntryCursor?) -> EntryPage {
        let forVehicle = entries.filter { $0.vehicleId == query.vehicleId }
        let typed = query.entryTypes.isEmpty
            ? forVehicle : forVehicle.filter { query.entryTypes.contains($0.entryType) }
        let matching = typed.filter { Self.isWithinDateBounds($0.entryDate, query: query) }
        let ordered = matching.sorted(by: Self.isOrderedBefore)
        let remaining = cursor.map { cursor in ordered.filter { Self.isAfter($0, cursor: cursor) } } ?? ordered
        // limit+1 sentinel (#4): mirrors the live Firestore path's overfetch so a hermetic/demo
        // page also reports "no more history" instead of dangling a cursor to an empty next page.
        let overfetched = remaining.prefix(limit + 1)
        let hasMore = overfetched.count > limit
        let page = Array(overfetched.prefix(limit))
        return EntryPage(
            entries: filter(page, with: query.searchText),
            nextCursor: hasMore ? Self.cursor(for: page.last) : nil
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
    static func isWithinDateBounds(_ entryDate: Date, query: EntryQuery) -> Bool {
        entryDate >= (query.startDate ?? .distantPast) && entryDate <= (query.endDate ?? .distantFuture)
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
