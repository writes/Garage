package com.writes.garage.core.domain

/** What an entry attachment is, from its Storage path (`…/{uuid}.pdf|jpg|png|…`). */
enum class AttachmentKind {
    IMAGE,
    PDF;

    companion object {
        fun fromPath(path: String): AttachmentKind = if (path.lowercase().endsWith(".pdf")) PDF else IMAGE

        fun fromMime(mime: String): AttachmentKind = if (mime == "application/pdf") PDF else IMAGE
    }
}

object AttachmentRules {
    /** A sane cap on attachments queued in one form (the per-file cap is [Constants.MAX_ATTACHMENT_BYTES]). */
    const val MAX_PER_ENTRY = 10

    fun canAddMore(existing: Int, pending: Int): Boolean = existing + pending < MAX_PER_ENTRY

    fun isAllowedMime(mime: String): Boolean = mime == "application/pdf" || (mime.startsWith("image/") && mime.length > 6)
}
