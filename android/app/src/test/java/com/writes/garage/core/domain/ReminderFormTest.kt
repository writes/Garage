package com.writes.garage.core.domain

import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Reminder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

class ReminderFormTest {
    private val today = LocalDate.of(2026, 1, 31)
    private val utc = ZoneOffset.UTC

    @Test
    fun presetsAddMonthsAndClampMonthEnd() {
        assertEquals(LocalDate.of(2026, 4, 30), ReminderDueDatePreset.THREE_MONTHS.date(today))
        assertEquals(LocalDate.of(2026, 7, 31), ReminderDueDatePreset.SIX_MONTHS.date(today))
        assertEquals(LocalDate.of(2027, 1, 31), ReminderDueDatePreset.ONE_YEAR.date(today))
    }

    @Test
    fun validationFlagsBlankTitleBadNumbersAndPastDates() {
        val s = ReminderFormState(
            title = " ", dueMileage = "abc", repeatMonths = "0", repeatMiles = "-5", hasDueDate = true,
            dueDate = today.minusDays(1),
        )
        val e = ReminderForm.validate(s, today)
        assertEquals(setOf("title", "dueMileage", "repeatMonths", "repeatMiles", "dueDate"), e.keys)
        assertTrue(ReminderForm.validate(ReminderFormState(title = "Oil", dueDate = today), today).isEmpty())
        // an existing reminder with a past date can still be edited unchanged
        assertTrue(ReminderForm.validate(ReminderFormState(editingId = "r", title = "Oil", hasDueDate = true, dueDate = today.minusDays(9)), today).isEmpty())
    }

    @Test
    fun newReminderStoresDueDateAt9amLocalAndDerivesRepeatMiles() {
        val s = ReminderFormState(title = " Oil change ", hasDueDate = true, dueDate = LocalDate.of(2026, 3, 1), dueMileage = "95,000".filter(Char::isDigit), repeatMonths = "6", entryType = EntryType.OIL_CHANGE, notes = " n ")
        val r = ReminderForm.toReminder(s, "v1", null, currentOdometer = 90_000, zone = utc)
        assertEquals("Oil change", r.title)
        assertEquals(Instant.parse("2026-03-01T09:00:00Z"), r.dueDate)
        assertEquals(95_000, r.dueMileage)
        assertEquals(5_000, r.repeatIntervalMiles) // due mileage minus today's odometer, never the absolute reading
        assertEquals(6, r.repeatIntervalMonths)
        assertEquals("n", r.notes)
        assertEquals(EntryType.OIL_CHANGE, r.entryType)
    }

    @Test
    fun explicitRepeatMilesWinAndNoDueMileageDropsTheInterval() {
        val withExplicit = ReminderForm.toReminder(ReminderFormState(title = "x", dueMileage = "95000", repeatMiles = "7500"), "v1", null, 90_000, utc)
        assertEquals(7_500, withExplicit.repeatIntervalMiles)
        val none = ReminderForm.toReminder(ReminderFormState(title = "x", repeatMiles = "7500"), "v1", null, 90_000, utc)
        assertNull(none.repeatIntervalMiles)
        assertNull(ReminderForm.deriveRepeatMiles(80_000, 90_000))
        assertNull(ReminderForm.deriveRepeatMiles(95_000, 0))
    }

    @Test
    fun editKeepsFieldsTheFormDoesNotShow() {
        val old = Reminder(
            "r1", "v1", "Old", createdAt = Instant.parse("2025-01-01T00:00:00Z"), isProFeature = true,
            dueMileage = 20_620, repeatIntervalMiles = 2_500,
        )
        val form = ReminderForm.fromReminder(old, utc, today).copy(title = "New", dueMileage = "21000")
        val saved = ReminderForm.toReminder(form, "v1", old, 18_000, utc)
        assertEquals("r1", saved.id)
        assertEquals("New", saved.title)
        assertEquals(old.createdAt, saved.createdAt)
        assertTrue(saved.isProFeature)
        assertEquals(2_500, saved.repeatIntervalMiles) // the cadence is not re-derived on edit
        // clearing the mileage ends tracking and the interval with it
        val cleared = ReminderForm.toReminder(form.copy(dueMileage = ""), "v1", old, 18_000, utc)
        assertNull(cleared.dueMileage)
        assertNull(cleared.repeatIntervalMiles)
    }

    @Test
    fun mileageOnlyHintAppearsWithoutADate() {
        assertTrue(ReminderForm.mileageOnlyHint(ReminderFormState(hasDueDate = false))!!.contains("can't send an alert"))
        assertNull(ReminderForm.mileageOnlyHint(ReminderFormState(hasDueDate = true)))
    }
}
