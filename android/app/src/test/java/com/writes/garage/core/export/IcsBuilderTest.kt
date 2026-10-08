package com.writes.garage.core.export

import com.writes.garage.core.model.Reminder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class IcsBuilderTest {
    private val stamp = Instant.parse("2026-06-01T08:30:00Z")

    private fun reminder(title: String = "Oil change", due: Instant? = Instant.parse("2026-09-15T14:00:00Z"), months: Int? = null) =
        Reminder(id = "rem1", vehicleId = "v1", title = title, dueDate = due, repeatIntervalMonths = months)

    @Test
    fun singleEventByteForByte() {
        val ics = IcsBuilder.makeCalendar(reminder(months = 6), stamp)
        assertEquals(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Garage//Reminder Export//EN\r\nCALSCALE:GREGORIAN\r\n" +
                "BEGIN:VEVENT\r\nUID:rem1@garage\r\nDTSTAMP:20260601T083000Z\r\nDTSTART:20260915T140000Z\r\n" +
                "SUMMARY:Oil change\r\nRRULE:FREQ=MONTHLY;INTERVAL=6\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            ics,
        )
    }

    @Test
    fun noDueDateMeansNoCalendar() {
        assertNull(IcsBuilder.makeCalendar(reminder(due = null), stamp))
        assertNull(IcsBuilder.makeCalendar(emptyList(), stamp))
    }

    @Test
    fun nonPositiveRepeatIntervalIsDropped() {
        assertFalse(IcsBuilder.makeCalendar(reminder(months = 0), stamp)!!.contains("RRULE"))
        assertFalse(IcsBuilder.makeCalendar(reminder(months = -3), stamp)!!.contains("RRULE"))
    }

    @Test
    fun textEscapingReplacesBackslashFirst() {
        assertEquals("a\\\\b\\;c\\,d\\ne\\nf\\ng", IcsBuilder.escape("a\\b;c,d\ne\r\nf\rg"))
    }

    @Test
    fun foldingNeverExceeds75OctetsAndNeverSplitsACodePoint() {
        val long = "SUMMARY:" + "é".repeat(60) + "🚗".repeat(10) // 2-byte and 4-byte code points
        val folded = IcsBuilder.fold(long)
        assertTrue(folded.size > 1)
        folded.forEach { assertTrue(it.toByteArray(Charsets.UTF_8).size <= 75) }
        folded.drop(1).forEach { assertTrue(it.startsWith(" ")) }
        // unfolding restores the original exactly
        assertEquals(long, folded.mapIndexed { i, s -> if (i == 0) s else s.drop(1) }.joinToString(""))
        assertEquals(listOf("short"), IcsBuilder.fold("short"))
    }

    @Test
    fun multipleRemindersShareOneCalendarAndSkipUndated() {
        val ics = IcsBuilder.makeCalendar(listOf(reminder("A"), reminder("B", due = null), reminder("C")), stamp)!!
        assertEquals(2, Regex("BEGIN:VEVENT").findAll(ics).count())
        assertEquals(1, Regex("BEGIN:VCALENDAR").findAll(ics).count())
        assertTrue(ics.endsWith("END:VCALENDAR\r\n"))
    }

    @Test
    fun notesBecomeEscapedDescription() {
        val ics = IcsBuilder.makeCalendar(reminder().copy(notes = "bring card, ok; thanks"), stamp)!!
        assertTrue(ics.contains("DESCRIPTION:bring card\\, ok\\; thanks\r\n"))
    }
}
