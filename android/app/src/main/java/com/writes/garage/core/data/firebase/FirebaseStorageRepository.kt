package com.writes.garage.core.data.firebase

import android.content.Context
import android.net.Uri
import android.util.Base64
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.MediaFolder
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.domain.Constants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.util.UUID

/**
 * Attachments under `users/{uid}/entry-attachments/{vehicleId}/{entryId}/{uuid}.{ext}` (owner-only, < 25 MB,
 * `image/…` or `application/pdf` per `firebase.storage.rules`; client cap is [Constants.MAX_ATTACHMENT_BYTES]).
 */
class FirebaseStorageRepository(
    private val context: Context,
    private val auth: AuthRepository,
    private val storage: FirebaseStorage = FirebaseStorage.getInstance(),
) : StorageRepository {

    override suspend fun uploadAttachment(vehicleId: String, localUri: String, contentType: String, entryId: String?): String {
        require(StoragePaths.isAllowedContentType(contentType)) { "Only images and PDFs can be attached." }
        val uid = auth.currentUser.value?.uid ?: error("Not signed in")
        val raw = readBoundedBytes(Uri.parse(localUri))
        // Images are re-encoded (EXIF rotation baked in, all metadata incl. GPS dropped), like iOS AttachmentImageProcessor.
        val isImage = contentType.startsWith("image/")
        val bytes = if (isImage) ImageReencoder.reencodeJpeg(raw, UPLOAD_MAX_EDGE, UPLOAD_JPEG_QUALITY) else raw
        val effectiveType = if (isImage) "image/jpeg" else contentType

        val path = StoragePaths.entryAttachment(
            uid, vehicleId, entryId ?: UUID.randomUUID().toString(),
            "${UUID.randomUUID()}.${StoragePaths.extensionFor(effectiveType)}",
        )
        val metadata = StorageMetadata.Builder().setContentType(effectiveType).build()
        storage.reference.child(path).putBytes(bytes, metadata).await()
        return path
    }

    override suspend fun uploadMedia(
        vehicleId: String,
        localUri: String,
        contentType: String,
        folder: MediaFolder,
        ownerId: String?,
    ): String {
        require(StoragePaths.isAllowedContentType(contentType)) { "Only images and PDFs can be attached." }
        val uid = auth.currentUser.value?.uid ?: error("Not signed in")
        val raw = readBoundedBytes(Uri.parse(localUri))
        val isImage = contentType.startsWith("image/")
        val bytes = if (isImage) ImageReencoder.reencodeJpeg(raw, UPLOAD_MAX_EDGE, UPLOAD_JPEG_QUALITY) else raw
        val effectiveType = if (isImage) "image/jpeg" else contentType
        val path = StoragePaths.media(uid, vehicleId, folder, ownerId, "${UUID.randomUUID()}.${StoragePaths.extensionFor(effectiveType)}")
        storage.reference.child(path).putBytes(bytes, StorageMetadata.Builder().setContentType(effectiveType).build()).await()
        return path
    }

    override suspend fun deleteAttachment(storagePath: String) {
        storage.reference.child(storagePath).delete().await()
    }

    override suspend fun downloadAttachment(storagePath: String, maxBytes: Int): ByteArray = try {
        storage.reference.child(storagePath).getBytes(maxBytes.toLong()).await()
    } catch (e: com.google.firebase.storage.StorageException) {
        if (e.errorCode == com.google.firebase.storage.StorageException.ERROR_OBJECT_NOT_FOUND) {
            throw com.writes.garage.core.data.AttachmentMissingException(storagePath)
        }
        throw e
    }

    override suspend fun readBytes(localUri: String, maxBytes: Int): ByteArray = withContext(Dispatchers.IO) {
        val stream = context.contentResolver.openInputStream(Uri.parse(localUri)) ?: error("Couldn't read that file.")
        try {
            stream.use { BoundedRead.readBounded(it, maxBytes) }
        } catch (e: BoundedRead.TooLargeException) {
            throw IllegalArgumentException("That file is too large.", e)
        }
    }

    override suspend fun readAsBase64(localUri: String, contentType: String): String = withContext(Dispatchers.IO) {
        val bytes = readBoundedBytes(Uri.parse(localUri))
        val payload = if (contentType.startsWith("image/")) ImageReencoder.reencodeJpeg(bytes, AI_MAX_EDGE, 80) else bytes
        Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    /** Never reads past the cap, whether or not the provider reports a length. */
    private suspend fun readBoundedBytes(uri: Uri): ByteArray = withContext(Dispatchers.IO) {
        val stream = context.contentResolver.openInputStream(uri) ?: error("Couldn't read that file.")
        try {
            stream.use { BoundedRead.readBounded(it, Constants.MAX_ATTACHMENT_BYTES) }
        } catch (e: BoundedRead.TooLargeException) {
            throw IllegalArgumentException("That file is larger than 20 MB.", e)
        }
    }

    private companion object {
        /** Receipts are text; 1600 px keeps them readable and well under the 9 MiB callable cap. */
        const val AI_MAX_EDGE = 1600
        const val UPLOAD_MAX_EDGE = 2560
        const val UPLOAD_JPEG_QUALITY = 85
    }
}
