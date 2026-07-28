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
        editingEntryVehicleId = entry.vehicleId
    }

    /// The validateOdometer() floor: the LOWER of "max among every other entry" (lastKnownOdometer,
    /// already excludingEntryID-fetched) and the entry's own original reading. Keeping the entry's
    /// own value unchanged — or lowering it — always validates as long as it doesn't undercut
    /// another entry; raising it still requires clearing the other-entries max. For create
    /// (editingEntryOriginalOdometer nil) this collapses to lastKnownOdometer alone, unchanged.
    var odometerFloor: Int? {
        guard let editingEntryOriginalOdometer else { return lastKnownOdometer }
        guard let lastKnownOdometer else { return editingEntryOriginalOdometer }
        return min(lastKnownOdometer, editingEntryOriginalOdometer)
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
