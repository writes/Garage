package com.writes.garage.core.domain

/**
 * The rule that decides a vehicle's `currentOdometer` after an entry is saved (iOS `EntryFormViewModel.updatedVehicle`).
 *
 * It does two opposite things: a NEW entry must never silently lower a number the owner declared, while an EDIT that
 * changes the entry's odometer must be able to lower it (correcting a mistyped reading is what editing is for).
 * The result is never behind the entry being saved.
 */
object OdometerFloor {
    /**
     * @param declared the vehicle's current odometer
     * @param reading the saved entry's odometer
     * @param otherEntriesMax the highest odometer among the vehicle's OTHER entries (null = none)
     * @param isEditing true when an existing entry is being saved
     * @param previousReading the entry's odometer before this edit (edits only)
     */
    fun resulting(declared: Int, reading: Int, otherEntriesMax: Int?, isEditing: Boolean, previousReading: Int? = null): Int {
        val others = otherEntriesMax ?: 0
        return when {
            !isEditing -> maxOf(declared, reading, others)
            // Touching notes/cost on an entry must not drag the declared odometer anywhere.
            previousReading == reading -> maxOf(declared, reading)
            else -> maxOf(reading, others)
        }
    }
}
