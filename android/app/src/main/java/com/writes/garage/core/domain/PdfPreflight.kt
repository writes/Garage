package com.writes.garage.core.domain

import java.util.Base64

/**
 * Local checks before a PDF is sent to an AI callable (port of iOS `OilAnalysisPDFPreflighter`): the callable body is
 * capped at 10 MiB, so the base64 payload stays under 9 MiB; and a file that isn't a PDF is refused before any upload.
 */
object PdfPreflight {
    /** Base64 ceiling that leaves JSON-envelope headroom below Firebase's 10 MiB request limit. */
    const val MAX_BASE64_BYTES = 9 * 1024 * 1024

    /** 3 * floor(MAX_BASE64_BYTES / 4) = 7,077,888 raw bytes. */
    const val MAX_RAW_BYTES = 3 * (MAX_BASE64_BYTES / 4)

    /** Best-effort page ceiling (counted from the page objects); the server is the authority on content. */
    const val MAX_PAGES = 12

    sealed interface Result {
        class Ok(val base64: String, val pages: Int?) : Result

        data class Rejected(val message: String) : Result
    }

    fun check(bytes: ByteArray, maxPages: Int = MAX_PAGES): Result {
        if (bytes.isEmpty()) return Result.Rejected("That file is empty.")
        if (bytes.size > MAX_RAW_BYTES) return Result.Rejected("That PDF is too large. Choose one under 7 MB.")
        if (!hasPdfSignature(bytes)) return Result.Rejected("Choose a valid PDF.")
        val pages = pageCount(bytes)
        if (pages != null && pages > maxPages) return Result.Rejected("That PDF has $pages pages. Choose one with at most $maxPages.")
        return Result.Ok(Base64.getEncoder().encodeToString(bytes), pages)
    }

    /** `%PDF-` within the first 1 KiB (some producers prepend junk). */
    fun hasPdfSignature(bytes: ByteArray): Boolean {
        val head = String(bytes, 0, minOf(bytes.size, 1024), Charsets.ISO_8859_1)
        return head.contains("%PDF-")
    }

    /**
     * Counts `/Type /Page` objects (not `/Pages`). Null when none are found in plain text (compressed object streams),
     * so an unknown count never blocks a valid file.
     */
    fun pageCount(bytes: ByteArray): Int? {
        val text = String(bytes, Charsets.ISO_8859_1)
        val n = PAGE_OBJECT.findAll(text).count()
        return n.takeIf { it > 0 }
    }

    private val PAGE_OBJECT = Regex("/Type\\s*/Page(?![A-Za-z])")
}
