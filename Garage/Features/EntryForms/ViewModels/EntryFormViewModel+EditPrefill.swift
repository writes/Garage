import Foundation

// MARK: - Edit-in-place shared-field seeding (audit finding: entries could not be corrected once
// saved). Type-specific `details` seeding lives per-form (each form's own seed(from:)); this only
// covers the fields EntryFormScaffold renders for every entry type.

extension EntryFormViewModel {
    /// Seeds the shared fields from an existing entry for editing, and pins pendingEntryID so
    /// save() overwrites the same document (makePendingEntry reuses it) instead of creating a
    /// new one. Also pins pendingCreatedAt (so save keeps the original createdAt instead of
    /// resetting it) and editingEntryID (so prepare()/odometer/vehicle-update logic and each
    /// form's own excludingEntryID lookups all exclude this entry from counting as its own
    /// "other entry").
    func applyExistingEntry(_ entry: FirestoreEntry) {
        entryDate = entry.entryDate
        odometerReading = String(entry.odometerReading)
        cost = entry.cost.map(Self.costString) ?? ""
        isDiy = entry.isDiy ?? true
        shopName = entry.shopName ?? ""
        notes = entry.notes ?? ""
        attachmentPaths = entry.attachmentPaths
        pendingEntryID = entry.id
        pendingCreatedAt = entry.createdAt
        editingEntryID = entry.id
        editingEntryOriginalOdometer = entry.odometerReading
        editingEntryOriginalDate = entry.entryDate
        editingEntryVehicleId = entry.vehicleId
    }

    /// The range `validateOdometer()` actually enforces.
    ///
    /// Create mode is the raw date-scoped range. Edit mode DROPS a boundary that the entry's own
    /// SAVED reading already violates: that contradiction predates this edit, so enforcing it would
    /// make the entry impossible to re-save at all — even to fix the typo that caused it. This is
    /// the same "an entry never blocks itself" guarantee the old
    /// `min(lastKnownOdometer, editingEntryOriginalOdometer)` floor gave, now applied in both
    /// directions rather than only downward. For create (editingEntryOriginalOdometer nil) it
    /// collapses to the fetched bounds, unchanged.
    ///
    /// The relaxation holds ONLY while the entry still sits on its saved date (cross-check
    /// finding). An entry is grandfathered against the timeline it was already part of, not against
    /// every timeline it could be moved to: once the date changes the entry is being RE-TIMED, and
    /// a deliberate re-timing has to fit the target date's history in full or the drop becomes a
    /// loophole for importing the stale reading into a stretch of history it contradicts.
    var validationBounds: OdometerBounds {
        guard let editingEntryOriginalOdometer, entryDate == editingEntryOriginalDate else {
            return odometerBounds
        }
        var bounds = odometerBounds
        if let earlier = bounds.earlier, editingEntryOriginalOdometer < earlier.reading {
            bounds.earlier = nil
        }
        if let later = bounds.later, editingEntryOriginalOdometer > later.reading {
            bounds.later = nil
        }
        return bounds
    }

    /// Re-derives the legal range for the CURRENT `entryDate`. The structural half of the
    /// backdating defect: the range was only ever derived once, inside `prepare()`, so moving the
    /// date picker left the form validating against the range for whatever date it happened to open
    /// with. EntryFormScaffold calls this on every date change.
    ///
    /// A failed fetch resolves to a permissive range rather than a stale one, and stays off the
    /// error banner: bounds derived for a DIFFERENT date would reject legal readings while naming an
    /// entry that is no longer adjacent, and a failed *hint* lookup must not read like a failed
    /// save. The write path validates independently (EntryService.saveLive's odometer guard).
    ///
    /// The staleness check is ONE guard covering both outcomes, deliberately. Cross-check finding:
    /// as two guards, the success path had one and the catch path did not, so a slow FAILURE from an
    /// older request wiped the bounds a newer request had already installed — silently disabling
    /// validation for the date on screen. Resolving the outcome first and gating the single
    /// assignment makes that divergence unrepresentable rather than merely fixed.
    func refreshOdometerBounds(vehicleId: String) async {
        let requestedDate = entryDate
        let resolved: OdometerBounds
        do {
            resolved = try await entryService.fetchOdometerBounds(
                vehicleId: vehicleId, on: requestedDate, excludingEntryID: editingEntryID
            )
        } catch {
            AppLogger.entries.error("Odometer bounds fetch failed: \(error.localizedDescription)")
            resolved = OdometerBounds()
        }
        guard entryDate == requestedDate else { return }
        odometerBounds = resolved
    }

    /// New currentOdometer = max(entry's own reading, every OTHER entry's reading — freshly
    /// re-fetched by save(), never the cached lastKnownOdometer). Create mode always collapses to
    /// the entry's own value (validateOdometer already guarantees that's the max); edit mode is
    /// what lets lowering the max entry drop the vehicle, and raising a non-max entry above the
    /// current max raise it. `internal` (moved out of the class body for the file cap).
    /// The vehicle's own `currentOdometer` joins the max on CREATE but not on EDIT, and the
    /// asymmetry is the whole point.
    ///
    /// Omitting it entirely — which is what this did — meant the reading the owner typed when
    /// adding the car was discarded by their first entry: add a vehicle at 85,000, log an oil
    /// change you had done at 84,500, and the dashboard silently reads 84,500. That number was
    /// evidence, not a placeholder, and nothing warned or offered to undo it.
    ///
    /// Including it unconditionally would be equally wrong in the other direction: someone who
    /// fat-fingers 200,000 and edits it back to 100,000 must see the vehicle follow, or the typo
    /// is permanent. Correcting a reading is exactly what editing is for — so on an edit the
    /// value is recomputed from entries alone, as before.
    static func updatedVehicle(
        from vehicle: Vehicle,
        for entry: FirestoreEntry,
        otherEntriesMaxOdometer: Int?,
        isEditingExistingEntry: Bool
    ) -> Vehicle {
        var updatedVehicle = vehicle
        let declaredFloor = isEditingExistingEntry ? 0 : vehicle.currentOdometer
        updatedVehicle.currentOdometer = max(
            entry.odometerReading, otherEntriesMaxOdometer ?? 0, declaredFloor
        )
        updatedVehicle.updatedAt = .now
        return updatedVehicle
    }
}
