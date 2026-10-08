package com.writes.garage.core.export

import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import com.writes.garage.core.data.firebase.BoundedRead
import java.io.OutputStream

/**
 * Where pages are drawn. The platform implementation wraps `android.graphics.pdf.PdfDocument`, which has no JVM/Robolectric
 * implementation, so tests supply their own sink to exercise the real layout (wrap + pagination) code.
 */
internal interface PdfPageSink {
    fun startPage(number: Int, width: Int, height: Int): Canvas

    fun finishPage()

    fun writeTo(out: OutputStream)

    fun close()
}

private class PlatformPdfSink : PdfPageSink {
    private val doc = PdfDocument()
    private var page: PdfDocument.Page? = null

    override fun startPage(number: Int, width: Int, height: Int): Canvas =
        doc.startPage(PdfDocument.PageInfo.Builder(width, height, number).create()).also { page = it }.canvas

    override fun finishPage() {
        page?.let { doc.finishPage(it) }
        page = null
    }

    override fun writeTo(out: OutputStream) = doc.writeTo(out)

    override fun close() = doc.close()
}

/** Renders [DossierLine]s onto US-Letter pages with `android.graphics.pdf.PdfDocument` (no third-party PDF lib). */
object PdfExporter {
    private const val PAGE_WIDTH = 612
    private const val PAGE_HEIGHT = 792
    private const val MARGIN = 48f
    private const val IMAGE_MAX_WIDTH = 300f
    private const val IMAGE_MAX_HEIGHT = 220f

    private data class Style(val size: Float, val bold: Boolean, val gapBefore: Float, val gray: Int)

    private fun style(s: DossierLineStyle) = when (s) {
        DossierLineStyle.TITLE -> Style(24f, true, 0f, 0xFF111111.toInt())
        DossierLineStyle.HEADING -> Style(15f, true, 14f, 0xFF111111.toInt())
        DossierLineStyle.BODY -> Style(11f, false, 3f, 0xFF222222.toInt())
        DossierLineStyle.CAPTION -> Style(9.5f, false, 1f, 0xFF666666.toInt())
        DossierLineStyle.IMAGE -> Style(9.5f, false, 6f, 0xFF666666.toInt())
    }

    /** Writes a multi-page PDF to [out]; the caller owns (and closes) the stream. Returns the page count. */
    fun write(lines: List<DossierLine>, out: OutputStream): Int = write(lines, out, PlatformPdfSink())

    internal fun write(lines: List<DossierLine>, out: OutputStream, sink: PdfPageSink): Int {
        var pageNumber = 0
        var canvas: Canvas? = null
        var y = MARGIN
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        fun newPage() {
            if (canvas != null) sink.finishPage()
            pageNumber++
            canvas = sink.startPage(pageNumber, PAGE_WIDTH, PAGE_HEIGHT)
            y = MARGIN
        }

        newPage()
        val maxWidth = PAGE_WIDTH - 2 * MARGIN
        for (line in lines) {
            if (line.style == DossierLineStyle.IMAGE) {
                val bitmap = line.image?.let { decodeSampled(it) }
                if (bitmap != null) {
                    val scale = minOf(IMAGE_MAX_WIDTH / bitmap.width, IMAGE_MAX_HEIGHT / bitmap.height, 1f)
                    val w = bitmap.width * scale
                    val h = bitmap.height * scale
                    if (y + h + 24f > PAGE_HEIGHT - MARGIN && y > MARGIN) newPage()
                    y += 6f
                    canvas!!.drawBitmap(bitmap, null, RectF(MARGIN, y, MARGIN + w, y + h), paint)
                    y += h
                    bitmap.recycle()
                    if (line.text.isNotBlank()) {
                        paint.textSize = 9.5f
                        paint.typeface = Typeface.DEFAULT
                        paint.color = 0xFF666666.toInt()
                        y += 12f
                        canvas!!.drawText(line.text.take(90), MARGIN, y, paint)
                    }
                } else if (line.text.isNotBlank()) {
                    // The photo couldn't be fetched/decoded: keep its caption so the section is still truthful.
                    paint.textSize = 11f
                    paint.typeface = Typeface.DEFAULT
                    paint.color = 0xFF222222.toInt()
                    if (y + 20f > PAGE_HEIGHT - MARGIN && y > MARGIN) newPage()
                    y += 16f
                    canvas!!.drawText(line.text.take(90), MARGIN, y, paint)
                }
                continue
            }
            val st = style(line.style)
            paint.textSize = st.size
            paint.typeface = if (st.bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            paint.color = st.gray
            val lineHeight = st.size * 1.3f
            val wrapped = wrap(line.text, paint, maxWidth)
            val needed = st.gapBefore + lineHeight * wrapped.size
            if (y + needed > PAGE_HEIGHT - MARGIN && y > MARGIN) newPage()
            y += st.gapBefore
            for (w in wrapped) {
                y += lineHeight
                canvas!!.drawText(w, MARGIN, y - st.size * 0.3f, paint)
            }
        }
        if (canvas != null) sink.finishPage()
        try {
            sink.writeTo(out)
        } finally {
            sink.close()
        }
        return pageNumber
    }

    /** Decodes near the size it is drawn at (a multi-megapixel photo must not land in memory whole). */
    private fun decodeSampled(bytes: ByteArray, maxEdge: Int = 900) = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val sample = BoundedRead.sampleSize(bounds.outWidth, bounds.outHeight, maxEdge)
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }.getOrNull()

    private fun wrap(text: String, paint: Paint, maxWidth: Float): List<String> =
        wrapText(text, maxWidth) { rest, width -> paint.breakText(rest, true, width, null) }

    /**
     * Greedy word-wrap. [fit] returns how many leading characters of its argument fit in the given width
     * (`Paint.breakText`); the rest of the algorithm is pure so page-break/wrap edge cases are unit-testable.
     * Always makes progress (an unbreakable token is hard-cut), so a pathological line cannot loop.
     */
    internal fun wrapText(text: String, maxWidth: Float, fit: (String, Float) -> Int): List<String> {
        val out = mutableListOf<String>()
        for (paragraph in text.split('\n')) {
            var rest = paragraph
            if (rest.isEmpty()) {
                out += ""
                continue
            }
            while (rest.isNotEmpty()) {
                val count = fit(rest, maxWidth)
                if (count >= rest.length) {
                    out += rest
                    break
                }
                // Prefer breaking at the last space inside the fitting prefix.
                val space = rest.lastIndexOf(' ', count - 1)
                val cut = if (space > 0) space else count.coerceAtLeast(1)
                out += rest.substring(0, cut).trimEnd()
                rest = rest.substring(cut).trimStart()
            }
        }
        return out
    }
}
