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

    private class MemoryStore : ExportFileStore {
        val files = mutableMapOf<String, ByteArray>()

        override fun write(fileName: String, mimeType: String, writer: (OutputStream) -> Unit): ExportedFile {
            val out = ByteArrayOutputStream().also(writer)
            files[fileName] = out.toByteArray()
            return ExportedFile(fileName, mimeType, "content://test/$fileName")
        }
    }

    private class Harness {
        val env = DemoEnv().also { it.store.activeVehicleId.value = SeedData.SQ5_ID }
        val store = MemoryStore()
        var pdfLines: List<DossierLine> = emptyList()
        val vm = HandoverViewModel(
            env.vehicles, env.entries, env.reminders, DemoFunctionsGateway(env.store), store,
            renderPdf = { lines, out -> pdfLines = lines; out.write("%PDF-fake".toByteArray()); 1 },
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
        assertTrue(String(h.store.files.getValue(f.fileName)).startsWith("%PDF"))
        assertTrue(h.pdfLines.any { it.text.contains("Audi") })
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
