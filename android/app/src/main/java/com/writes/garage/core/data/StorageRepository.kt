package com.writes.garage.core.data

interface StorageRepository {
    /**
     * Uploads a local file (content/file URI string) and returns its storage path
     * (`users/{uid}/entry-attachments/{vehicleId}/{entryId}/{uuid}.{ext}`).
     * Size is capped by `Constants.MAX_ATTACHMENT_BYTES` (storage rules ceiling is 25 MB);
     * only `image/…` and `application/pdf` are accepted (storage rules).
     */
    suspend fun uploadAttachment(
        vehicleId: String,
        localUri: String,
        contentType: String,
        entryId: String? = null,
    ): String

    /**
     * Uploads a gallery photo, spare-part photo or spare-part receipt (image/PDF per [folder]) under
     * `users/{uid}/vehicles/{vehicleId}/…` and returns the storage path. Images are re-encoded (metadata stripped).
     */
    suspend fun uploadMedia(vehicleId: String, localUri: String, contentType: String, folder: MediaFolder, ownerId: String? = null): String

    suspend fun deleteAttachment(storagePath: String)

    /** Downloads an attachment (capped by [maxBytes]). Throws [AttachmentMissingException] when the object is gone. */
    suspend fun downloadAttachment(storagePath: String, maxBytes: Int = 15 * 1024 * 1024): ByteArray

    /** Reads a local content/file URI as raw bytes, failing once it exceeds [maxBytes] (even when the length is unknown). */
    suspend fun readBytes(localUri: String, maxBytes: Int): ByteArray

    /** Reads a local content/file URI as base64 (images are downscaled) for the AI callables. */
    suspend fun readAsBase64(localUri: String, contentType: String): String
}

/** The Storage object no longer exists (e.g. the server removed a free user's upload). */
class AttachmentMissingException(path: String) : Exception("The attachment $path is no longer available.")

/** Where non-entry media lives (iOS `StoragePaths.gallery / photo / receipt`). */
enum class MediaFolder(val segment: String) {
    GALLERY("gallery"),
    PHOTOS("photos"),
    RECEIPTS("receipts"),
}
