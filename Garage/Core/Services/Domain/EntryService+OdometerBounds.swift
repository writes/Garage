import FirebaseFirestore

// MARK: - Date-scoped odometer bounds (the entry form's validation range)
//
// `fetchLatestOdometer` in +Paging.swift is deliberately left alone: "the highest reading this
// vehicle has ever recorded" is still exactly right for the vehicle's own `currentOdometer` and for
// the create-mode hint. It was only ever wrong as a VALIDATION FLOOR, and the name (`latest`) hid
// that — it carries no date predicate at all. This file answers the different question the form
// actually needs: what readings does this vehicle's history allow on the chosen DATE.

extension EntryService {
    /// How many neighbouring entries on each side of the chosen date the max/min is reduced over.
    ///
    /// The reduce has to happen client-side. Firestore serves a range filter together with an
    /// `orderBy` only when they name the SAME field, so ordering by `entryDate` (which the range
    /// needs) rules out ordering by `odometerReading`, and the composite index that pair would
    /// require is not deployed. Bounding the read keeps it cheap; ordering it by proximity to the
    /// chosen date makes it the RIGHT window, because an odometer climbs — the entries nearest in
    /// time carry the extreme readings on each side.
    static let odometerBoundsWindow = 25

    /// Page budget per side for skipping past unrecorded (zero) readings — see
    /// `recordedNeighbours`. Bounded so a pathological history can never turn opening an entry form
    /// into an unbounded read; 8 × 25 = 200 consecutive zeros is far past anything real, and beyond
    /// it the bound simply goes unenforced (fail open) rather than the form hanging.
    static let odometerBoundsMaxPages = 8

    nonisolated static func odometerBounds(
        in entries: [FirestoreEntry], vehicleId: String, on entryDate: Date,
        excludingEntryID: String? = nil
    ) -> OdometerBounds {
        // A zero reading means "not recorded", never "mile zero" — the same rule MaintenanceAdvisor
        // applies to its baseline. Left in, one legacy zero dated after the chosen date would pin
        // the ceiling at 0 and reject every possible reading.
        let scoped = entries.filter {
            $0.vehicleId == vehicleId && $0.id != excludingEntryID && $0.odometerReading > 0
        }
        return OdometerBounds(
            earlier: highestReading(among: scoped.filter { $0.entryDate <= entryDate }),
            later: lowestReading(among: scoped.filter { $0.entryDate > entryDate })
        )
    }

    nonisolated private static func highestReading(among entries: [FirestoreEntry]) -> OdometerBoundary? {
        boundary(entries.max { $0.odometerReading < $1.odometerReading })
    }

    nonisolated private static func lowestReading(among entries: [FirestoreEntry]) -> OdometerBoundary? {
        boundary(entries.min { $0.odometerReading < $1.odometerReading })
    }

    nonisolated private static func boundary(_ entry: FirestoreEntry?) -> OdometerBoundary? {
        entry.map { OdometerBoundary(reading: $0.odometerReading, entryDate: $0.entryDate) }
    }

#if DEBUG
    /// Hermetic in-flight seam, DEBUG-only — same intent and precedent as `hermeticSaveFailure`.
    /// It runs before the lookup resolves, so a test can simulate the user moving the date picker
    /// while a request is in flight AND can make that request fail. Together those are the only way
    /// to drive `refreshOdometerBounds`'s stale-response guard deterministically on both outcomes:
    /// `testEntries` never throws and never suspends, and the live path needs Firestore.
    ///
    /// It is handed the vehicleId precisely so an armed hook can no-op for every vehicle but its
    /// own — Swift Testing runs suites in parallel and this is process-global state.
    static var testBoundsInFlightHook: (@MainActor (String) async throws -> Void)?
#endif

