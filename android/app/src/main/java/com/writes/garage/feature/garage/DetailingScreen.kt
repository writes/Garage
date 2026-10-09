package com.writes.garage.feature.garage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ListItem
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.DetailingForm
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.model.DetailingRecord
import com.writes.garage.core.model.DetailingType
import com.writes.garage.feature.shared.ChoiceField
import com.writes.garage.feature.shared.ChoiceOption
import com.writes.garage.feature.shared.ConfirmDialog
import com.writes.garage.feature.shared.DateField
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.FormTextField
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.appViewModel

@Composable
fun DetailingScreen(vehicleId: String, onBack: () -> Unit) {
    val vm = appViewModel(key = "detailing-$vehicleId") { DetailingViewModel(it.detailing, vehicleId) }
    val s by vm.state.collectAsState()
    var pendingDelete by remember { mutableStateOf<DetailingRecord?>(null) }
    pendingDelete?.let { r ->
        ConfirmDialog(
            "Delete record?", "\"${r.title}\" will be removed.", "Delete",
            onConfirm = { vm.delete(r); pendingDelete = null }, onDismiss = { pendingDelete = null },
        )
    }

    ScreenColumn("Detailing") {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onBack) { Text("Back") }
                if (s.form == null) Button(onClick = vm::startNew) { Text("Add record") }
            }
        }
        item { ErrorText(s.error) }
        val f = s.form
        if (f != null) {
            item { SectionHeader(if (f.editingId != null) "Edit record" else "New record") }
            item { DateField("Service date", f.serviceDate, { d -> d?.let { vm.update { copy(serviceDate = it) } } }, required = true) }
            item {
                ChoiceField("Type", DetailingType.entries.map { ChoiceOption(it.wire, it.label) }, f.type.wire, { v ->
                    vm.update { copy(type = DetailingType.fromWire(v)) }
                })
            }
            item { FormTextField("Title", f.title, { v -> vm.update { copy(title = v) } }, error = f.errors[DetailingForm.TITLE], required = true) }
            item { FormTextField("Provider / shop", f.provider, { v -> vm.update { copy(provider = v) } }) }
            item { FormTextField("Product", f.product, { v -> vm.update { copy(product = v) } }) }
            item { FormTextField("Correction type", f.correctionType, { v -> vm.update { copy(correctionType = v) } }) }
            item { FormTextField("Coverage area", f.coverageArea, { v -> vm.update { copy(coverageArea = v) } }) }
            item {
                FormTextField(
                    "Layers", f.layers, { v -> vm.update { copy(layers = v.filter(Char::isDigit)) } },
                    error = f.errors[DetailingForm.LAYERS], keyboardType = KeyboardType.Number,
                )
            }
            item { DateField("Warranty expiration", f.warrantyExpiration, { d -> vm.update { copy(warrantyExpiration = d) } }, clearable = true) }
            item { FormTextField("Maintenance schedule notes", f.maintenanceNotes, { v -> vm.update { copy(maintenanceNotes = v) } }, singleLine = false) }
            item {
                FormTextField(
                    "Cost", f.cost, { v -> vm.update { copy(cost = v.filter { c -> c.isDigit() || c == '.' }) } },
                    error = f.errors[DetailingForm.COST], keyboardType = KeyboardType.Decimal,
                )
            }
            item { FormTextField("Notes", f.notes, { v -> vm.update { copy(notes = v) } }, singleLine = false) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = vm::save, enabled = !s.saving) { Text(if (s.saving) "Saving..." else "Save") }
                    OutlinedButton(onClick = vm::cancel) { Text("Cancel") }
                }
            }
        }
        if (s.items.isEmpty() && f == null) item { EmptyState("No detailing records yet.") }
        items(s.items, key = { it.id }) { r ->
            ListItem(
                overlineContent = { Text(r.serviceType.label.uppercase()) },
                headlineContent = { Text(r.title) },
                supportingContent = {
                    Text(
                        listOfNotNull(
                            Formatters.date(r.serviceDate), r.providerName, r.productName,
                            r.layers?.let { "$it layer${if (it == 1) "" else "s"}" }, r.cost?.let { Formatters.currency(it) },
                            r.warrantyExpiration?.let { "warranty to ${Formatters.date(it)}" },
                        ).joinToString(" - "),
                    )
                },
                trailingContent = {
                    Row {
                        TextButton(onClick = { vm.startEdit(r) }) { Text("Edit") }
                        TextButton(onClick = { pendingDelete = r }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
                    }
                },
            )
        }
    }
}
