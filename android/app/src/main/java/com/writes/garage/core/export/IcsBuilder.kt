package com.writes.garage.core.export

import com.writes.garage.core.model.Reminder
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** iCalendar (RFC 5545) export for reminders (port of iOS `ICSBuilder`). A .ics is a hand-off, not a calendar sync. */
object IcsBuilder {
    /** RFC 5545 §3.1: lines fold at 75 OCTETS; continuation lines start with one space counted in the same budget. */
    const val MAX_OCTETS_PER_LINE = 75
    const val PRODUCT_ID = "-//Garage//Reminder Export//EN"

    private val stampFormatter = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC)

    /** Null when the reminder has no due date (a mileage-only reminder is not a calendar event). */
    fun makeCalendar(reminder: Reminder, stamped: Instant): String? = makeCalendar(listOf(reminder), stamped)

    /** One VCALENDAR with a VEVENT per reminder that has a due date; null if none do. */
    fun makeCalendar(reminders: List<Reminder>, stamped: Instant): String? {
        val dated = reminders.filter { it.dueDate != null }
        if (dated.isEmpty()) return null
        val lines = mutableListOf("BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:$PRODUCT_ID", "CALSCALE:GREGORIAN")
        for (r in dated) {
            lines += "BEGIN:VEVENT"
            lines += "UID:${r.id}@garage"
            lines += "DTSTAMP:${timestamp(stamped)}"
            lines += "DTSTART:${timestamp(r.dueDate!!)}"
            lines += "SUMMARY:${escape(r.title)}"
            r.notes?.takeIf { it.isNotBlank() }?.let { lines += "DESCRIPTION:${escape(it)}" }
            // INTERVAL must be a positive integer; a malformed rule can make calendars drop the whole event.
            r.repeatIntervalMonths?.takeIf { it > 0 }?.let { lines += "RRULE:FREQ=MONTHLY;INTERVAL=$it" }
            lines += "END:VEVENT"
        }
        lines += "END:VCALENDAR"
        // Every line, including the last, is CRLF-terminated.
        return lines.flatMap(::fold).joinToString("") { it + "\r\n" }
    }

    /** RFC 5545 §3.3.11 TEXT escaping. The backslash is replaced first. */
    fun escape(text: String): String = text
        .replace("\\", "\\\\")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")
        .replace("\r", "\\n")
        .replace(";", "\\;")
        .replace(",", "\\,")

    /** UTC basic format, e.g. `19980118T230000Z`. */
    fun timestamp(instant: Instant): String = stampFormatter.format(instant)

    /** Folds one content line to the octet budget without splitting a (multi-byte) code point. */
    fun fold(line: String): List<String> {
        if (line.toByteArray(Charsets.UTF_8).size <= MAX_OCTETS_PER_LINE) return listOf(line)
        val folded = mutableListOf<String>()
        val current = StringBuilder()
        var octets = 0
        var budget = MAX_OCTETS_PER_LINE
        var i = 0
        while (i < line.length) {
            val cp = line.codePointAt(i)
            val chars = Character.charCount(cp)
            val width = String(Character.toChars(cp)).toByteArray(Charsets.UTF_8).size
            if (octets + width > budget) {
                folded += current.toString()
                current.setLength(0)
                octets = 0
                budget = MAX_OCTETS_PER_LINE - 1
            }
            current.appendCodePoint(cp)
            octets += width
            i += chars
        }
        folded += current.toString()
        return folded.mapIndexed { index, s -> if (index == 0) s else " $s" }
    }
}
