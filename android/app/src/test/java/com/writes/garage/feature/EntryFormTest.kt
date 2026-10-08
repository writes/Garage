package com.writes.garage.feature

import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.model.EntryType
import com.writes.garage.feature.entry.EntryDetailsMapper
import com.writes.garage.feature.entry.EntryDetailsPresenter
import com.writes.garage.feature.entry.EntryEditViewModel
import com.writes.garage.feature.entry.EntryFieldSpecs
import com.writes.garage.feature.entry.EntryFormState
import com.writes.garage.feature.entry.EntryFormValidator
import com.writes.garage.feature.entry.FieldKind
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

class EntryFormTest {
    @get:Rule val main = MainDispatcherRule()

    private fun form(type: EntryType, odometer: String = "1000", cost: String = "", details: Map<String, String> = emptyMap()) =
        EntryFormState(type = type, odometer = odometer, cost = cost, details = EntryDetailsMapper.defaults(type) + details, loading = false)

    // --- specs ---

    @Test
    fun everyEntryTypeHasAFieldSet() {
        EntryType.entries.forEach { type ->
            val spec = EntryFieldSpecs.forType(type)
            assertTrue("$type has no fields", spec.fields.isNotEmpty())
            assertEquals("$type has duplicate keys", spec.fields.size, spec.fields.map { it.key }.toSet().size)
            spec.fields.filter { it.kind == FieldKind.CHOICE }.forEach { assertTrue("${it.key} needs choices", it.choices.isNotEmpty()) }
        }
    }

    // --- validation ---

    @Test
    fun validFormHasNoErrors() {
        val s = form(EntryType.OIL_CHANGE, cost = "\$89.50", details = mapOf("oilBrand" to "Mobil 1", "oilGrade" to "5W-30", "quantityQuarts" to "5"))
        assertTrue(EntryFormValidator.validate(s).isEmpty())
    }

    @Test
    fun odometerAndCostAreChecked() {
        val blank = EntryFormValidator.validate(form(EntryType.ALIGNMENT, odometer = ""))
        assertEquals("Required", blank[EntryFormValidator.ODOMETER])
        assertNotNull(EntryFormValidator.validate(form(EntryType.ALIGNMENT, odometer = "9999999"))[EntryFormValidator.ODOMETER])
        assertNotNull(EntryFormValidator.validate(form(EntryType.ALIGNMENT, cost = "abc"))[EntryFormValidator.COST])
        assertNotNull(EntryFormValidator.validate(form(EntryType.ALIGNMENT, cost = "-5"))[EntryFormValidator.COST])
        assertTrue(EntryFormValidator.validate(form(EntryType.ALIGNMENT, cost = "1,250.00")).isEmpty())
    }

    @Test
    fun requiredDetailFieldsAreEnforcedPerType() {
        val errors = EntryFormValidator.validate(form(EntryType.OIL_CHANGE))
        assertEquals(setOf("detail:oilBrand", "detail:oilGrade", "detail:quantityQuarts"), errors.keys)
        assertEquals(setOf("detail:title"), EntryFormValidator.validate(form(EntryType.REPAIR)).keys)
        assertEquals(setOf("detail:venueName"), EntryFormValidator.validate(form(EntryType.TRACK_DAY)).keys)
        assertEquals(setOf("detail:labName"), EntryFormValidator.validate(form(EntryType.OIL_ANALYSIS)).keys)
        assertEquals(setOf("detail:gallons", "detail:pricePerGallon"), EntryFormValidator.validate(form(EntryType.FUEL)).keys)
        assertTrue(EntryFormValidator.validate(form(EntryType.BRAKE)).isEmpty())
    }

    @Test
    fun conditionalRulesFollowTheirTrigger() {
        // "Describe the service" only exists (and is required) for item = other.
        assertTrue(EntryFormValidator.validate(form(EntryType.MAINTENANCE)).isEmpty())
        val other = EntryFormValidator.validate(form(EntryType.MAINTENANCE, details = mapOf("item" to "other")))
        assertEquals(setOf("detail:otherLabel"), other.keys)
        // Tire brand/model are only required for a new install.
        assertEquals(setOf("detail:tireBrand", "detail:tireModel"), EntryFormValidator.validate(form(EntryType.TIRE)).keys)
        assertTrue(EntryFormValidator.validate(form(EntryType.TIRE, details = mapOf("actionType" to "rotation"))).isEmpty())
    }

