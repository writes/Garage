package com.writes.garage.feature.log

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import com.writes.garage.core.data.firebase.BoundedRead
import com.writes.garage.feature.handover.CacheExportFileStore
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Formatters
import com.writes.garage.feature.entry.EntryDetailsPresenter
import com.writes.garage.feature.shared.ConfirmDialog
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.appViewModel

@Composable
fun EntryDetailScreen(vehicleId: String, entryId: String, onEdit: () -> Unit, onBack: () -> Unit) {
    val app = LocalContext.current.applicationContext
    val vm = appViewModel(key = "entry-$vehicleId-$entryId") {
        EntryDetailViewModel(it.entries, vehicleId, entryId, it.storage, CacheExportFileStore(app), it.analytics)
    }
    val entry by vm.entry.collectAsState()
    val loads by vm.attachments.collectAsState()
    val pendingView by vm.pendingView.collectAsState()
    val context = LocalContext.current
    LaunchedEffect(pendingView) {
        val f = pendingView ?: return@LaunchedEffect
        val uri = Uri.parse(f.uri)
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, f.mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching { context.startActivity(Intent.createChooser(view, f.fileName)) }
        vm.viewHandled()
    }
    val error by vm.error.collectAsState()
    var confirmDelete by remember { mutableStateOf(false) }
    val e = entry

    if (confirmDelete) {
        ConfirmDialog(
            title = "Delete entry?",
            message = "This removes the entry from your log. This can't be undone.",
            confirmLabel = "Delete",
            onConfirm = { confirmDelete = false; vm.delete(onBack) },
            onDismiss = { confirmDelete = false },
        )
    }

    ScreenColumn(e?.entryType?.displayName ?: "Entry") {
        if (e == null) {
            item { EmptyState("Entry not found.") }
            item { OutlinedButton(onClick = onBack) { Text("Back") } }
            return@ScreenColumn
        }
        item {
            ListItem(
                headlineContent = { Text(Formatters.date(e.entryDate)) },
                supportingContent = { Text("${Formatters.odometer(e.odometerReading)} - ${Formatters.currency(e.cost)}") },
                trailingContent = { if (e.isDiy == true) Text("DIY") },
            )
        }
        e.shopName?.let { item { ListItem(headlineContent = { Text("Shop") }, supportingContent = { Text(it) }) } }
        e.notes?.let { item { ListItem(headlineContent = { Text("Notes") }, supportingContent = { Text(it) }) } }
        val rows = EntryDetailsPresenter.rows(e)
        if (rows.isNotEmpty()) {
            item { SectionHeader("Details") }
            items(rows, key = { it.first }) { (label, value) ->
                ListItem(headlineContent = { Text(label) }, supportingContent = { Text(value) })
            }
        }
        if (e.attachmentPaths.isNotEmpty()) {
            item { SectionHeader("Attachments") }
            items(e.attachmentPaths, key = { "att-$it" }) { path ->
                AttachmentRow(
                    path, loads[path] ?: AttachmentLoad.Loading,
                    onOpenPdf = { vm.openPdf(path) }, onRemoveMissing = { vm.removeMissing(path) },
                )
            }
        }
        item { ErrorText(error) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onEdit) { Text("Edit") }
                OutlinedButton(onClick = { confirmDelete = true }) { Text("Delete") }
                OutlinedButton(onClick = onBack) { Text("Back") }
            }
        }
    }
}

@Composable
private fun AttachmentRow(path: String, load: AttachmentLoad, onOpenPdf: () -> Unit, onRemoveMissing: () -> Unit) {
    val name = path.substringAfterLast('/')
    when (load) {
        AttachmentLoad.Loading -> ListItem(headlineContent = { Text(name) }, supportingContent = { Text("Loading...") })
        is AttachmentLoad.Image -> {
            val bitmap = remember(load) { decodeThumbnail(load.bytes) }
            if (bitmap != null) {
                Image(bitmap, contentDescription = "Attachment photo", modifier = Modifier.fillMaxWidth().heightIn(max = 280.dp))
            } else {
                ListItem(headlineContent = { Text(name) }, supportingContent = { Text("Photo") })
            }
        }
        AttachmentLoad.Pdf -> ListItem(
            headlineContent = { Text("PDF") }, supportingContent = { Text(name) },
            trailingContent = { OutlinedButton(onClick = onOpenPdf) { Text("Open") } },
        )
        AttachmentLoad.Missing -> ListItem(
            headlineContent = { Text("Attachment unavailable") },
            supportingContent = { Text("The file is no longer stored (attachments are a Pro feature).") },
            trailingContent = { TextButton(onClick = onRemoveMissing) { Text("Remove") } },
        )
        is AttachmentLoad.Failed -> ListItem(headlineContent = { Text(name) }, supportingContent = { Text(load.message) })
    }
}

/** Decodes a downscaled preview so a multi-megapixel photo never lands in memory at full size. */
private fun decodeThumbnail(bytes: ByteArray, maxEdge: Int = 1024) = runCatching {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    val sample = BoundedRead.sampleSize(bounds.outWidth, bounds.outHeight, maxEdge)
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })?.asImageBitmap()
}.getOrNull()
