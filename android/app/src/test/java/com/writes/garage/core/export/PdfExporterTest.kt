package com.writes.garage.core.export

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode
import java.io.ByteArrayOutputStream
import java.io.OutputStream

/**
 * `android.graphics.pdf.PdfDocument` has no Robolectric implementation, so these tests drive the real layout
 * (wrap + pagination) through a recording [PdfPageSink] over a real (native-graphics) Canvas. The `%PDF` header of
 * the platform writer can only be asserted in an instrumented test.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PdfExporterTest {
    private data class Drawn(val page: Int, val text: String, val y: Float)

    private class RecordingSink : PdfPageSink {
        val drawn = mutableListOf<Drawn>()
        var started = 0
        var finished = 0
        var written = false
        var closed = false
        private var current = 0

        override fun startPage(number: Int, width: Int, height: Int): Canvas {
            started++
            current = number
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            return object : Canvas(bitmap) {
                override fun drawText(text: String, x: Float, y: Float, paint: Paint) {
                    drawn += Drawn(current, text, y)
                }
            }
        }

        override fun finishPage() { finished++ }

        override fun writeTo(out: OutputStream) { written = true; out.write("%PDF-fake".toByteArray()) }

        override fun close() { closed = true }
    }

    private fun render(lines: List<DossierLine>): Pair<Int, RecordingSink> {
        val sink = RecordingSink()
        val pages = PdfExporter.write(lines, ByteArrayOutputStream(), sink)
        return pages to sink
    }

    private fun body(n: Int) = List(n) { DossierLine(DossierLineStyle.BODY, "Service line number $it  |  \$42.00") }

    @Test
    fun manyLinesPaginateEveryPageIsFinishedAndNothingIsLost() {
        val (pages, sink) = render(body(500))
        assertTrue("500 body lines cannot fit on one page, got $pages", pages >= 2)
        assertEquals(pages, sink.started)
        assertEquals("every started page is finished", sink.started, sink.finished)
        assertTrue(sink.written && sink.closed)
        // All 500 lines are drawn exactly once, in order.
        val texts = sink.drawn.map { it.text }
        assertEquals(500, texts.size)
        assertEquals("Service line number 0  |  \$42.00", texts.first())
        assertEquals("Service line number 499  |  \$42.00", texts.last())
        // No text is drawn into the bottom margin (792 - 48), and pages advance monotonically.
        assertTrue(sink.drawn.all { it.y <= 792f - 48f + 1f })
        assertEquals(sink.drawn.map { it.page }, sink.drawn.map { it.page }.sorted())
        assertEquals(pages, sink.drawn.last().page)
    }

    @Test
    fun emptyDossierIsOneBlankPage() {
        val (pages, sink) = render(emptyList())
        assertEquals(1, pages)
        assertEquals(1, sink.finished)
        assertTrue(sink.drawn.isEmpty())
    }

    @Test
    fun aFewLinesStayOnOnePage() {
        val (pages, _) = render(listOf(DossierLine(DossierLineStyle.TITLE, "2015 Audi SQ5")) + body(10))
        assertEquals(1, pages)
    }

    @Test
    fun aVeryLongUnbrokenTokenIsHardWrappedAndTerminates() {
        val token = "x".repeat(5_000)
        val (pages, sink) = render(listOf(DossierLine(DossierLineStyle.BODY, token)))
        assertTrue(pages >= 1)
        assertTrue("a 5,000-char token must wrap onto several lines", sink.drawn.size > 1)
        assertEquals("no characters are dropped by wrapping", token, sink.drawn.joinToString("") { it.text })
    }

    @Test
    fun longTextWrapsAtSpacesWithoutLosingWords() {
        val sentence = List(80) { "word$it" }.joinToString(" ")
        val (_, sink) = render(listOf(DossierLine(DossierLineStyle.CAPTION, sentence)))
        assertTrue(sink.drawn.size > 1)
        assertEquals(sentence, sink.drawn.joinToString(" ") { it.text })
    }

    @Test
    fun blankAndNewlineOnlyLinesAreAccepted() {
        val (pages, sink) = render(
            listOf(
                DossierLine(DossierLineStyle.BODY, ""),
                DossierLine(DossierLineStyle.CAPTION, "\n\n"),
                DossierLine(DossierLineStyle.HEADING, "Heading"),
            ),
        )
        assertEquals(1, pages)
        assertTrue(sink.drawn.any { it.text == "Heading" })
    }

    @Test
    fun headingNeverStrandsAtThePageBottomWithoutRoomForItself() {
        // Fill a page nearly to the margin, then add a heading: it must start the next page rather than overflow.
        val (_, sink) = render(body(52) + DossierLine(DossierLineStyle.HEADING, "Recalls"))
        val heading = sink.drawn.first { it.text == "Recalls" }
        assertTrue(heading.y <= 792f - 48f + 1f)
    }

    @Test
    fun undecodableImageFallsBackToItsCaptionAndIsNotDropped() {
        val (pages, sink) = render(
            listOf(
                DossierLine(DossierLineStyle.IMAGE, "Front quarter", image = byteArrayOf(1, 2, 3)),
                DossierLine(DossierLineStyle.IMAGE, "No bytes"),
                DossierLine(DossierLineStyle.IMAGE, ""),
            ),
        )
        assertEquals(1, pages)
        assertEquals(listOf("Front quarter", "No bytes"), sink.drawn.map { it.text })
    }

    @Test
    fun theSinkIsClosedEvenWhenWritingFails() {
        val sink = object : PdfPageSink {
            val inner = RecordingSink()
            override fun startPage(number: Int, width: Int, height: Int) = inner.startPage(number, width, height)
            override fun finishPage() = inner.finishPage()
            override fun writeTo(out: OutputStream) = throw java.io.IOException("disk full")
            override fun close() = inner.close()
        }
        try {
            PdfExporter.write(body(3), ByteArrayOutputStream(), sink)
            org.junit.Assert.fail("expected the write failure to propagate")
        } catch (e: java.io.IOException) {
            assertEquals("disk full", e.message)
        }
        assertTrue(sink.inner.closed)
        assertFalse(sink.inner.drawn.isEmpty())
    }

    // ---- pure wrap (no Android): measure = one unit per character

    private fun wrap(text: String, width: Int, fit: (String, Float) -> Int = { s, w -> minOf(s.length, w.toInt()) }) =
        PdfExporter.wrapText(text, width.toFloat(), fit)

    @Test
    fun wrapBreaksAtSpacesWithinWidth() {
        assertEquals(listOf("aaa bbb", "ccc"), wrap("aaa bbb ccc", 8))
        assertEquals(listOf("short"), wrap("short", 40))
    }

    @Test
    fun wrapHardCutsAnUnbreakableToken() {
        assertEquals(listOf("abcd", "efgh", "ij"), wrap("abcdefghij", 4))
    }

    @Test
    fun wrapKeepsBlankParagraphsAndSplitsOnNewlines() {
        assertEquals(listOf("a", "", "b"), wrap("a\n\nb", 10))
    }

    @Test
    fun wrapAlwaysTerminatesEvenWhenNothingFits() {
        // A measure that claims zero characters fit must still advance one character at a time.
        val lines = wrap("abc", 1) { _, _ -> 0 }
        assertEquals(listOf("a", "b", "c"), lines)
    }

    @Test
    fun wrapHandlesFiveThousandCharacterTokenQuickly() {
        val lines = wrap("y".repeat(5_000), 100)
        assertEquals(50, lines.size)
        assertTrue(lines.all { it.length == 100 })
    }

    @Test
    fun wrapDropsTheSpaceItBreaksOn() {
        val lines = wrap("one two three four", 9)
        assertTrue(lines.toString(), lines.none { it.startsWith(" ") || it.endsWith(" ") })
        assertEquals("one two three four", lines.joinToString(" "))
    }
}