    @Test
    fun numericAndFormatRulesApplyToDetails() {
        fun errs(type: EntryType, key: String, value: String) = EntryFormValidator.validate(form(type, details = mapOf(key to value)))["detail:$key"]
        assertNotNull(errs(EntryType.BRAKE, "frontPadPct", "150"))
        assertNull(errs(EntryType.BRAKE, "frontPadPct", "62.5"))
        assertNotNull(errs(EntryType.TRACK_DAY, "numberOfLaps", "2.5"))
        assertNotNull(errs(EntryType.TRACK_DAY, "bestLapTime", "fast"))
        assertNull(errs(EntryType.TRACK_DAY, "bestLapTime", "1:34.821"))
        assertNotNull(errs(EntryType.OIL_CONSUMPTION, "amountAddedQuarts", "-1"))
    }

    // --- mapping ---

    @Test
    fun detailsAreTypedOnTheWayOutAndRoundTrip() {
        val raw = mapOf(
            "oilBrand" to "Mobil 1", "oilGrade" to "0W-40", "quantityQuarts" to "10.5", "filterBrand" to "",
        )
        val details = EntryDetailsMapper.toDetails(EntryType.OIL_CHANGE, raw, emptyMap(), ZoneOffset.UTC)
        assertEquals("Mobil 1", details["oilBrand"])
        assertEquals(10.5, details["quantityQuarts"])
        assertFalse(details.containsKey("filterBrand"))
        val back = EntryDetailsMapper.toRaw(EntryType.OIL_CHANGE, details, ZoneOffset.UTC)
        assertEquals("10.5", back["quantityQuarts"])
        assertEquals("0W-40", back["oilGrade"])
    }

    @Test
    fun wholeNumbersDisplayWithoutDecimals() {
        val raw = EntryDetailsMapper.toRaw(EntryType.TRACK_DAY, mapOf("numberOfLaps" to 24.0, "heatCyclesAdded" to 1L, "venueName" to "WS"), ZoneOffset.UTC)
        assertEquals("24", raw["numberOfLaps"])
        assertEquals("1", raw["heatCyclesAdded"])
    }

    @Test
    fun nonOptionalIosFieldsAreAlwaysWritten() {
        // iOS decodes these as non-optional Codable fields; a missing key would drop the entry there.
        val tire = EntryDetailsMapper.toDetails(EntryType.TIRE, EntryDetailsMapper.defaults(EntryType.TIRE) + ("actionType" to "rotation"), emptyMap(), ZoneOffset.UTC)
        assertEquals("", tire["tireBrand"])
        assertEquals("", tire["tireModel"])
        assertEquals("rotation", tire["actionType"])
        assertEquals("all_four", tire["position"])
        val repair = EntryDetailsMapper.toDetails(EntryType.REPAIR, mapOf("title" to "Pump"), emptyMap(), ZoneOffset.UTC)
        assertEquals(emptyList<String>(), repair["replacedParts"])
        val track = EntryDetailsMapper.toDetails(EntryType.TRACK_DAY, EntryDetailsMapper.defaults(EntryType.TRACK_DAY) + ("venueName" to "WS"), emptyMap(), ZoneOffset.UTC)
        assertEquals(0, track["heatCyclesAdded"])
        assertEquals("dry", track["conditions"])
        val brake = EntryDetailsMapper.toDetails(EntryType.BRAKE, EntryDetailsMapper.defaults(EntryType.BRAKE), emptyMap(), ZoneOffset.UTC)
        assertEquals(false, brake["fluidFlushed"])
    }

    @Test
    fun alignmentSpecsAreNestedAndAlwaysPresent() {
        val empty = EntryDetailsMapper.toDetails(EntryType.ALIGNMENT, emptyMap(), emptyMap(), ZoneOffset.UTC)
        assertEquals(emptyMap<String, Any?>(), empty["beforeSpecs"])
        assertEquals(emptyMap<String, Any?>(), empty["afterSpecs"])
        val d = EntryDetailsMapper.toDetails(EntryType.ALIGNMENT, mapOf("afterSpecs.frontLeftCamber" to "-3.0"), emptyMap(), ZoneOffset.UTC)
        assertEquals(mapOf("frontLeftCamber" to "-3.0"), d["afterSpecs"])
        assertEquals("-3.0", EntryDetailsMapper.toRaw(EntryType.ALIGNMENT, d, ZoneOffset.UTC)["afterSpecs.frontLeftCamber"])
    }

