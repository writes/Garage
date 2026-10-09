package com.writes.garage.feature

import com.writes.garage.core.data.demo.DemoFunctionsGateway
import com.writes.garage.core.data.demo.SeedData
import com.writes.garage.core.export.DossierLine
import com.writes.garage.feature.handover.ExportFileStore
import com.writes.garage.feature.handover.ExportedFile
import com.writes.garage.feature.handover.HandoverViewModel
import kotlinx.coroutines.Dispatchers
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
import java.io.OutputStream

@OptIn(ExperimentalCoroutinesApi::class)
class HandoverViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private open class MemoryStore : ExportFileStore {
        val files = mutableMapOf<String, ByteArray>()

        override fun write(fileName: String, mimeType: String, writer: (OutputStream) -> Unit): ExportedFile {
            val out = ByteArrayOutputStream().also(writer)
            files[fileName] = out.toByteArray()
            return ExportedFile(fileName, mimeType, "content://test/$fileName")
        }
    }

    private class FailingStore : MemoryStore() {
        override fun write(fileName: String, mimeType: String, writer: (OutputStream) -> Unit): ExportedFile =
            throw java.io.IOException("No space left on device")
    }

    private class Harness(failingStore: Boolean = false, failingRenderer: Boolean = false) {
        val env = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }
        val store: MemoryStore = if (failingStore) FailingStore() else MemoryStore()
        var pdfLines: List<DossierLine> = emptyList()
        var renderCalls = 0
        val vm = HandoverViewModel(
            env.vehicles, env.entries, env.reminders, DemoFunctionsGateway(env.store), store, env.purchases.entitlement,
            renderPdf = { lines, out ->
                renderCalls++
                if (failingRenderer) throw IllegalStateException("render blew up")
                pdfLines = lines; out.write("rendered-by-fake".toByteArray()); 1
            },
            clock = { env.now },
            zone = java.time.ZoneOffset.UTC,
            io = UnconfinedTestDispatcher(),
        )
    }

    @Test
    fun summarisesActiveVehicle() = runTest {
        val h = Harness()
        val s = h.vm.state.value
        assertEquals("Daily SQ5", s.vehicle?.displayName)
        assertTrue(s.entryCount > 0)
        assertEquals(SeedData.SQ5_ID, s.vehicle?.id)
    }

    @Test
    fun csvExportHasHeaderAndRowPerEntry() = runTest {
        val h = Harness()
        h.vm.exportCsv()
        val f = h.vm.state.value.pendingShare!!
        assertEquals("text/csv", f.mimeType)
        assertEquals("garage-daily-sq5-entries-2026-01-01.csv", f.fileName)
        val csv = String(h.store.files.getValue(f.fileName))
        assertEquals(h.vm.state.value.entryCount + 1, csv.trim().lines().size)
        h.vm.shareHandled()
        assertNull(h.vm.state.value.pendingShare)
    }

    @Test
    fun pdfExportRendersDossierLines() = runTest {
        val h = Harness()
        h.vm.setIncludeRecalls(false)
        h.vm.exportPdf()
        val f = h.vm.state.value.pendingShare!!
        assertEquals("application/pdf", f.mimeType)
        // The VM hands the renderer's output to the store verbatim (the real PDF bytes are covered by PdfExporterTest).
        assertEquals("rendered-by-fake", String(h.store.files.getValue(f.fileName)))
        assertEquals("garage-daily-sq5-dossier-2026-01-01.pdf", f.fileName)
        assertEquals(1, h.renderCalls)
        assertTrue(h.pdfLines.any { it.text.contains("Audi") })
    }

    @Test
    fun pdfIsAProFeatureButCsvAndIcsStayFree() = runTest {
        val h = Harness()
        h.env.purchases.setPro(false)
        assertFalse(h.vm.state.value.isPro)
        h.vm.exportPdf()
        assertNull(h.vm.state.value.pendingShare)
        assertTrue(h.vm.state.value.error!!.contains("Pro"))
        assertTrue(h.pdfLines.isEmpty())

        h.vm.exportCsv()
        assertNotNull(h.vm.state.value.pendingShare)
        h.vm.shareHandled()
        h.vm.exportIcs()
        assertNotNull(h.vm.state.value.pendingShare)

        h.env.purchases.setPro(true)
        h.vm.shareHandled()
        h.vm.exportPdf()
        assertEquals("application/pdf", h.vm.state.value.pendingShare!!.mimeType)
    }

    @Test
    fun sectionsAndDateRangeShapeTheDossier() = runTest {
        val h = Harness()
        h.vm.setSection(com.writes.garage.core.model.ReportSection.COST_SUMMARY, false)
        h.vm.setSection(com.writes.garage.core.model.ReportSection.RECALLS, false)
        h.vm.setStartDate(java.time.LocalDate.of(2025, 11, 1))
        h.vm.exportPdf()
        val text = h.pdfLines.map { it.text }
        assertFalse(text.contains("Cost summary"))
        assertTrue(text.any { it.startsWith("Records from 2025-11-01") })
        assertTrue(text.contains("Oil changes & analysis")) // logged 45 days before the frozen clock
        assertFalse(text.contains("Brake history")) // 150 days before: outside the range
        h.vm.shareHandled()
        h.vm.setEndDate(java.time.LocalDate.of(2025, 10, 1))
        h.vm.exportPdf()
        assertTrue(h.vm.state.value.error!!.contains("end date"))
    }

    @Test
    fun icsExportContainsOutstandingDatedReminders() = runTest {
        val h = Harness()
        assertTrue(h.vm.state.value.datedReminderCount > 0)
        h.vm.exportIcs()
        val f = h.vm.state.value.pendingShare!!
        assertEquals("text/calendar", f.mimeType)
        val ics = String(h.store.files.getValue(f.fileName))
        assertTrue(ics.startsWith("BEGIN:VCALENDAR"))
        assertTrue(ics.contains("SUMMARY:Oil change"))
        assertTrue(ics.contains("SUMMARY:Rotate tires"))
        // The completed seed reminder must not be exported, and only this vehicle's two outstanding ones are.
        assertFalse(ics.contains("Cabin filter"))
        assertEquals(2, Regex("BEGIN:VEVENT").findAll(ics).count())
        assertEquals(h.vm.state.value.datedReminderCount, Regex("BEGIN:VEVENT").findAll(ics).count())
    }

    // ---- failure paths (T10)

    @Test
    fun csvWriterFailureSetsErrorAndClearsBusy() = runTest {
        val h = Harness(failingStore = true)
        h.vm.exportCsv()
        val s = h.vm.state.value
        assertEquals("No space left on device", s.error)
        assertFalse(s.busy)
        assertNull(s.pendingShare)
        assertNull(s.message)
        // A failure must not wedge the screen: the next export is accepted.
        h.vm.exportIcs()
        assertEquals("No space left on device", h.vm.state.value.error)
    }

    @Test
    fun pdfRendererFailureSetsErrorAndClearsBusy() = runTest {
        val h = Harness(failingRenderer = true)
        h.vm.exportPdf()
        val s = h.vm.state.value
        assertEquals("render blew up", s.error)
        assertFalse(s.busy)
        assertNull(s.pendingShare)
    }

    @Test
    fun icsWithNoDatedRemindersReportsAClearError() = runTest {
        val h = Harness()
        h.env.store.reminders.value = emptyList()
        h.vm.exportIcs()
        assertEquals("No upcoming reminders with a due date to export.", h.vm.state.value.error)
        assertNull(h.vm.state.value.pendingShare)
    }

    @Test
    fun noVehicleReportsError() = runTest {
        val h = Harness()
        h.env.store.vehicles.value = emptyList()
        h.vm.exportPdf()
        assertNotNull(h.vm.state.value.error)
        assertNull(h.vm.state.value.pendingShare)
    }

    @Test
    fun fileNameSlugifiesVehicle() {
        val v = com.writes.garage.TestFixtures.vehicle().copy(nickname = "My  Car!!")
        assertEquals(
            "garage-my-car-dossier-2026-02-03.pdf",
            HandoverViewModel.fileName(v, "dossier", "pdf", java.time.Instant.parse("2026-02-03T10:00:00Z")),
        )
    }
}
