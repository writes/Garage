package com.writes.garage.feature

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.writes.garage.feature.handover.CacheExportFileStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class ExportFileStoreTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    /** FileProvider memoises its path roots statically; Robolectric gives every test a fresh cache dir. */
    @Before
    fun resetFileProviderCache() {
        val f = androidx.core.content.FileProvider::class.java.getDeclaredField("sCache")
        f.isAccessible = true
        (f.get(null) as MutableMap<*, *>).clear()
    }
    private val dir get() = File(context.cacheDir, "exports")

    @Test
    fun writesTheBytesAndReturnsAFileProviderUri() {
        val store = CacheExportFileStore(context)
        val out = store.write("Garage-SQ5.csv", "text/csv") { it.write("a,b\n1,2\n".toByteArray()) }
        assertEquals("Garage-SQ5.csv", out.fileName)
        assertEquals("text/csv", out.mimeType)
        assertTrue(out.uri, out.uri.startsWith("content://"))
        assertTrue(out.uri.endsWith("Garage-SQ5.csv"))
        assertEquals("a,b\n1,2\n", File(dir, "Garage-SQ5.csv").readText())
    }

    @Test
    fun aNewExportDeletesThePreviousOneBecauseItHoldsPersonalData() {
        val store = CacheExportFileStore(context)
        store.write("old.pdf", "application/pdf") { it.write(1) }
        store.write("older.csv", "text/csv") { it.write(2) }
        store.write("new.pdf", "application/pdf") { it.write(3) }
        assertEquals(listOf("new.pdf"), dir.list()!!.toList())
        assertFalse(File(dir, "old.pdf").exists())
    }

    @Test
    fun aWriterThatThrowsPropagatesAndLeavesNoShareableFileUri() {
        val store = CacheExportFileStore(context)
        try {
            store.write("x.pdf", "application/pdf") { throw java.io.IOException("disk full") }
            org.junit.Assert.fail("expected failure")
        } catch (e: java.io.IOException) {
            assertEquals("disk full", e.message)
        }
    }
}
