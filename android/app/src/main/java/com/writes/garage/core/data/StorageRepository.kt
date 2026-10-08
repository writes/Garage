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

    suspend fun deleteAttachment(storagePath: String)

    /** Reads a local content/file URI as base64 (images are downscaled) for the AI callables. */
    suspend fun readAsBase64(localUri: String, contentType: String): String
}
