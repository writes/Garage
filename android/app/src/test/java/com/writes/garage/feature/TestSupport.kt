package com.writes.garage.feature

import com.writes.garage.core.data.demo.DemoEntryRepository
import com.writes.garage.core.data.demo.DemoPurchaseRepository
import com.writes.garage.core.data.demo.DemoRecords
import com.writes.garage.core.data.demo.DemoReminderRepository
import com.writes.garage.core.data.demo.DemoStore
import com.writes.garage.core.data.demo.DemoVehicleRepository
import com.writes.garage.core.data.demo.SeedData
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.Dispatchers
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import java.time.Instant

/** Replaces Dispatchers.Main so `viewModelScope` runs eagerly in JVM unit tests. */
@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule : TestWatcher() {
    override fun starting(description: Description) = Dispatchers.setMain(UnconfinedTestDispatcher())

    override fun finished(description: Description) = Dispatchers.resetMain()
}

/** Keeps a `stateIn(WhileSubscribed)` flow hot for the duration of the test. */
@OptIn(ExperimentalCoroutinesApi::class)
fun <T> TestScope.keepHot(flow: StateFlow<T>): Job =
    backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { flow.collect { } }

/** Demo repositories over one seeded store with a frozen clock. */
class DemoEnv(val now: Instant = Instant.parse("2026-01-01T00:00:00Z")) {
    val store = DemoStore(SeedData(now)) { now }
    val vehicles = DemoVehicleRepository(store)
    val entries = DemoEntryRepository(store)
    val reminders = DemoReminderRepository(store)
    val purchases = DemoPurchaseRepository(store)
    val gallery = DemoRecords.gallery(store)
    val warranties = DemoRecords.warranties(store)
    val parts = DemoRecords.parts(store)
    val detailing = DemoRecords.detailing(store)
    val recalls = DemoRecords.recalls(store)
    val wear = DemoRecords.wear(store)
}
