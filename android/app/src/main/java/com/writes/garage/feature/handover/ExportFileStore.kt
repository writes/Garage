package com.writes.garage.feature.handover

import android.content.Context
import androidx.core.content.FileProvider
import java.io.File
import java.io.OutputStream

/** A file ready to be handed to the share sheet. [uri] is a FileProvider `content://` uri string. */
data class ExportedFile(val fileName: String, val mimeType: String, val uri: String)

/** Where exports are written. The Android implementation uses the FileProvider-shared cache dir. */
interface ExportFileStore {
    fun write(fileName: String, mimeType: String, writer: (OutputStream) -> Unit): ExportedFile
}

/**
 * Writes into `cacheDir/exports/` (declared in `res/xml/file_paths.xml`) and exposes the file via the app's
 * FileProvider. Exports hold personal data, so earlier exports are deleted before each new write.
 */
class CacheExportFileStore(private val context: Context) : ExportFileStore {
    override fun write(fileName: String, mimeType: String, writer: (OutputStream) -> Unit): ExportedFile {
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val file = File(dir, fileName)
        file.outputStream().use(writer)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        return ExportedFile(fileName, mimeType, uri.toString())
    }
}