    /// `excludingEntryID` is the edit-in-place variant every other lookup here carries: the entry
    /// being edited must never bound itself.
    func fetchOdometerBounds(
        vehicleId: String, on entryDate: Date, excludingEntryID: String? = nil
    ) async throws -> OdometerBounds {
#if DEBUG
        try await Self.testBoundsInFlightHook?(vehicleId)
#endif
        if let testEntries {
            return Self.odometerBounds(
                in: testEntries, vehicleId: vehicleId, on: entryDate, excludingEntryID: excludingEntryID
            )
        }
#if DEBUG
        if AppRuntime.isLocalDemoMode {
            return Self.odometerBounds(
                in: DemoSessionStore.shared.entries(for: vehicleId), vehicleId: vehicleId,
                on: entryDate, excludingEntryID: excludingEntryID
            )
        }
#endif
        let collection = firestore.db.collection(FirestorePaths.vehicleEntries(vehicleId: vehicleId))
        // INDEX CONSTRAINT: the range filter and the order name the SAME field, so Firestore's
        // automatic single-field index on `entryDate` serves both of these in both directions —
        // nothing is added to Configuration/FirestoreIndexes.json (which is protected here anyway).
        // Adding a second order-by field, or an inequality on `odometerReading` to skip the zeros
        // server-side, would need a composite that is not deployed (Firestore also forbids range
        // filters on two fields), and the query would FAILED_PRECONDITION at runtime. Hence the
        // zero-skipping is done by PAGING the same single-field query, below.
        let earlier = try await recordedNeighbours(
            from: collection
                .whereField("entryDate", isLessThanOrEqualTo: entryDate)
                .order(by: "entryDate", descending: true)
        )
        let later = try await recordedNeighbours(
            from: collection
                .whereField("entryDate", isGreaterThan: entryDate)
                .order(by: "entryDate", descending: false)
        )
        return Self.odometerBounds(
            in: earlier + later, vehicleId: vehicleId, on: entryDate, excludingEntryID: excludingEntryID
        )
    }

    /// Walks one side's window until it yields at least one entry with a RECORDED reading, that
    /// side's history runs out, or the page budget is spent.
    ///
    /// Cross-check finding: the window limit applies server-side, BEFORE the client-side
    /// zero-reading filter, so a contiguous block of `odometerReading == 0` entries longer than one
    /// page consumed the whole window and returned nothing usable — a real 50,000-mile floor sitting
    /// just beyond the zeros went unseen and a contradictory low reading was admitted. The current
    /// form cannot write a zero (`Validators.positiveInteger` gates every save, and
    /// `makePendingEntry` is the app's only entry write), but the security rules place no constraint
    /// on the field, so legacy and out-of-band documents can carry one — which is why the reading is
    /// filtered at all.
    ///
    /// Paging rather than widening the limit keeps the common case at one small read: a page is
    /// only ever fetched because the previous one was ENTIRELY unrecorded.
    private func recordedNeighbours(from query: Query) async throws -> [FirestoreEntry] {
        var cursor: DocumentSnapshot?
        for _ in 0..<Self.odometerBoundsMaxPages {
            var page = query.limit(to: Self.odometerBoundsWindow)
            if let cursor { page = page.start(afterDocument: cursor) }
            let documents = try await page.getDocuments().documents
            guard let last = documents.last else { return [] }
            let recorded = await Self.decodeTolerantly(documents, using: firestore)
                .filter { $0.odometerReading > 0 }
            guard Self.needsAnotherOdometerPage(recorded: recorded, pageCount: documents.count) else {
                return recorded
            }
            cursor = last
        }
        return []
    }

    /// The paging decision, extracted as a pure rule so it is testable without Firestore (the loop
    /// above cannot be). Another round trip is justified only when the page yielded NOTHING
    /// recorded AND was full — a short page means that side's history is exhausted, so there is
    /// nothing further to skip past, and any recorded reading means the bound has been found.
    /// The old code answered `false` unconditionally, which is exactly the saturation defect.
    static func needsAnotherOdometerPage(recorded: [FirestoreEntry], pageCount: Int) -> Bool {
        recorded.isEmpty && pageCount >= odometerBoundsWindow
    }
}
