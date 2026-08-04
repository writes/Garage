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
    /// Decodes a page of entry documents, skipping any that fail rather than throwing the whole
    /// page away.
    ///
    /// `VehicleService.fetchVehicles` was hardened this way ("one corrupt doc must not blank the
    /// garage"); entries never were, even though they are far more numerous and carry a per-type
    /// `details` payload that is much likelier to drift. A single undecodable document therefore
    /// emptied the Log tab, the Dashboard recent card, the Stats charts AND the resale PDF/CSV
    /// export for that vehicle — the paid artifact the product exists to produce.
    ///
    /// Failures are recorded as Crashlytics non-fatals, so "quietly dropped" still means "visible
    /// to us". Yields every 50 documents, preserving the chunked-decode behaviour (#22) that keeps
    /// a large page from blocking the main actor through one synchronous run.
    static func decodeTolerantly(
        _ documents: some Sequence<QueryDocumentSnapshot>,
        using firestore: FirestoreService
    ) async -> [FirestoreEntry] {
        var entries: [FirestoreEntry] = []
        for (index, document) in documents.enumerated() {
            do {
                entries.append(try firestore.decode(FirestoreEntry.self, from: document.data()))
            } catch {
                AppLogger.shared.error(
                    "Entry decode failed for \(document.documentID): \(error.localizedDescription)"
                )
                CrashReporter.shared.record(error, context: "entry-decode")
            }
            if index % 50 == 49 { await Task.yield() }
        }
        return entries
    }

    static func cursor(document: DocumentSnapshot?, entry: FirestoreEntry?) -> EntryCursor? {
        guard let document else { return nil }
        // Falls back to the document's raw entryDate when nothing in the page decoded. Requiring a
        // decoded entry meant a page where every document was corrupt produced a nil cursor, which
        // the caller reads as "no more history" — truncating the log at the corruption instead of
        // paging past it, and defeating the point of tolerating the bad document in the first
        // place. The date is only used by the in-memory ordering path; live paging resumes from
        // `document`.
        guard let entryDate = entry?.entryDate ?? rawEntryDate(document) else { return nil }
        return EntryCursor(document: document, entryDate: entryDate, documentID: document.documentID)
    }

    /// `entryDate` is a Firestore `Timestamp` on the wire. Read directly so a document whose
    /// *other* fields fail to decode can still position the cursor.
    static func rawEntryDate(_ document: DocumentSnapshot) -> Date? {
        (document.data()?["entryDate"] as? Timestamp)?.dateValue()
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
    nonisolated static func latestOdometer(
        in entries: [FirestoreEntry], vehicleId: String, excludingEntryID: String? = nil
    ) -> Int? {
        entries.filter { $0.vehicleId == vehicleId && $0.id != excludingEntryID }.map(\.odometerReading).max()
    }
    /// `before` (review MAJOR): the previous fill-up must be strictly older than the entry's
    /// CURRENT form date, not just "the newest OTHER fuel entry" — otherwise editing any non-
    /// latest fuel entry could pick a chronologically LATER entry as its "previous" fill-up,
    /// corrupting calculatedMPG. Tiebreak on equal dates matches isOrderedBefore/EntryCursor's
    /// descending-id convention, so this stays consistent with pagination ordering elsewhere.
    nonisolated static func latestFuelEntry(
        in entries: [FirestoreEntry], vehicleId: String, before: Date, excludingEntryID: String? = nil
    ) -> FirestoreEntry? {
        entries
            .filter {
                $0.vehicleId == vehicleId && $0.entryType == .fuel
                    && $0.id != excludingEntryID && $0.entryDate < before
            }
            // Newest wins; on an exact date tie, higher id wins — matches isOrderedBefore's
            // descending-with-id-tiebreak convention (verified equivalent to
            // `.sorted(by: isOrderedBefore).first`), just expressed as max()'s ascending sense.
            .max { lhs, rhs in
                lhs.entryDate != rhs.entryDate ? lhs.entryDate < rhs.entryDate : lhs.id < rhs.id
            }
    }
}

// MARK: - Odometer/fuel-history lookups (edit-in-place needs an excludingEntryID variant of each:
// the entry being edited must not count as its own "previous odometer" or "previous fill-up")

extension EntryService {
    func fetchLatestOdometer(vehicleId: String, excludingEntryID: String? = nil) async throws -> Int? {
        if let testEntries {
            return Self.latestOdometer(in: testEntries, vehicleId: vehicleId, excludingEntryID: excludingEntryID)
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            let entries = DemoSessionStore.shared.entries(for: vehicleId)
            return Self.latestOdometer(in: entries, vehicleId: vehicleId, excludingEntryID: excludingEntryID)
        }
#endif
        // A max query can't exclude a specific document server-side. Excluding one document can
        // knock out at most the #1 result, so the true remaining max is always within the top 2 —
        // fetch that (or just 1, when there's nothing to exclude) and skip the excluded id client-side.
        let limit = excludingEntryID == nil ? 1 : 2
        let snapshot = try await firestore.db.collection(
            FirestorePaths.vehicleEntries(vehicleId: vehicleId)
        ).order(by: "odometerReading", descending: true).limit(to: limit).getDocuments()
        let entries = try snapshot.documents.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
        return entries.first { $0.id != excludingEntryID }?.odometerReading
    }

    func lastFuelEntry(
        vehicleId: String, before: Date, excludingEntryID: String? = nil
    ) async throws -> FirestoreEntry? {
        if let testEntries {
            return Self.latestFuelEntry(
                in: testEntries, vehicleId: vehicleId, before: before, excludingEntryID: excludingEntryID
            )
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            let entries = DemoSessionStore.shared.entries(for: vehicleId)
            return Self.latestFuelEntry(
                in: entries, vehicleId: vehicleId, before: before, excludingEntryID: excludingEntryID
            )
        }
#endif
        let limit = excludingEntryID == nil ? 1 : 2
        // The vehicleId equality is data-redundant (the subcollection path already scopes it) but
        // INDEX-load-bearing: the deployed composite is (vehicleId, entryType, entryDate DESC),
        // and Firestore only serves a query whose filters cover the index's LEADING fields.
        // Without it this shape needs an (entryType, entryDate) index that does not exist, so the
        // query FAILED_PRECONDITIONs — and FuelFormView's `try?` swallowed that, silently killing
        // MPG auto-fill (found 2026-08-03, same prefix rule as the advisor's narrowed fetch).
        let snapshot = try await firestore.db.collection(
            FirestorePaths.vehicleEntries(vehicleId: vehicleId)
        ).whereField("vehicleId", isEqualTo: vehicleId)
            .whereField("entryType", isEqualTo: EntryType.fuel.rawValue)
            .whereField("entryDate", isLessThan: before)
            .order(by: "entryDate", descending: true).limit(to: limit).getDocuments()
        let entries = try snapshot.documents.map { try firestore.decode(FirestoreEntry.self, from: $0.data()) }
        return entries.first { $0.id != excludingEntryID }
    }
}
