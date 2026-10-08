package com.writes.garage.feature

import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.feature.entry.EntryDetailsMapper
import com.writes.garage.feature.entry.EntryEditViewModel
import com.writes.garage.feature.entry.EntryFieldSpecs
import com.writes.garage.feature.entry.EntryFormState
import com.writes.garage.feature.entry.EntryFormValidator
import com.writes.garage.feature.entry.FieldKind
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** iOS `SeedDetailsCanonicalTests` parity: every seeded entry must be something the Android form itself accepts. */
class SeedDataCanonicalTest {
    @get:Rule val main = MainDispatcherRule()

    private val seed = SeedData(Instant.parse("2026-01-01T00:00:00Z"))

    private fun stateFor(e: com.writes.garage.core.model.Entry) = EntryFormState(
        vehicleId = e.vehicleId,
        type = e.entryType,
        odometer = e.odometerReading.toString(),
        cost = e.cost?.toString().orEmpty(),
        details = EntryDetailsMapper.toRaw(e.entryType, e.details, ZoneOffset.UTC),
    )

    @Test
    fun everySeededEntryPassesTheFormValidator() {
        val failures = seed.entries.mapNotNull { e ->
            EntryFormValidator.validate(stateFor(e)).takeIf { it.isNotEmpty() }?.let { "${e.id}: $it" }
        }
        assertTrue("seed entries the form would reject: $failures", failures.isEmpty())
    }

    @Test
    fun everySeededChoiceValueIsAMemberOfItsChoices() {
        val bad = mutableListOf<String>()
        for (e in seed.entries) {
            val raw = EntryDetailsMapper.toRaw(e.entryType, e.details, ZoneOffset.UTC)
            for (f in EntryFieldSpecs.forType(e.entryType).fields.filter { it.kind == FieldKind.CHOICE }) {
                val v = raw[f.key] ?: continue
                if (f.choices.none { it.value == v }) bad += "${e.id}.${f.key}='$v'"
            }
        }
        assertTrue("choice values outside their vocabulary: $bad", bad.isEmpty())
    }

    @Test
    fun anUnknownChoiceValueIsAValidationError() {
        val ok = EntryFormState(
            type = com.writes.garage.core.model.EntryType.REPAIR, odometer = "1000",
            details = mapOf("title" to "Pump", "status" to "resolved"),
        )
        assertTrue(EntryFormValidator.validate(ok).isEmpty())
        val bad = ok.copy(details = ok.details + ("status" to "completed"))
        assertEquals("Choose one of the options", EntryFormValidator.validate(bad)[EntryFormValidator.detailKey("status")])
        // ...but an untouched legacy value (older client) stays editable.
        assertTrue(EntryFormValidator.validate(bad, unchangedLegacy = mapOf("status" to "completed")).isEmpty())
        assertEquals(
            "Choose one of the options",
            EntryFormValidator.validate(bad, unchangedLegacy = mapOf("status" to "other"))[EntryFormValidator.detailKey("status")],
        )
        // A blank optional/defaulted choice is a separate rule (required), not a vocabulary error.
        assertFalse(EntryFormValidator.validate(ok.copy(details = mapOf("title" to "Pump", "status" to "")))
            .containsValue("Choose one of the options"))
    }

    @Test
    fun editingTheSeededRepairAndSavingKeepsItResolved() = runTest {
        val env = DemoEnv()
        env.store.activeVehicleId.value = SeedData.SQ5_ID
        val vm = EntryEditViewModel(
            env.entries, env.vehicles, SeedData.SQ5_ID, "seed-sq5-repair", ZoneOffset.UTC, today = { LocalDate.of(2026, 1, 1) },
        )
        assertNotNull(env.store.entries.value.first { it.id == "seed-sq5-repair" }.isResolved)
        assertEquals(true, env.store.entries.value.first { it.id == "seed-sq5-repair" }.isResolved)
        assertFalse(vm.state.value.loading)
        vm.save {}
        val after = env.store.entries.value.first { it.id == "seed-sq5-repair" }
        assertTrue("saving an unchanged resolved repair must not un-resolve it", after.isResolved == true)
        assertEquals("resolved", after.details["status"])
    }

    @Test
    fun editingTheSeededMaintenanceItemKeepsItsStatus() = runTest {
        val env = DemoEnv()
        env.store.activeVehicleId.value = SeedData.SQ5_ID
        val vm = EntryEditViewModel(
            env.entries, env.vehicles, SeedData.SQ5_ID, "seed-sq5-maint", ZoneOffset.UTC, today = { LocalDate.of(2026, 1, 1) },
        )
        vm.save {}
        val after = env.store.entries.value.first { it.id == "seed-sq5-maint" }
        assertEquals("resolved", after.details["status"])
        assertEquals(true, after.isResolved)
    }
}
