package com.writes.garage.feature

import com.writes.garage.core.data.LocalDataWiper
import com.writes.garage.core.data.LocalFiles
import com.writes.garage.core.data.SessionCleaner
import com.writes.garage.core.data.demo.DemoAuthRepository
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.domain.AccentScheme
import com.writes.garage.core.domain.ReminderDueDatePreset
import com.writes.garage.core.export.IcsBuilder
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.notify.InMemoryNotificationSettings
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.feature.handover.ExportFileStore
import com.writes.garage.feature.handover.ExportedFile
import com.writes.garage.feature.settings.ProfileViewModel
import com.writes.garage.feature.settings.RemindersViewModel
import com.writes.garage.feature.settings.SettingsViewModel
import com.writes.garage.feature.settings.ThemeViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneOffset

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsFeaturesTest {
    @get:Rule val main = MainDispatcherRule()

    private class MemoryStore : ExportFileStore {
        val files = mutableMapOf<String, ByteArray>()

        override fun write(fileName: String, mimeType: String, writer: (OutputStream) -> Unit): ExportedFile {
            files[fileName] = ByteArrayOutputStream().also(writer).toByteArray()
            return ExportedFile(fileName, mimeType, "content://test/$fileName")
        }
    }

    // ---------------- reminders ----------------

    private fun reminders(env: DemoEnv, store: MemoryStore = MemoryStore()): RemindersViewModel {
        env.store.activeVehicleId.value = SeedData.SQ5_ID
        return RemindersViewModel(env.vehicles, env.reminders, store, { env.now }, ZoneOffset.UTC, UnconfinedTestDispatcher())
    }

    @Test
    fun createsAReminderWithAPresetDateAndShowsItRanked() = runTest {
        val env = DemoEnv()
        val vm = reminders(env)
        vm.updateForm { copy(title = "Brake fluid") }
        vm.applyPreset(ReminderDueDatePreset.SIX_MONTHS)
        assertTrue(vm.state.value.form.hasDueDate)
        vm.save()
        val saved = env.store.reminders.value.first { it.title == "Brake fluid" }
        assertEquals(Instant.parse("2026-07-01T09:00:00Z"), saved.dueDate)
        assertEquals(SeedData.SQ5_ID, saved.vehicleId)
        assertTrue(vm.state.value.saved)
        assertTrue(vm.state.value.outstanding.any { it.reminder.title == "Brake fluid" })
        assertEquals("Oil change", vm.state.value.form.title) // form reset to defaults
    }

    @Test
    fun invalidFormDoesNotSave() = runTest {
        val env = DemoEnv()
        val vm = reminders(env)
        val before = env.store.reminders.value.size
        vm.updateForm { copy(title = "", dueMileage = "abc") }
        vm.save()
        assertEquals(before, env.store.reminders.value.size)
        assertEquals(setOf("title", "dueMileage"), vm.state.value.form.errors.keys)
    }

    @Test
    fun editUpdatesInPlaceAndDeleteRemoves() = runTest {
        val env = DemoEnv()
        val vm = reminders(env)
        val target = env.store.reminders.value.first { it.id == "seed-reminder-sq5-oil" }
        vm.beginEditing(target)
        assertTrue(vm.state.value.form.isEditing)
        vm.updateForm { copy(title = "Oil + filter") }
        val count = env.store.reminders.value.size
        vm.save()
        assertEquals(count, env.store.reminders.value.size)
        val updated = env.store.reminders.value.first { it.id == target.id }
        assertEquals("Oil + filter", updated.title)
        assertEquals(target.createdAt, updated.createdAt)
        // the due DAY is kept (stored at 09:00 local, like iOS); only the time of day is canonicalised
        assertEquals(target.dueDate!!.atZone(ZoneOffset.UTC).toLocalDate(), updated.dueDate!!.atZone(ZoneOffset.UTC).toLocalDate())

        vm.delete(updated)
        assertTrue(env.store.reminders.value.none { it.id == target.id })
    }

    @Test
    fun markDoneCompletesAndSchedulesTheRepeat() = runTest {
        val env = DemoEnv()
        val vm = reminders(env)
        val target = env.store.reminders.value.first { it.id == "seed-reminder-sq5-oil" }
        vm.markDone(target)
        assertNotNull(env.store.reminders.value.first { it.id == target.id }.completedAt)
        val next = env.store.reminders.value.single { it.title == "Oil change" && it.vehicleId == SeedData.SQ5_ID && it.isOutstanding }
        assertEquals(Instant.parse("2027-05-01T00:00:00Z"), next.dueDate) // original due (day 120) + 12 months, iOS parity
        assertTrue(vm.state.value.completed.any { it.id == target.id })
    }

    @Test
    fun calendarExportWritesAnIcsAndNeedsADate() = runTest {
        val env = DemoEnv()
        val store = MemoryStore()
        val vm = reminders(env, store)
        val dated = env.store.reminders.value.first { it.id == "seed-reminder-sq5-oil" }
        vm.exportCalendar(dated)
        val f = vm.state.value.pendingShare!!
        assertEquals("text/calendar", f.mimeType)
        assertTrue(String(store.files.getValue(f.fileName)).contains("SUMMARY:Oil change"))
        vm.shareHandled()
        assertNull(vm.state.value.pendingShare)

        vm.exportCalendar(Reminder("r", SeedData.SQ5_ID, "Mileage only", dueMileage = 90_000))
        assertNull(vm.state.value.pendingShare)
        assertNotNull(vm.state.value.error)
        assertNull(IcsBuilder.makeCalendar(Reminder("r", "v", "x"), Instant.EPOCH))
    }

    // ---------------- profile / theme / analytics toggle ----------------

    @Test
    fun profileSavesOnlyFormFieldsAndKeepsConsentAndTheme() = runTest {
        val env = DemoEnv()
        val repo = DemoProfileRepository(env.store)
        repo.setThemeId("plum")
        val vm = ProfileViewModel(repo)
        assertTrue(vm.state.value.loaded)
        vm.edit { copy(name = " Ann ", insuranceCompany = "Geico", policyNumber = "P-1", address = "", phone = "555") }
        vm.save()
        assertTrue(vm.state.value.saved)
        val p = env.store.profile.value
        assertEquals("Ann", p.name)
        assertEquals("Geico", p.insuranceCompany)
        assertNull(p.address)
        assertEquals("plum", p.themeId)
        assertTrue(p.hasAiConsent)
    }

    @Test
    fun themeIsGatedOnProWithALockedPreview() = runTest {
        val env = DemoEnv()
        val repo = DemoProfileRepository(env.store)
        env.purchases.setPro(false)
        val vm = ThemeViewModel(repo, env.purchases)
        keepHot(vm.state)
        assertEquals(AccentScheme.entries.size, vm.state.value.schemes.size)
        assertTrue(vm.state.value.schemes.all { it.second }) // all locked for a free user
        assertFalse(vm.select(AccentScheme.MARINE)) // caller must open the paywall
        assertNull(env.store.profile.value.themeId)

        env.purchases.setPro(true)
        assertTrue(vm.select(AccentScheme.MARINE))
        assertEquals("marine", env.store.profile.value.themeId)
        assertEquals(AccentScheme.MARINE, vm.state.value.selected)
        assertTrue(vm.state.value.schemes.none { it.second })
    }

    @Test
    fun accentIdsMatchIosAndBadIdsClear() {
        assertEquals(listOf("classic", "graphite", "marine", "plum"), AccentScheme.entries.map { it.id })
        assertEquals(AccentScheme.PLUM, AccentScheme.fromId(" Plum "))
        assertNull(AccentScheme.fromId("neon"))
        assertNull(AccentScheme.fromId(null))
        assertNull(AccentScheme.CLASSIC.darkArgb) // Classic keeps the app's own accent
    }

    @Test
    fun analyticsSharingWritesOnlyTheOptOutFlag() = runTest {
        val env = DemoEnv()
        val repo = DemoProfileRepository(env.store)
        val vm = SettingsViewModel(DemoAuthRepository(env.store), repo, env.purchases, DemoFunctionsGateway(env.store), InMemoryNotificationSettings(), true, "1")
        assertTrue(env.store.profile.value.analyticsOptOut) // default: opted out
        vm.setAnalyticsSharing(true)
        assertFalse(env.store.profile.value.analyticsOptOut)
        assertTrue(env.store.profile.value.hasAiConsent)
        vm.setAnalyticsSharing(false)
        assertTrue(env.store.profile.value.analyticsOptOut)
    }

    // ---------------- sign-out / delete wipe ----------------

    private class FakeWiper(var restart: Boolean = false) : LocalDataWiper {
        var wiped = 0
        override suspend fun wipe() {
            wiped++
        }
        override val needsRestart: Boolean get() = restart
    }

    @Test
    fun signOutSignsOutThenWipesAndRestartsWhenRequired() = runTest {
        val env = DemoEnv()
        val auth = DemoAuthRepository(env.store)
        auth.signInDemo()
        val wiper = FakeWiper(restart = true)
        var restarted = 0
        val cleaner = SessionCleaner(auth, wiper, kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + UnconfinedTestDispatcher(testScheduler))) { restarted++ }
        val vm = SettingsViewModel(auth, DemoProfileRepository(env.store), env.purchases, DemoFunctionsGateway(env.store), InMemoryNotificationSettings(), true, "1", cleaner)
        vm.signOut()
        assertNull(auth.currentUser.value)
        assertEquals(1, wiper.wiped)
        assertEquals(1, restarted)
    }

    @Test
    fun deleteAccountPurgesServerSideThenWipesLocalData() = runTest {
        val env = DemoEnv()
        val auth = DemoAuthRepository(env.store)
        auth.signInDemo()
        val notifications = InMemoryNotificationSettings().also { it.setEnabled(true) }
        val wiper = FakeWiper()
        val cleaner = SessionCleaner(auth, wiper, kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + UnconfinedTestDispatcher(testScheduler)))
        val vm = SettingsViewModel(auth, DemoProfileRepository(env.store), env.purchases, DemoFunctionsGateway(env.store), notifications, true, "1", cleaner)
        vm.deleteAccount()
        assertNull(auth.currentUser.value)
        assertFalse(notifications.enabled.value)
        assertEquals(1, wiper.wiped)
        assertFalse(vm.state.value.busy)
    }

    @Test
    fun aFailedSignOutDoesNotWipeAnything() = runTest {
        val env = DemoEnv()
        val failing = object : com.writes.garage.core.data.AuthRepository by DemoAuthRepository(env.store) {
            override suspend fun signOut() = error("network")
        }
        val wiper = FakeWiper()
        val cleaner = SessionCleaner(failing, wiper, kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + UnconfinedTestDispatcher(testScheduler)))
        val vm = SettingsViewModel(failing, DemoProfileRepository(env.store), env.purchases, DemoFunctionsGateway(env.store), InMemoryNotificationSettings(), true, "1", cleaner)
        vm.signOut()
        assertEquals(0, wiper.wiped)
        assertEquals("network", vm.state.value.error)
    }

    @Test
    fun localFilesClearDirectoriesAndRefuseEscapingNames() {
        val dir = Files.createTempDirectory("garage-wipe").toFile()
        File(dir, "a.pdf").writeText("x")
        File(dir, "sub").mkdir()
        File(dir, "sub/b.csv").writeText("y")
        assertEquals(3, LocalFiles.clearDirectory(dir))
        assertEquals(0, dir.listFiles()!!.size)
        assertEquals(0, LocalFiles.clearDirectory(File(dir, "missing")))

        File(dir, "keep.jpg").writeText("z")
        val outside = File(dir.parentFile, "outside-${System.nanoTime()}.txt").also { it.writeText("o") }
        assertFalse(LocalFiles.deleteNamed(dir, "../${outside.name}"))
        assertTrue(outside.exists())
        assertTrue(LocalFiles.deleteNamed(dir, "keep.jpg"))
        assertFalse(LocalFiles.deleteNamed(dir, ".."))
        outside.delete()
        dir.deleteRecursively()
    }
}
