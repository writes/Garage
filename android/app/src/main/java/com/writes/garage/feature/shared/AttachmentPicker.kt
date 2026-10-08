package com.writes.garage.feature.shared

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.writes.garage.core.data.LocalFiles
import java.io.File

/** FileProvider-shared `cacheDir/capture/` for camera shots; they hold personal data, so they are deleted once used. */
object CaptureFiles {
    private fun dir(context: Context) = File(context.cacheDir, "capture").apply { mkdirs() }

    /** A fresh jpeg uri; stale captures (>1h) are swept first. */
    fun newUri(context: Context, prefix: String = "capture"): Uri {
        val d = dir(context)
        val cutoff = System.currentTimeMillis() - 60 * 60 * 1000L
        d.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
        val file = File(d, "$prefix-${System.currentTimeMillis()}.jpg")
        return FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    }

    /** Deletes the capture file behind [uri] (no-op for anything that isn't one of ours). */
    fun release(context: Context, uri: String) {
        val u = Uri.parse(uri)
        if (u.authority != "${context.packageName}.fileprovider") return
        LocalFiles.deleteNamed(dir(context), u.lastPathSegment)
    }
}

fun displayNameOf(context: Context, uri: Uri, fallback: String): String =
    runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }.getOrNull() ?: fallback

/**
 * Photo Picker + camera (+ optional PDF via the document picker). Reports `(uri, mimeType, displayName)`;
 * the caller decides what to do with it (queue for upload, scan, ...).
 */
@Composable
fun AttachmentPickerRow(
    onPicked: (uri: String, mimeType: String, displayName: String) -> Unit,
    onError: (String) -> Unit,
    modifier: Modifier = Modifier,
    allowPdf: Boolean = true,
    allowCamera: Boolean = true,
    enabled: Boolean = true,
) {
    val context = LocalContext.current
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) onPicked(uri.toString(), context.contentResolver.getType(uri) ?: "image/jpeg", displayNameOf(context, uri, "Photo"))
    }
    val pdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) onPicked(uri.toString(), "application/pdf", displayNameOf(context, uri, "document.pdf"))
    }
    var captureUri by rememberSaveable { mutableStateOf<Uri?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = captureUri
        captureUri = null
        if (ok && uri != null) onPicked(uri.toString(), "image/jpeg", "Camera photo")
    }
    fun launchCamera() {
        runCatching { CaptureFiles.newUri(context) }
            .onSuccess { captureUri = it; camera.launch(it) }
            .onFailure { onError("Couldn't start the camera.") }
    }
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchCamera() else onError("Camera permission denied. You can still choose a photo from your library.")
    }

    Row(modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(
            enabled = enabled,
            onClick = { photo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
        ) { Text("Photo") }
        if (allowCamera) {
            OutlinedButton(
                enabled = enabled,
                onClick = {
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        launchCamera()
                    } else {
                        cameraPermission.launch(Manifest.permission.CAMERA)
                    }
                },
            ) { Text("Camera") }
        }
        if (allowPdf) OutlinedButton(enabled = enabled, onClick = { pdf.launch(arrayOf("application/pdf")) }) { Text("PDF") }
    }
}
