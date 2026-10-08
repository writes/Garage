package com.writes.garage.core.export

import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.OutputStream

/** Renders [DossierLine]s onto US-Letter pages with `android.graphics.pdf.PdfDocument` (no third-party PDF lib). */
object PdfExporter {
    private const val PAGE_WIDTH = 612
    private const val PAGE_HEIGHT = 792
    private const val MARGIN = 48f

    private data class Style(val size: Float, val bold: Boolean, val gapBefore: Float, val gray: Int)

    private fun style(s: DossierLineStyle) = when (s) {
        DossierLineStyle.TITLE -> Style(24f, true, 0f, 0xFF111111.toInt())
        DossierLineStyle.HEADING -> Style(15f, true, 14f, 0xFF111111.toInt())
        DossierLineStyle.BODY -> Style(11f, false, 3f, 0xFF222222.toInt())
        DossierLineStyle.CAPTION -> Style(9.5f, false, 1f, 0xFF666666.toInt())
    }

    /** Writes a multi-page PDF to [out]; the caller owns (and closes) the stream. Returns the page count. */
    fun write(lines: List<DossierLine>, out: OutputStream): Int {
        val doc = PdfDocument()
        var pageNumber = 0
        var page: PdfDocument.Page? = null
        var y = MARGIN
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        fun newPage() {
            page?.let { doc.finishPage(it) }
            pageNumber++
            page = doc.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create())
            y = MARGIN
        }

        newPage()
        val maxWidth = PAGE_WIDTH - 2 * MARGIN
        for (line in lines) {
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
                page!!.canvas.drawText(w, MARGIN, y - st.size * 0.3f, paint)
            }
        }
        page?.let { doc.finishPage(it) }
        try {
            doc.writeTo(out)
        } finally {
            doc.close()
        }
        return pageNumber
    }

    private fun wrap(text: String, paint: Paint, maxWidth: Float): List<String> {
        val out = mutableListOf<String>()
        for (paragraph in text.split('\n')) {
            var rest = paragraph
            if (rest.isEmpty()) {
                out += ""
                continue
            }
            while (rest.isNotEmpty()) {
                val count = paint.breakText(rest, true, maxWidth, null)
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
