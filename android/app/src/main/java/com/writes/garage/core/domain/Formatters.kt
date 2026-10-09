package com.writes.garage.core.domain

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

object Formatters {
    private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)

    fun currency(amount: Double?): String = if (amount == null) "-" else String.format(Locale.US, "\$%,.2f", amount)

    /** In the device's CURRENT zone (read per call, so a mid-session zone change is honoured). */
    fun date(instant: Instant?): String = date(instant, ZoneId.systemDefault())

    /** Date rendered in a fixed zone (exports must not depend on the device zone in tests). */
    fun date(instant: Instant?, zone: ZoneId): String =
        instant?.let { dateFormatter.withZone(zone).format(it) } ?: "-"

    fun odometer(miles: Int?): String = if (miles == null) "-" else String.format(Locale.US, "%,d mi", miles)

    fun mpg(value: Double?): String = if (value == null) "-" else String.format(Locale.US, "%.1f mpg", value)

    /** `$0.42/mi`; "-" when there is no ratio. */
    fun costPerMile(value: Double?): String = if (value == null) "-" else String.format(Locale.US, "\$%.2f/mi", value)

    fun percent(value: Double?): String = if (value == null) "-" else String.format(Locale.US, "%.0f%%", value)
}
