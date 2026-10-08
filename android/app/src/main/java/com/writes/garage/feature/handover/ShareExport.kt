package com.writes.garage.feature.handover

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri

/** Opens the system share sheet for a FileProvider-backed [ExportedFile]. Returns false if no app could handle it. */
fun shareExportedFile(context: Context, f: ExportedFile): Boolean {
    val uri = Uri.parse(f.uri)
    val send = Intent(Intent.ACTION_SEND).apply {
        type = f.mimeType
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, f.fileName)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        clipData = ClipData.newRawUri(f.fileName, uri)
    }
    return runCatching { context.startActivity(Intent.createChooser(send, "Share ${f.fileName}")) }.isSuccess
}
