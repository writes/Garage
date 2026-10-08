package com.writes.garage.feature.log

import androidx.compose.foundation.layout.Arrangement
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
    val vm = appViewModel(key = "entry-$vehicleId-$entryId") { EntryDetailViewModel(it.entries, vehicleId, entryId) }
    val entry by vm.entry.collectAsState()
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
            item { ListItem(headlineContent = { Text("Attachments") }, supportingContent = { Text("${e.attachmentPaths.size} file(s)") }) }
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