    @Test
    fun replacedPartsSplitOnCommas() {
        val d = EntryDetailsMapper.toDetails(EntryType.REPAIR, mapOf("title" to "x", "replacedParts" to "Water pump, Thermostat ,"), emptyMap(), ZoneOffset.UTC)
        assertEquals(listOf("Water pump", "Thermostat"), d["replacedParts"])
    }

    @Test
    fun unknownKeysSurviveAndHiddenFieldsAreDropped() {
        val base = mapOf<String, Any?>("legacyField" to "keep me", "otherLabel" to "stale")
        val d = EntryDetailsMapper.toDetails(EntryType.MAINTENANCE, mapOf("item" to "air_filter", "status" to "resolved"), base, ZoneOffset.UTC)
        assertEquals("keep me", d["legacyField"])
        assertFalse(d.containsKey("otherLabel"))
    }

    @Test
    fun datesBecomeInstantsInTheGivenZone() {
        val d = EntryDetailsMapper.toDetails(EntryType.MAINTENANCE, mapOf("item" to "air_filter", "status" to "resolved", "nextDueDate" to "2026-03-05"), emptyMap(), ZoneOffset.UTC)
        assertEquals(java.time.Instant.parse("2026-03-05T00:00:00Z"), d["nextDueDate"])
        assertEquals("2026-03-05", EntryDetailsMapper.toRaw(EntryType.MAINTENANCE, d, ZoneOffset.UTC)["nextDueDate"])
    }

    @Test
    fun presenterLabelsKnownKeysAndKeepsLegacyOnes() {
        val entry = DemoEnv().let { SeedData(it.now).entries.first { e -> e.id == "seed-sq5-repair" } }
        val rows = EntryDetailsPresenter.rows(entry, ZoneOffset.UTC).toMap()
        assertEquals("Water pump, Thermostat", rows["Replaced parts (comma separated)"])
        assertEquals("Water pump + thermostat", rows["Title"])
        assertEquals("completed", rows["Status"])
    }

    // --- ViewModel ---

    private fun vm(env: DemoEnv, vehicleId: String?, entryId: String? = null) = EntryEditViewModel(
        env.entries, env.vehicles, vehicleId, entryId, ZoneOffset.UTC, today = { LocalDate.of(2026, 1, 1) },
    )

    @Test
    fun invalidFormDoesNotSave() = runTest {
        val env = DemoEnv()
        val before = env.entries.observeEntries(SeedData.SQ5_ID).first().size
        val vm = vm(env, SeedData.SQ5_ID)
        vm.setType(EntryType.OIL_CHANGE)
        var done = false
        vm.save { done = true }
        val s = vm.state.value
        assertFalse(done)
        assertEquals("Required", s.errors["detail:oilBrand"])
        assertEquals("Fix the highlighted fields.", s.formError)
        assertEquals(before, env.entries.observeEntries(SeedData.SQ5_ID).first().size)
    }

    @Test
    fun editingAFieldClearsItsError() = runTest {
        val vm = vm(DemoEnv(), SeedData.SQ5_ID)
        vm.setType(EntryType.OIL_CHANGE)
        vm.save()
        assertTrue(vm.state.value.errors.containsKey("detail:oilBrand"))
        vm.setDetail("oilBrand", "Mobil 1")
        assertFalse(vm.state.value.errors.containsKey("detail:oilBrand"))
    }

    @Test
    fun savesANewTypedEntryAndAdvancesTheOdometer() = runTest {
        val env = DemoEnv()
        val vm = vm(env, SeedData.SQ5_ID)
        vm.setType(EntryType.OIL_CHANGE)
        vm.setOdometer("83,000")
        vm.setCost("129.99")
        vm.setDetail("oilBrand", "Liqui Moly")
        vm.setDetail("oilGrade", "5W-40")
        vm.setDetail("quantityQuarts", "7")
        vm.update { copy(shop = "  Garage  ", isDiy = true) }
        var done = false
        vm.save { done = true }
        assertTrue(done)
        val saved = env.entries.observeEntries(SeedData.SQ5_ID).first().first { it.entryType == EntryType.OIL_CHANGE && it.odometerReading == 83_000 }
        assertEquals(129.99, saved.cost!!, 0.0001)
        assertEquals("Garage", saved.shopName)
        assertEquals(true, saved.isDiy)
        assertEquals("Liqui Moly", saved.details["oilBrand"])
        assertEquals(7.0, saved.details["quantityQuarts"])
        assertEquals(java.time.Instant.parse("2026-01-01T12:00:00Z"), saved.entryDate)
        assertEquals(83_000, env.vehicles.observeVehicle(SeedData.SQ5_ID).first()!!.currentOdometer)
    }

