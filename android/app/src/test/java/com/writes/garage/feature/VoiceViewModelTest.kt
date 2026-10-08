package com.writes.garage.feature

import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.DemoProfileRepository
import com.writes.garage.core.model.EntryType
import com.writes.garage.feature.voice.VoiceViewModel
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class VoiceViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private class Harness {
        val env = DemoEnv()
        val profile = DemoProfileRepository(env.store)
        val vm = VoiceViewModel(env.vehicles, profile, DemoFunctionsGateway(env.store), env.entries, ZoneOffset.UTC)
    }

    @Test
    fun speechCallbacksDriveTranscript() = runTest {
        val h = Harness()
        h.vm.onListeningStarted()
        assertTrue(h.vm.state.value.listening)
        h.vm.onPartial("changed the")
        assertEquals("changed the", h.vm.state.value.partial)
        h.vm.onSpeechResult("  changed the oil for 90 dollars ")
        val s = h.vm.state.value
        assertFalse(s.listening)
        assertEquals("", s.partial)
        assertEquals("changed the oil for 90 dollars", s.transcript)
    }

    @Test
    fun speechErrorStopsListeningAndKeepsTranscript() = runTest {
        val h = Harness()
        h.vm.setTranscript("typed")
        h.vm.onListeningStarted()
        h.vm.onSpeechError("Didn't catch that. Try again.")
        assertFalse(h.vm.state.value.listening)
        assertEquals("typed", h.vm.state.value.transcript)
        assertEquals("Didn't catch that. Try again.", h.vm.state.value.error)
    }

    @Test
    fun interpretProducesReviewableProposalAndWritesNothing() = runTest {
        val h = Harness()
        val before = h.env.store.entries.value.size
        h.vm.setTranscript("oil change 90")
        h.vm.interpret()
        val s = h.vm.state.value
        assertEquals(EntryType.OIL_CHANGE, s.proposal!!.entryType)
        assertEquals("90.00", s.form!!.cost)
        assertEquals(before, h.env.store.entries.value.size)
    }

    @Test
    fun consentGateThenResume() = runTest {
        val h = Harness()
        h.profile.setAiConsent(false)
        h.vm.setTranscript("fuel 40")
        h.vm.interpret()
        assertTrue(h.vm.state.value.needsConsent)
        assertNull(h.vm.state.value.proposal)
        h.vm.grantConsent()
        assertEquals(EntryType.FUEL, h.vm.state.value.proposal!!.entryType)
    }

    @Test
    fun confirmSavesEditedEntry() = runTest {
        val h = Harness()
        h.vm.setTranscript("brake pads 300")
        h.vm.interpret()
        h.vm.updateForm(h.vm.state.value.form!!.copy(cost = "310", notes = "front pads"))
        h.vm.confirm()
        val s = h.vm.state.value
        assertTrue(s.saved)
        assertNull(s.proposal)
        assertEquals("", s.transcript)
        val saved = h.env.store.entries.value.last()
        assertEquals(EntryType.BRAKE, saved.entryType)
        assertEquals(310.0, saved.cost!!, 0.0)
        assertEquals("front pads", saved.notes)
    }

    @Test
    fun invalidFormBlocksSave_andDiscardWritesNothing() = runTest {
        val h = Harness()
        val before = h.env.store.entries.value.size
        h.vm.setTranscript("tire 100")
        h.vm.interpret()
        h.vm.updateForm(h.vm.state.value.form!!.copy(odometer = "-5"))
        h.vm.confirm()
        assertNotNull(h.vm.state.value.form!!.errors["odometer"])
        h.vm.discard()
        assertEquals(before, h.env.store.entries.value.size)
        assertNull(h.vm.state.value.proposal)
    }
}
