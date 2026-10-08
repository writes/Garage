package com.writes.garage.core.domain

import com.writes.garage.core.data.firebase.BoundedRead
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream

class PdfPreflightTest {
    private fun pdf(pages: Int) = ("%PDF-1.4\n" + "1 0 obj << /Type /Pages >> endobj\n" + (1..pages).joinToString("") { "<< /Type /Page >>\n" } + "%%EOF").toByteArray()

    @Test
    fun acceptsAPdfAndEncodesBase64() {
        val r = PdfPreflight.check(pdf(2)) as PdfPreflight.Result.Ok
        assertEquals(2, r.pages)
        assertTrue(java.util.Base64.getDecoder().decode(r.base64).decodeToString().startsWith("%PDF"))
    }

    @Test
    fun rejectsEmptyOversizeNonPdfAndTooManyPages() {
        assertTrue(PdfPreflight.check(ByteArray(0)) is PdfPreflight.Result.Rejected)
        assertTrue(PdfPreflight.check(ByteArray(PdfPreflight.MAX_RAW_BYTES + 1)) is PdfPreflight.Result.Rejected)
        assertEquals("Choose a valid PDF.", (PdfPreflight.check("not a pdf".toByteArray()) as PdfPreflight.Result.Rejected).message)
        assertTrue((PdfPreflight.check(pdf(40)) as PdfPreflight.Result.Rejected).message.contains("40 pages"))
    }

    @Test
    fun pageCountDoesNotConfuseThePagesNodeWithAPageAndIsNullWhenUnknown() {
        assertEquals(3, PdfPreflight.pageCount(pdf(3)))
        assertNull(PdfPreflight.pageCount("%PDF-1.7 compressed streams only".toByteArray()))
        // an unknown page count never blocks a valid file
        assertTrue(PdfPreflight.check("%PDF-1.7 compressed streams only".toByteArray()) is PdfPreflight.Result.Ok)
    }

    @Test
    fun rawLimitMatchesIos() {
        assertEquals(7_077_888, PdfPreflight.MAX_RAW_BYTES)
    }

    @Test
    fun boundedReadStopsAtTheLimitEvenWithoutAKnownLength() {
        assertEquals(10, BoundedRead.readBounded(ByteArrayInputStream(ByteArray(10)), 10).size)
        assertThrows(BoundedRead.TooLargeException::class.java) { BoundedRead.readBounded(ByteArrayInputStream(ByteArray(11)), 10) }
        // an endless stream is cut off, never read into memory
        val endless = object : java.io.InputStream() {
            override fun read(): Int = 7
            override fun read(b: ByteArray): Int = b.size.also { java.util.Arrays.fill(b, 7) }
        }
        assertThrows(BoundedRead.TooLargeException::class.java) { BoundedRead.readBounded(endless, 1_000_000) }
    }

    @Test
    fun sampleSizeKeepsTheLongEdgeAtOrAboveTarget() {
        assertEquals(1, BoundedRead.sampleSize(1_000, 800, 1_600))
        assertEquals(2, BoundedRead.sampleSize(4_000, 3_000, 1_600))
        assertEquals(4, BoundedRead.sampleSize(8_000, 6_000, 1_600))
    }
}
