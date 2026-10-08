package com.writes.garage.feature

import com.writes.garage.TestFixtures
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.export.DossierContent
import com.writes.garage.core.model.EntryType
import com.writes.garage.feature.entry.EntryDetailsMapper
import com.writes.garage.feature.entry.EntryEditViewModel
import com.writes.garage.feature.garage.VehicleEditViewModel
import com.writes.garage.feature.garage.VehicleFormState
import com.writes.garage.feature.garage.VehicleFormValidator
import com.writes.garage.feature.log.groupByMonth
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.TimeZone

/** T17: every zone-sensitive path in zones where an offset or DST bug would actually show (tests elsewhere use UTC). */
class ZoneDeterminismTest {
    @get:Rule val main = MainDispatcherRule()

    private val la = ZoneId.of("America/Los_Angeles")
    private val auckland = ZoneId.of("Pacific/Auckland")
    private val zones = listOf(ZoneOffset.UTC, la, auckland)

    /** 2026-03-31 23:30 on the wall clock of [zone]. */
    private fun lateMarch31(zone: ZoneId): Instant = LocalDate.of(2026, 3, 31).atTime(23, 30).atZone(zone).toInstant()

    @Test
    fun anEntryAtHalfPastElevenLocalGroupsIntoItsOwnMonth() {
        for (zone in zones) {
            val e = TestFixtures.entry("e").copy(entryDate = lateMarch31(zone))
            val groups = groupByMonth(listOf(e), zone)
            assertEquals(zone.id, "March 2026", groups.single().label)
        }
        // The same instant belongs to April on the other side of the date line.
        val la1 = TestFixtures.entry("e").copy(entryDate = lateMarch31(la))
        assertEquals("April 2026", groupByMonth(listOf(la1), ZoneOffset.UTC).single().label)
        assertEquals("April 2026", groupByMonth(listOf(la1), auckland).single().label)
    }

    private fun edit(env: DemoEnv, zone: ZoneId, entryId: String) = EntryEditViewModel(
        env.entries, env.vehicles, SeedData.SQ5_ID, entryId, zone, today = { LocalDate.of(2026, 4, 2) },
    )

    @Test
    fun editingADateNeutralFieldKeepsTheExactInstantInEveryZone() = runTest {
        for (zone in zones) {
            val env = DemoEnv()
            val seeded = env.entries.addEntry(
                TestFixtures.entry("", EntryType.MAINTENANCE, odo = 83_000, vehicleId = SeedData.SQ5_ID, details = mapOf("item" to "air_filter", "status" to "resolved"))
                    .copy(entryDate = lateMarch31(zone)),
            )
            val vm = edit(env, zone, seeded.id)
            assertEquals(zone.id, LocalDate.of(2026, 3, 31), vm.state.value.date)
            vm.update { copy(notes = "changed") }
            vm.save()
            val after = env.store.entries.value.first { it.id == seeded.id }
            assertEquals(zone.id, seeded.entryDate, after.entryDate)
            assertEquals("changed", after.notes)
        }
    }

    @Test
    fun changingTheDayStoresNoonLocalOfThePickedDay() = runTest {
        for (zone in zones) {
            val env = DemoEnv()
            val seeded = env.entries.addEntry(
                TestFixtures.entry("", EntryType.MAINTENANCE, odo = 83_000, vehicleId = SeedData.SQ5_ID, details = mapOf("item" to "air_filter", "status" to "resolved"))
                    .copy(entryDate = lateMarch31(zone)),
            )
            val vm = edit(env, zone, seeded.id)
            vm.setDate(LocalDate.of(2026, 3, 5))
            vm.save()
            val after = env.store.entries.value.first { it.id == seeded.id }
            assertEquals(zone.id, LocalDate.of(2026, 3, 5).atTime(12, 0).atZone(zone).toInstant(), after.entryDate)
            assertEquals(zone.id, LocalDate.of(2026, 3, 5), after.entryDate.atZone(zone).toLocalDate())
        }
    }

    @Test
    fun aDetailDateRoundTripsRawToDetailsToRawInEveryZone() {
        for (zone in zones) {
            val details = EntryDetailsMapper.toDetails(
                EntryType.MAINTENANCE, mapOf("item" to "air_filter", "status" to "resolved", "nextDueDate" to "2026-03-08"), emptyMap(), zone,
            )
            assertEquals(zone.id, LocalDate.of(2026, 3, 8).atStartOfDay(zone).toInstant(), details["nextDueDate"])
            assertEquals(zone.id, "2026-03-08", EntryDetailsMapper.toRaw(EntryType.MAINTENANCE, details, zone)["nextDueDate"])
        }
        // 2026-03-08 is the US DST change day: its local midnight is still unambiguous and round-trips.
    }

