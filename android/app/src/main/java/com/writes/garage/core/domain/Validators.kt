package com.writes.garage.core.domain

import com.writes.garage.core.model.Entry
import java.time.Instant

object Validators {
    private val vinPattern = Regex("^[A-HJ-NPR-Z0-9]{17}$")

    /** 17 characters, letters and digits, never I / O / Q. Case-insensitive; surrounding spaces ignored. */
    fun isValidVin(vin: String?): Boolean = vin != null && vinPattern.matches(vin.trim().uppercase())

    fun normalizeVin(vin: String?): String? = vin?.trim()?.uppercase()?.takeIf { it.isNotEmpty() }

    /** Odometer entered by a user: digits (commas/spaces tolerated) in 0..2,000,000 (the server clamp). */
    fun parseOdometer(text: String): Int? {
        val digits = text.filterNot { it == ',' || it.isWhitespace() }
        return digits.toIntOrNull()?.takeIf { it in 0..2_000_000 }
    }

    // --- odometer monotonicity (port of EntryService.odometerBounds) ---

    data class OdometerBoundary(val reading: Int, val entryDate: Instant)

    data class OdometerBounds(val earlier: OdometerBoundary?, val later: OdometerBoundary?)

    /** A zero reading means "not recorded"; it never pins a bound. */
    fun odometerBounds(
        entries: List<Entry>,
        vehicleId: String,
        on: Instant,
        excludingEntryId: String? = null,
    ): OdometerBounds {
        val scoped = entries.filter { it.vehicleId == vehicleId && it.id != excludingEntryId && it.odometerReading > 0 }
        val earlier = scoped.filter { it.entryDate <= on }.maxByOrNull { it.odometerReading }
        val later = scoped.filter { it.entryDate > on }.minByOrNull { it.odometerReading }
        return OdometerBounds(
            earlier?.let { OdometerBoundary(it.odometerReading, it.entryDate) },
            later?.let { OdometerBoundary(it.odometerReading, it.entryDate) },
        )
    }

    /** Human-readable warnings (not errors: a corrected odometer is legitimate). Empty when consistent or unrecorded. */
    fun odometerWarnings(reading: Int, bounds: OdometerBounds): List<String> {
        if (reading <= 0) return emptyList()
        val out = mutableListOf<String>()
        bounds.earlier?.takeIf { reading < it.reading }?.let {
            out += "Lower than the ${Formatters.odometer(it.reading)} recorded on ${Formatters.date(it.entryDate)}."
        }
        bounds.later?.takeIf { reading > it.reading }?.let {
            out += "Higher than the ${Formatters.odometer(it.reading)} recorded on ${Formatters.date(it.entryDate)}, a later entry."
        }
        return out
    }
}