    @Test
    fun fuelEntryComputesTotalAndMpgAgainstThePreviousFill() = runTest {
        val env = DemoEnv()
        val vm = vm(env, SeedData.SQ5_ID)
        vm.setType(EntryType.FUEL)
        // The vehicle's fuel type seeds the grade.
        assertEquals("premium_91", vm.state.value.details["fuelGrade"])
        vm.setOdometer("82900")
        vm.setDetail("gallons", "18")
        vm.setDetail("pricePerGallon", "4.00")
        vm.save()
        val saved = env.entries.observeEntries(SeedData.SQ5_ID).first().first { it.odometerReading == 82_900 }
        assertEquals(72.0, saved.cost!!, 0.0001)
        assertEquals(72.0, saved.details["totalCost"] as Double, 0.0001)
        // (82,900 - 82,440) / 18 = 25.555... -> 25.6
        assertEquals(25.6, saved.details["calculatedMPG"] as Double, 0.0001)
    }

    @Test
    fun repairStatusDrivesIsResolved() = runTest {
        val env = DemoEnv()
        val vm = vm(env, SeedData.SQ5_ID)
        vm.setType(EntryType.REPAIR)
        vm.setDetail("title", "Wiper motor")
        vm.setDetail("status", "in_progress")
        vm.save()
        val saved = env.entries.observeEntries(SeedData.SQ5_ID).first().first { it.details["title"] == "Wiper motor" }
        assertEquals(false, saved.isResolved)
        assertEquals(emptyList<String>(), saved.details["replacedParts"])
    }

    @Test
    fun warnsWhenOdometerGoesBackwards() = runTest {
        val vm = vm(DemoEnv(), SeedData.SQ5_ID)
        vm.setOdometer("1000")
        assertTrue(vm.state.value.warnings.isNotEmpty())
        vm.setOdometer("90000")
        assertTrue(vm.state.value.warnings.isEmpty())
    }

    @Test
    fun editLoadsPrefillsAndKeepsUnknownDetails() = runTest {
        val env = DemoEnv()
        val original = env.entries.observeEntry(SeedData.SQ5_ID, "seed-sq5-maint").first()!!
        val withLegacy = original.copy(details = original.details + ("futureField" to "x"))
        env.entries.updateEntry(withLegacy)

        val vm = vm(env, SeedData.SQ5_ID, "seed-sq5-maint")
        val s = vm.state.value
        assertFalse(s.loading)
        assertEquals(EntryType.MAINTENANCE, s.type)
        assertEquals("81300", s.odometer)
        assertEquals("240", s.cost)
        assertEquals("air_filter", s.details["item"])
        assertEquals("96000", s.details["nextDueMileage"])

        vm.setCost("250.5")
        var done = false
        vm.save { done = true }
        assertTrue(done)
        val after = env.entries.observeEntry(SeedData.SQ5_ID, "seed-sq5-maint").first()!!
        assertEquals(250.5, after.cost!!, 0.0001)
        assertEquals("x", after.details["futureField"])
        assertEquals(original.entryDate, after.entryDate)
        assertEquals(original.id, after.id)
        assertEquals(1, env.entries.observeEntries(SeedData.SQ5_ID).first().count { it.id == "seed-sq5-maint" })
    }

    @Test
    fun editingAMissingEntryIsNotFound() = runTest {
        val vm = vm(DemoEnv(), SeedData.SQ5_ID, "nope")
        assertTrue(vm.state.value.notFound)
    }

    @Test
    fun addingWithoutAnyVehicleExplainsWhy() = runTest {
        val env = DemoEnv()
        env.store.vehicles.value = emptyList()
        val vm = vm(env, null)
        assertNull(vm.state.value.vehicleId)
        assertEquals("Add a vehicle first.", vm.state.value.formError)
    }
}