    @Test
    fun theVehiclePurchaseDateStaysOnThePickedLocalDay() = runTest {
        for (zone in zones) {
            val env = DemoEnv()
            val vm = VehicleEditViewModel(env.vehicles, env.purchases, SeedData.SQ5_ID, zone)
            vm.update { copy(purchaseDate = LocalDate.of(2020, 5, 17)) }
            vm.save()
            val v = env.vehicles.observeVehicle(SeedData.SQ5_ID).first()!!
            assertEquals(zone.id, LocalDate.of(2020, 5, 17).atTime(12, 0).atZone(zone).toInstant(), v.purchaseDate)
            // Reopening the form in the same zone shows the same day.
            val reopened = VehicleEditViewModel(env.vehicles, env.purchases, SeedData.SQ5_ID, zone)
            assertEquals(zone.id, LocalDate.of(2020, 5, 17), reopened.state.value.purchaseDate)
        }
    }

    @Test
    fun savingAnUntouchedPurchaseDateDoesNotShiftIt() = runTest {
        val env = DemoEnv()
        val vm = VehicleEditViewModel(env.vehicles, env.purchases, SeedData.SQ5_ID, la)
        vm.update { copy(purchaseDate = LocalDate.of(2020, 5, 17)) }
        vm.save()
        val first = env.vehicles.observeVehicle(SeedData.SQ5_ID).first()!!.purchaseDate
        val again = VehicleEditViewModel(env.vehicles, env.purchases, SeedData.SQ5_ID, la)
        again.save()
        assertEquals(first, env.vehicles.observeVehicle(SeedData.SQ5_ID).first()!!.purchaseDate)
    }

    @Test
    fun dossierDatesFollowTheGivenZone() {
        val e = TestFixtures.entry("e", EntryType.OIL_CHANGE, odo = 1_000).copy(entryDate = lateMarch31(la))
        val inLa = DossierContent.serviceHistoryLines(listOf(e), la)[1].text
        val inUtc = DossierContent.serviceHistoryLines(listOf(e), ZoneOffset.UTC)[1].text
        assertTrue(inLa, inLa.startsWith("Mar 31, 2026"))
        assertTrue(inUtc, inUtc.startsWith("Apr 1, 2026"))
    }

    @Test
    fun theDefaultZoneOverloadReadsTheCurrentZoneEachCall() {
        val original = TimeZone.getDefault()
        try {
            val instant = lateMarch31(la) // 2026-04-01T06:30Z
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
            assertEquals("Mar 31, 2026", Formatters.date(instant))
            TimeZone.setDefault(TimeZone.getTimeZone("Pacific/Auckland"))
            assertEquals("Apr 1, 2026", Formatters.date(instant))
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            assertEquals("Apr 1, 2026", Formatters.date(instant))
        } finally {
            TimeZone.setDefault(original)
        }
    }

    @Test
    fun formattersRenderMissingValuesAsDashes() {
        assertEquals("-", Formatters.date(null))
        assertEquals("-", Formatters.date(null, la))
        assertEquals("-", Formatters.currency(null))
        assertEquals("-", Formatters.odometer(null))
        assertEquals("-", Formatters.mpg(null))
        assertEquals("-", Formatters.costPerMile(null))
        assertEquals("-", Formatters.percent(null))
        assertEquals("\$1,234.50", Formatters.currency(1234.5))
        assertEquals("1,234 mi", Formatters.odometer(1234))
        assertEquals("25.6 mpg", Formatters.mpg(25.55))
    }

    // ---- clock-independent validator (maxYear passed explicitly)

    @Test
    fun yearBoundsAreCheckedAgainstAnExplicitMaxYear() {
        val ok = VehicleFormState(make = "Audi", model = "SQ5", year = "2027", odometer = "100")
        assertTrue(VehicleFormValidator.validate(ok, maxYear = 2027).isEmpty())
        assertEquals(setOf("year"), VehicleFormValidator.validate(ok.copy(year = "2028"), maxYear = 2027).keys)
        assertEquals(setOf("year"), VehicleFormValidator.validate(ok.copy(year = "1885"), maxYear = 2027).keys)
        assertTrue(VehicleFormValidator.validate(ok.copy(year = "1886"), maxYear = 2027).isEmpty())
    }
}
