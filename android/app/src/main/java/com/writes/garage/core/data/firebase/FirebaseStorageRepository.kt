package com.writes.garage.core.data.firebase

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.ExifInterface
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.domain.Constants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
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
        val uri = Uri.parse(localUri)
        val size = withContext(Dispatchers.IO) {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1L
        }
        require(size < 0 || size <= Constants.MAX_ATTACHMENT_BYTES) { "That file is larger than 20 MB." }

        val path = StoragePaths.entryAttachment(
            uid, vehicleId, entryId ?: UUID.randomUUID().toString(),
            "${UUID.randomUUID()}.${StoragePaths.extensionFor(contentType)}",
        )
        val metadata = StorageMetadata.Builder().setContentType(contentType).build()
        storage.reference.child(path).putFile(uri, metadata).await()
        return path
    }

    override suspend fun deleteAttachment(storagePath: String) {
        storage.reference.child(storagePath).delete().await()
    }

    override suspend fun readAsBase64(localUri: String, contentType: String): String = withContext(Dispatchers.IO) {
        val uri = Uri.parse(localUri)
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: error("Couldn't read that file.")
        val payload = if (contentType.startsWith("image/")) downscaleJpeg(bytes) else bytes
        Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    /** Camera JPEGs carry orientation in EXIF, which re-encoding drops; bake it into the pixels first. */
    private fun applyExifRotation(bitmap: Bitmap, original: ByteArray): Bitmap {
        val orientation = runCatching {
            ExifInterface(ByteArrayInputStream(original))
                .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.postRotate(90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.postRotate(270f); m.postScale(-1f, 1f) }
            else -> return bitmap
        }
        return runCatching { Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true) }.getOrDefault(bitmap)
    }

    /** Receipts are text; 1600 px on the long edge at JPEG q80 keeps them readable and well under the 9 MiB callable cap. */
    private fun downscaleJpeg(bytes: ByteArray, maxEdge: Int = 1600): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0) return bytes
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxEdge || bounds.outHeight / (sample * 2) >= maxEdge) sample *= 2
        val sampled = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return bytes
        val decoded = applyExifRotation(sampled, bytes)
        val scale = maxEdge.toFloat() / maxOf(decoded.width, decoded.height)
        val bitmap = if (scale < 1f) {
            Bitmap.createScaledBitmap(decoded, (decoded.width * scale).toInt(), (decoded.height * scale).toInt(), true)
        } else {
            decoded
        }
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
    }
}
