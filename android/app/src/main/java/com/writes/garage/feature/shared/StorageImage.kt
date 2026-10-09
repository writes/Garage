package com.writes.garage.feature.shared

import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.firebase.BoundedRead
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private object ThumbCache {
    // ~12 MB of thumbnails; entries are keyed by Storage path (immutable uuid names, so never stale).
    val cache = object : LruCache<String, ImageBitmap>(12 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ImageBitmap) = value.width * value.height * 4
    }
}

/** Downloads (once, cached) and decodes a downscaled preview of a Storage image. Null while loading or on failure. */
@Composable
fun rememberStorageBitmap(storage: StorageRepository, path: String?, maxEdge: Int = 800): ImageBitmap? {
    var bitmap by remember(path) { mutableStateOf(path?.let { ThumbCache.cache.get(it) }) }
    LaunchedEffect(path) {
        if (path != null && bitmap == null) {
            bitmap = runCatching {
                withContext(Dispatchers.IO) {
                    val bytes = storage.downloadAttachment(path)
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    val sample = BoundedRead.sampleSize(bounds.outWidth, bounds.outHeight, maxEdge)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
                        ?.asImageBitmap()
                }
            }.getOrNull()?.also { ThumbCache.cache.put(path, it) }
        }
    }
    return bitmap
}

/** A fixed-height photo from Storage with a text placeholder while it loads or if it can't be loaded. */
@Composable
fun StorageImage(storage: StorageRepository, path: String?, modifier: Modifier = Modifier, height: Dp = 160.dp) {
    val bitmap = rememberStorageBitmap(storage, path)
    if (bitmap != null) {
        Image(bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier.fillMaxWidth().height(height))
    } else {
        Box(modifier.fillMaxWidth().height(height), contentAlignment = Alignment.Center) {
            Text("Photo unavailable", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
