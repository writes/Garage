package com.writes.garage.core.data

import com.writes.garage.core.data.demo.DemoAuthRepository
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.data.demo.DemoStore
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConsentTest {
    private class RecordingSink : AnalyticsSink {
        val sent = mutableListOf<String>()
        var enabled: Boolean? = null

        override fun log(event: String, params: Map<String, Any?>) {
            sent += event
        }

        override fun setEnabled(enabled: Boolean) {
            this.enabled = enabled
        }
    }

    private class RecordingCrash : CrashReporter {
        val logs = mutableListOf<String>()
        val recorded = mutableListOf<Throwable>()
        var uid: String? = "unset"
        var enabled: Boolean? = null

        override fun log(message: String) {
            logs += message
        }

        override fun record(error: Throwable) {
            recorded += error
        }

        override fun setUserId(uid: String?) {
            this.uid = uid
        }

        override fun setEnabled(enabled: Boolean) {
            this.enabled = enabled
        }
    }

    @Test
    fun eventsAreHeldUntilConsentThenFlushed() {
        val sink = RecordingSink()
        val gate = ConsentGatedAnalyticsSink(sink)
        gate.log("sign_in_completed")
        gate.log("entry_saved")
        assertTrue(sink.sent.isEmpty())
        assertEquals(2, gate.pendingCount)
        gate.setEnabled(true)
        assertEquals(listOf("sign_in_completed", "entry_saved"), sink.sent)
        gate.log("export_pdf")
        assertEquals("export_pdf", sink.sent.last())
    }

    @Test
    fun disablingKeepsHeldEventsButNeverReleasesThem() {
        val sink = RecordingSink()
        val gate = ConsentGatedAnalyticsSink(sink)
        gate.log("a")
        gate.setEnabled(false)
        assertEquals(1, gate.pendingCount)
        assertTrue(sink.sent.isEmpty())
        assertEquals(false, sink.enabled)
    }

    @Test
    fun identityChangeDiscardsHeldEvents() {
        val sink = RecordingSink()
        val gate = ConsentGatedAnalyticsSink(sink)
        gate.log("belongs-to-account-1")
        gate.discardPending()
        gate.setEnabled(true)
        assertTrue(sink.sent.isEmpty())
    }

    @Test
    fun heldEventsAreBoundedOldestDropped() {
        val sink = RecordingSink()
        val gate = ConsentGatedAnalyticsSink(sink, limit = 3)
        repeat(5) { gate.log("e$it") }
        gate.setEnabled(true)
        assertEquals(listOf("e2", "e3", "e4"), sink.sent)
    }

    @Test
    fun crashReporterIsSilentUntilEnabledAndForgetsTheUidOnDisable() {
        val crash = RecordingCrash()
        val gate = ConsentGatedCrashReporter(crash)
        gate.setUserId("uid-1")
        gate.log("breadcrumb")
        gate.record(RuntimeException("x"))
        assertTrue(crash.logs.isEmpty() && crash.recorded.isEmpty())
        assertNull(crash.uid.takeIf { it != "unset" }) // never forwarded while disabled
        gate.setEnabled(true)
        assertEquals("uid-1", crash.uid)
        gate.log("now")
        gate.record(RuntimeException("y"))
        assertEquals(listOf("now"), crash.logs)
        assertEquals(1, crash.recorded.size)
        gate.setEnabled(false)
        assertNull(crash.uid)
        assertEquals(false, crash.enabled)
        gate.record(RuntimeException("z"))
        assertEquals(1, crash.recorded.size)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun TestScope.coordinator(store: DemoStore, crash: RecordingCrash, sink: RecordingSink): Job {
        val job = Job()
        ConsentCoordinator(DemoAuthRepository(store), DemoProfileRepository(store), crash, sink)
            .start(kotlinx.coroutines.CoroutineScope(UnconfinedTestDispatcher(testScheduler) + job))
        return job
    }

    @Test
    fun coordinatorDrivesCollectionFromTheStoredOptOut() = runTest {
        val store = DemoStore()
        val crash = RecordingCrash()
        val sink = RecordingSink()
        val job = coordinator(store, crash, sink)
        // signed out: off
        assertEquals(false, sink.enabled)
        assertEquals(false, crash.enabled)

        DemoAuthRepository(store).signInDemo()
        // default profile is opted OUT: still off
        assertFalse(sink.enabled == true)
        assertFalse(crash.enabled == true)

        DemoProfileRepository(store).setAnalyticsOptOut(false)
        assertEquals(true, sink.enabled)
        assertEquals(true, crash.enabled)
        assertEquals("debug-user", crash.uid)

        DemoProfileRepository(store).setAnalyticsOptOut(true)
        assertEquals(false, sink.enabled)
        assertEquals(false, crash.enabled)

        DemoProfileRepository(store).setAnalyticsOptOut(false)
        DemoAuthRepository(store).signOut()
        assertEquals(false, sink.enabled)
        assertEquals(false, crash.enabled)
        assertNull(crash.uid)
        job.cancel()
    }
}
