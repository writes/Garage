package com.writes.garage.feature

import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.FuelType
import com.writes.garage.feature.garage.GarageViewModel
import com.writes.garage.feature.garage.VehicleEditViewModel
import com.writes.garage.feature.garage.VehicleFormState
import com.writes.garage.feature.garage.VehicleFormValidator
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class VehicleLimitTest {
    @get:Rule val main = MainDispatcherRule()

    private fun DemoEnv.free() {
        store.entitlement.value = Entitlement.FREE
    }

    private fun addForm(vm: VehicleEditViewModel) {
        vm.edit("make", "Porsche")
        vm.edit("model", "911 GT3")
        vm.edit("year", "2022")
    }

    // --- GarageViewModel: limit as seen by the list screen ---

    @Test
    fun freePlanAllowsOneVehicle() = runTest {
        val env = DemoEnv()
        env.free()
        env.store.vehicles.value = emptyList()
        val vm = GarageViewModel(env.vehicles, env.purchases)
        keepHot(vm.state)
        assertEquals(1, vm.state.value.limit)
        assertTrue(vm.state.value.canAdd)
        env.vehicles.addVehicle(com.writes.garage.TestFixtures.vehicle("a").copy(id = ""))
        assertFalse(vm.state.value.canAdd)
    }

    @Test
    fun proPlanAllowsFive() = runTest {
        val env = DemoEnv() // demo starts as Pro with 2 seeded vehicles
        val vm = GarageViewModel(env.vehicles, env.purchases)
        keepHot(vm.state)
        assertEquals(5, vm.state.value.limit)
        assertTrue(vm.state.value.canAdd)
        assertTrue(vm.state.value.isPro)
    }

    @Test
    fun downgradedAccountWithTwoVehiclesCannotAddMore() = runTest {
        val env = DemoEnv()
        env.free()
        val vm = GarageViewModel(env.vehicles, env.purchases)
        keepHot(vm.state)
        assertEquals(2, vm.state.value.vehicles.size)
        assertFalse(vm.state.value.canAdd)
    }

    @Test
    fun softDeleteRemovesTheVehicleAndMovesTheActiveOne() = runTest {
        val env = DemoEnv()
        val vm = GarageViewModel(env.vehicles, env.purchases)
        keepHot(vm.state)
        assertEquals(SeedData.VIPER_ID, vm.state.value.activeId)
        vm.delete(SeedData.VIPER_ID)
        assertEquals(listOf(SeedData.SQ5_ID), vm.state.value.vehicles.map { it.id })
        assertEquals(SeedData.SQ5_ID, vm.state.value.activeId)
        // Tombstoned, not purged.
        assertNotNull(env.store.vehicles.value.first { it.id == SeedData.VIPER_ID }.deletedAt)
    }

    @Test
    fun setActiveVehicle() = runTest {
        val env = DemoEnv()
        val vm = GarageViewModel(env.vehicles, env.purchases)
        keepHot(vm.state)
        vm.select(SeedData.SQ5_ID)
        assertEquals(SeedData.SQ5_ID, vm.state.value.activeId)
    }

    // --- VehicleEditViewModel: limit enforced on save ---

    @Test
    fun addFormIsGatedWhenThePlanLimitIsUsed() = runTest {
        val env = DemoEnv()
        env.free()
        val vm = VehicleEditViewModel(env.vehicles, env.purchases, null, ZoneOffset.UTC)
        assertTrue(vm.state.value.limitReached)
        assertEquals(1, vm.state.value.limit)
    }

    @Test
    fun savingPastTheLimitFailsWithUpgradeMessageAndAddsNothing() = runTest {
        val env = DemoEnv()
        env.free()
        val vm = VehicleEditViewModel(env.vehicles, env.purchases, null, ZoneOffset.UTC)
        addForm(vm)
        var done = false
        vm.save { done = true }
        assertFalse(done)
        assertEquals("Plan limit reached (1). Upgrade to add more.", vm.state.value.formError)
        assertEquals(2, env.vehicles.observeVehicles().first().size)
    }

    @Test
    fun freeUserCanAddTheFirstVehicleButNotTheSecond() = runTest {
        val env = DemoEnv()
        env.free()
        env.store.vehicles.value = emptyList()
        env.store.activeVehicleId.value = null

        val first = VehicleEditViewModel(env.vehicles, env.purchases, null, ZoneOffset.UTC)
        assertFalse(first.state.value.limitReached)
        addForm(first)
        var done = false
        first.save { done = true }
        assertTrue(done)
        assertEquals(1, env.vehicles.observeVehicles().first().size)
        assertNotNull(env.vehicles.activeVehicleId.value)

        val second = VehicleEditViewModel(env.vehicles, env.purchases, null, ZoneOffset.UTC)
        assertTrue(second.state.value.limitReached)
    }

    @Test
    fun upgradingLiftsTheGate() = runTest {
        val env = DemoEnv()
        env.free()
        val vm = VehicleEditViewModel(env.vehicles, env.purchases, null, ZoneOffset.UTC)
        assertTrue(vm.state.value.limitReached)
        env.purchases.purchase("annual")
        assertFalse(vm.state.value.limitReached)
        addForm(vm)
        var done = false
        vm.save { done = true }
        assertTrue(done)
        assertEquals(3, env.vehicles.observeVehicles().first().size)
    }

    // --- form validation / persistence ---

    @Test
    fun validatorChecksRequiredFieldsVinYearAndOdometer() {
        val ok = VehicleFormState(make = "Audi", model = "SQ5", year = "2015", odometer = "100")
        assertTrue(VehicleFormValidator.validate(ok).isEmpty())
        assertEquals(setOf("make", "model"), VehicleFormValidator.validate(ok.copy(make = " ", model = "")).keys)
        assertEquals(setOf("year"), VehicleFormValidator.validate(ok.copy(year = "1800")).keys)
        assertEquals(setOf("year"), VehicleFormValidator.validate(ok.copy(year = "")).keys)
        assertEquals(setOf("odometer"), VehicleFormValidator.validate(ok.copy(odometer = "")).keys)
        assertEquals(setOf("vin"), VehicleFormValidator.validate(ok.copy(vin = "ABC123")).keys)
        assertEquals(setOf("vin"), VehicleFormValidator.validate(ok.copy(vin = "1HGCM82633A00435O")).keys) // letter O
        assertTrue(VehicleFormValidator.validate(ok.copy(vin = "1hgcm82633a004352")).isEmpty())
        assertEquals(setOf("purchasePrice"), VehicleFormValidator.validate(ok.copy(purchasePrice = "free")).keys)
    }

    @Test
    fun invalidFormDoesNotSave() = runTest {
        val env = DemoEnv()
        val vm = VehicleEditViewModel(env.vehicles, env.purchases, null, ZoneOffset.UTC)
        vm.edit("make", "Audi")
        var done = false
        vm.save { done = true }
        assertFalse(done)
        assertEquals("Required", vm.state.value.errors["model"])
        assertEquals(2, env.vehicles.observeVehicles().first().size)
        vm.edit("model", "S4")
        assertNull(vm.state.value.errors["model"])
    }

    @Test
    fun editRoundTripsEveryField() = runTest {
        val env = DemoEnv()
        val vm = VehicleEditViewModel(env.vehicles, env.purchases, SeedData.SQ5_ID, ZoneOffset.UTC)
        val s = vm.state.value
        assertEquals("Audi", s.make)
        assertEquals(FuelType.PREMIUM_91.wire, s.fuelType)
        vm.edit("vin", "wauzzz8r9fa012345")
        vm.edit("purchasePrice", "31500")
        vm.edit("licensePlate", "7ABC123")
        vm.update { copy(purchaseDate = java.time.LocalDate.of(2020, 5, 17)) }
        var done = false
        vm.save { done = true }
        assertTrue(done)
        val v = env.vehicles.observeVehicle(SeedData.SQ5_ID).first()!!
        assertEquals("WAUZZZ8R9FA012345", v.vin)
        assertEquals(31_500.0, v.purchasePrice!!, 0.001)
        assertEquals("7ABC123", v.licensePlate)
        assertEquals(java.time.Instant.parse("2020-05-17T12:00:00Z"), v.purchaseDate)
        assertEquals("Daily SQ5", v.nickname) // untouched fields survive
        assertEquals(2, env.vehicles.observeVehicles().first().size)
    }

    @Test
    fun editingAMissingVehicleIsNotFound() = runTest {
        val env = DemoEnv()
        val vm = VehicleEditViewModel(env.vehicles, env.purchases, "ghost", ZoneOffset.UTC)
        assertTrue(vm.state.value.notFound)
    }
}
