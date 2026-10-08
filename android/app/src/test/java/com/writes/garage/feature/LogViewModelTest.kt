package com.writes.garage.feature

import com.writes.garage.TestFixtures
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.model.EntryType
import com.writes.garage.feature.log.LogViewModel
import com.writes.garage.feature.log.groupByMonth
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class LogViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private fun viewModel(env: DemoEnv) = LogViewModel(env.vehicles, env.entries, ZoneOffset.UTC)

    @Test
    fun showsActiveVehicleEntriesNewestFirst() = runTest {
        val env = DemoEnv()
        val vm = viewModel(env)
        keepHot(vm.state)
        val s = vm.state.value
        assertTrue(s.hasVehicle)
        assertEquals(SeedData.VIPER_ID, s.activeVehicleId)
        assertTrue(s.entries.isNotEmpty())
        assertTrue(s.entries.all { it.vehicleId == SeedData.VIPER_ID })
        assertEquals(s.entries.sortedByDescending { it.entryDate }, s.entries)
        assertEquals(s.entries.size, s.totalCount)
        assertFalse(s.isFiltering)
    }

    @Test
    fun searchMatchesShopNotesAndTypeName() = runTest {
        val vm = viewModel(DemoEnv())
        keepHot(vm.state)
        vm.setSearch("willow")
        assertEquals(listOf(EntryType.TRACK_DAY), vm.state.value.entries.map { it.entryType })
        vm.setSearch("coilover")
        assertEquals(listOf(EntryType.UPGRADE), vm.state.value.entries.map { it.entryType })
        vm.setSearch("Brake")
        assertEquals(listOf(EntryType.BRAKE), vm.state.value.entries.map { it.entryType })
        vm.setSearch("zzz-nothing")
        assertTrue(vm.state.value.entries.isEmpty())
        assertTrue(vm.state.value.isFiltering)
    }

    @Test
    fun typeFiltersAreAdditiveAndClearable() = runTest {
        val vm = viewModel(DemoEnv())
        keepHot(vm.state)
        vm.toggleType(EntryType.OIL_CHANGE)
        assertEquals(setOf(EntryType.OIL_CHANGE), vm.state.value.entries.map { it.entryType }.toSet())
        vm.toggleType(EntryType.FUEL)
        assertEquals(setOf(EntryType.OIL_CHANGE, EntryType.FUEL), vm.state.value.entries.map { it.entryType }.toSet())
        vm.toggleType(EntryType.OIL_CHANGE)
        assertEquals(setOf(EntryType.FUEL), vm.state.value.entries.map { it.entryType }.toSet())
        vm.setSearch("shell")
        vm.clearFilters()
        assertFalse(vm.state.value.isFiltering)
        assertEquals(vm.state.value.totalCount, vm.state.value.entries.size)
    }

    @Test
    fun switchingVehicleSwitchesTheLog() = runTest {
        val env = DemoEnv()
        val vm = viewModel(env)
        keepHot(vm.state)
        vm.selectVehicle(SeedData.SQ5_ID)
        val s = vm.state.value
        assertEquals(SeedData.SQ5_ID, s.activeVehicleId)
        assertTrue(s.entries.all { it.vehicleId == SeedData.SQ5_ID })
        assertEquals(2, s.vehicles.size)
    }

    @Test
    fun noVehicleMeansEmptyLog() = runTest {
        val env = DemoEnv()
        env.store.vehicles.value = emptyList()
        val vm = viewModel(env)
        keepHot(vm.state)
        assertFalse(vm.state.value.hasVehicle)
        assertTrue(vm.state.value.groups.isEmpty())
    }

    @Test
    fun groupsByCalendarMonthWithTotals() {
        // NOW = 2026-06-01T12:00Z
        val entries = listOf(
            TestFixtures.entry("a", daysAgo = 0, cost = 10.0),
            TestFixtures.entry("b", daysAgo = 1, cost = 5.0),
            TestFixtures.entry("c", daysAgo = 40, cost = null),
            TestFixtures.entry("d", daysAgo = 400, cost = 100.0),
        )
        val groups = groupByMonth(entries, ZoneOffset.UTC)
        assertEquals(listOf("June 2026", "May 2026", "April 2026", "April 2025"), groups.map { it.label })
        assertEquals(listOf("a", "b", "c", "d"), groups.flatMap { g -> g.entries.map { it.id } })
        assertEquals(listOf(10.0, 5.0, 0.0, 100.0), groups.map { it.total })
    }
}
