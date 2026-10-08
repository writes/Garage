package com.writes.garage.feature.garage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.GalleryForm
import com.writes.garage.core.model.GalleryPhoto
import com.writes.garage.core.model.GallerySection
import com.writes.garage.feature.entry.PendingAttachment
import com.writes.garage.feature.shared.AttachmentPickerRow
import com.writes.garage.feature.shared.ConfirmDialog
import com.writes.garage.feature.shared.DateField
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.FormTextField
import com.writes.garage.feature.shared.LocalAppContainer
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.StorageImage
import com.writes.garage.feature.shared.SwitchRow
import com.writes.garage.feature.shared.appViewModel

/** The photo gallery ([GallerySection.MAIN]) or the wheel gallery ([GallerySection.WHEEL]) of one vehicle. */
@Composable
fun GalleryScreen(vehicleId: String, section: GallerySection, onBack: () -> Unit) {
    val vm = appViewModel(key = "gallery-$vehicleId-${section.wire}") {
        GalleryViewModel(it.gallery, it.storage, vehicleId, section)
    }
    val s by vm.state.collectAsState()
    val storage = LocalAppContainer.current.storage
    val wheel = section == GallerySection.WHEEL
    var pendingDelete by remember { mutableStateOf<GalleryPhoto?>(null) }
    pendingDelete?.let { p ->
        ConfirmDialog(
            "Delete photo?", "\"${p.title}\" will be removed.", "Delete",
            onConfirm = { vm.delete(p); pendingDelete = null }, onDismiss = { pendingDelete = null },
        )
    }

    ScreenColumn(if (wheel) "Wheel gallery" else "Photo gallery") {
        item { OutlinedButton(onClick = onBack) { Text("Back") } }
        item { ErrorText(s.error) }
        val f = s.form
        if (f == null) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(if (wheel) "Add a wheel set photo" else "Add a photo", style = MaterialTheme.typography.labelLarge)
                    AttachmentPickerRow(
                        onPicked = { uri, mime, name -> vm.pick(PendingAttachment(uri, mime, name)) },
                        onError = vm::reportError, allowPdf = false,
                    )
                }
            }
        } else {
            item { SectionHeader(if (f.editingId != null) "Edit details" else "New ${if (wheel) "wheel photo" else "photo"}") }
            item { FormTextField("Title", f.title, { v -> vm.update { copy(title = v) } }, error = f.errors[GalleryForm.TITLE], required = true) }
            item { FormTextField("Caption", f.caption, { v -> vm.update { copy(caption = v) } }, singleLine = false) }
            item { DateField("Date taken", f.shotDate, { d -> vm.update { copy(shotDate = d) } }, clearable = true) }
            if (wheel) {
                item { FormTextField("Wheel brand", f.wheelBrand, { v -> vm.update { copy(wheelBrand = v) } }) }
                item { FormTextField("Wheel model", f.wheelModel, { v -> vm.update { copy(wheelModel = v) } }) }
                item { FormTextField("Wheel size", f.wheelSize, { v -> vm.update { copy(wheelSize = v) } }) }
                item { FormTextField("Finish", f.wheelFinish, { v -> vm.update { copy(wheelFinish = v) } }) }
                item { FormTextField("Tire combo at the time", f.tireCombo, { v -> vm.update { copy(tireCombo = v) } }) }
            }
            item { SwitchRow("Include in PDF export", f.includeInExport, { on -> vm.update { copy(includeInExport = on) } }) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = vm::save, enabled = !s.saving) { Text(if (s.saving) "Saving..." else "Save") }
                    OutlinedButton(onClick = vm::cancel) { Text("Cancel") }
                }
            }
        }
        if (s.photos.isEmpty() && f == null) item { EmptyState(if (wheel) "No wheel photos yet." else "No photos yet.") }
        items(s.photos, key = { it.id }) { p ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    StorageImage(storage, p.storagePath)
                    Text(p.title.ifBlank { "Untitled" }, style = MaterialTheme.typography.titleMedium)
                    p.caption?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                    if (wheel) {
                        Text(
                            listOfNotNull(p.wheelBrand, p.wheelModel, p.wheelSize, p.wheelFinish).joinToString(" "),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        p.tireComboAtTimeOfPhoto?.let { Text("Tires: $it", style = MaterialTheme.typography.bodySmall) }
                    }
                    Text(
                        if (p.includeInExport) "Included in PDF export" else "Not in PDF export",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        TextButton(onClick = { vm.move(p, -1) }) { Text("Up") }
                        TextButton(onClick = { vm.move(p, 1) }) { Text("Down") }
                        TextButton(onClick = { vm.toggleExport(p) }) { Text(if (p.includeInExport) "Exclude" else "Include") }
                        TextButton(onClick = { vm.edit(p) }) { Text("Edit") }
                        TextButton(onClick = { pendingDelete = p }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
                    }
                }
            }
        }
    }
}
