package com.writes.garage.feature

import com.writes.garage.core.data.demo.DemoAuthRepository
import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.notify.InMemoryNotificationSettings
import com.writes.garage.feature.settings.PaywallViewModel
import com.writes.garage.feature.settings.SettingsViewModel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SettingsViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private class Harness(isDemo: Boolean = true) {
        val env = DemoEnv()
        val auth = DemoAuthRepository(env.store)
        val profile = DemoProfileRepository(env.store)
        val notifications = InMemoryNotificationSettings()
        val vm = SettingsViewModel(auth, profile, env.purchases, DemoFunctionsGateway(env.store), notifications, isDemo, "1.2.3")
    }

    @Test
    fun exposesAccountPlanBackendAndVersion() = runTest {
        val h = Harness()
        h.auth.signInDemo()
        val s = h.vm.state.value
        assertEquals("Demo Driver", s.user?.displayName)
        assertEquals("Demo", s.backendLabel)
        assertEquals("1.2.3", s.appVersion)
        assertEquals("Garage Pro", s.planLabel) // demo store starts as Pro
        assertTrue(s.profile!!.hasAiConsent)
    }

    @Test
    fun liveBackendLabel() = runTest {
        assertEquals("Live", Harness(isDemo = false).vm.state.value.backendLabel)
    }

    @Test
    fun aiConsentToggleRoundTrips() = runTest {
        val h = Harness()
        h.vm.setAiConsent(false)
        assertFalse(h.vm.state.value.profile!!.hasAiConsent)
        h.vm.setAiConsent(true)
        assertTrue(h.vm.state.value.profile!!.hasAiConsent)
    }

    @Test
    fun notificationToggleAndPermissionDenial() = runTest {
        val h = Harness()
        h.vm.setNotificationsEnabled(true)
        assertTrue(h.vm.state.value.notificationsEnabled)
        h.vm.notificationPermissionDenied()
        assertFalse(h.vm.state.value.notificationsEnabled)
        assertNotNull(h.vm.state.value.error)
        h.vm.clearMessages()
        assertNull(h.vm.state.value.error)
    }

    @Test
    fun signOutClearsSession() = runTest {
        val h = Harness()
        h.auth.signInDemo()
        h.vm.signOut()
        assertNull(h.vm.state.value.user)
    }

    @Test
    fun deleteAccountCallsBackendThenSignsOutAndStopsNotifications() = runTest {
        val h = Harness()
        h.auth.signInDemo()
        h.notifications.setEnabled(true)
        h.vm.deleteAccount()
        val s = h.vm.state.value
        assertNull(s.user)
        assertFalse(s.notificationsEnabled)
        assertFalse(s.busy)
        assertNull(s.error)
    }

    @Test
    fun paywallLoadsPackagesPurchasesAndRestores() = runTest {
        val env = DemoEnv()
        env.purchases.setPro(false)
        val vm = PaywallViewModel(env.purchases)
        keepHot(vm.state)
        assertTrue(vm.state.value.loaded)
        assertEquals(2, vm.state.value.packages.size)
        assertFalse(vm.state.value.isPro)

        vm.purchase("annual")
        assertTrue(vm.state.value.isPro)
        assertNotNull(vm.state.value.message)

        vm.restore()
        assertEquals("Purchases restored.", vm.state.value.message)
    }

    // ---- T11: ordering and failure semantics, with recording fakes (the demo gateway nulls the user itself).

    private class RecordingHarness(failure: Throwable? = null, gate: CompletableDeferred<Unit>? = null) {
        val env = DemoEnv()
        val log = CallLog()
        val auth = RecordingAuth(DemoAuthRepository(env.store), log)
        val functions = RecordingFunctions(DemoFunctionsGateway(env.store), log, failure, gate)
        val notifications = InMemoryNotificationSettings(initial = true)
        val vm = SettingsViewModel(auth, DemoProfileRepository(env.store), env.purchases, functions, notifications, true, "1")
    }

    @Test
    fun deleteAccountRunsBackendFirstThenExactlyOneSignOut() = runTest {
        val h = RecordingHarness()
        h.auth.signInDemo()
        h.vm.deleteAccount()
        assertEquals(listOf("functions.deleteAccount", "auth.signOut"), h.log.calls)
        assertEquals(1, h.log.count("auth.signOut"))
        assertFalse("notifications are disabled after success", h.notifications.enabled.value)
        assertNull(h.vm.state.value.user)
        assertFalse(h.vm.state.value.busy)
    }

    @Test
    fun deleteAccountFailureKeepsUserSignedInAndNotificationsOn() = runTest {
        val h = RecordingHarness(failure = IllegalStateException("server said no"))
        h.auth.signInDemo()
        h.vm.deleteAccount()
        assertEquals(0, h.log.count("auth.signOut"))
        assertTrue(h.notifications.enabled.value)
        assertNotNull("user must stay signed in", h.vm.state.value.user)
        assertEquals("server said no", h.vm.state.value.error)
        assertFalse(h.vm.state.value.busy)
    }

    @Test
    fun deleteAccountWhileBusyIsIgnored() = runTest {
        val gate = CompletableDeferred<Unit>()
        val h = RecordingHarness(gate = gate)
        h.auth.signInDemo()
        h.vm.deleteAccount()
        assertTrue(h.vm.state.value.busy)
        h.vm.deleteAccount()
        assertEquals(1, h.log.count("functions.deleteAccount"))
        gate.complete(Unit)
        assertEquals(1, h.log.count("auth.signOut"))
        assertFalse(h.vm.state.value.busy)
    }

    @Test
    fun signOutFailureSurfacesAnError() = runTest {
        val h = RecordingHarness()
        h.auth.signOutFailure = RuntimeException("no network")
        h.vm.signOut()
        assertEquals("no network", h.vm.state.value.error)
    }

    @Test
    fun deleteAccountWithSessionCleanerEndsSessionOnlyAfterBackend() = runTest {
        val h = RecordingHarness()
        h.auth.signInDemo()
        val cleaner = com.writes.garage.core.data.SessionCleaner(
            h.auth,
            object : com.writes.garage.core.data.LocalDataWiper {
                override val needsRestart = false
                override suspend fun wipe() { h.log.calls += "wipe" }
            },
            kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.test.UnconfinedTestDispatcher(testScheduler)),
        )
        val vm = SettingsViewModel(h.auth, DemoProfileRepository(h.env.store), h.env.purchases, h.functions, h.notifications, true, "1", cleaner)
        vm.deleteAccount()
        assertEquals(listOf("functions.deleteAccount", "auth.signOut", "wipe"), h.log.calls)
    }
}
