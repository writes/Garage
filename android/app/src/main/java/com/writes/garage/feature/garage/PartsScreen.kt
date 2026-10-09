package com.writes.garage.feature.garage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.domain.PartForm
import com.writes.garage.core.model.PartCategory
import com.writes.garage.core.model.PartCondition
import com.writes.garage.core.model.SparePart
import com.writes.garage.feature.entry.PendingAttachment
import com.writes.garage.feature.shared.AttachmentPickerRow
import com.writes.garage.feature.shared.ChoiceField
import com.writes.garage.feature.shared.ChoiceOption
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

@Composable
fun PartsScreen(vehicleId: String, onBack: () -> Unit) {
    val vm = appViewModel(key = "parts-$vehicleId") { PartsViewModel(it.parts, vehicleId, it.storage) }
    val s by vm.state.collectAsState()
    val storage = LocalAppContainer.current.storage
    var pendingDelete by remember { mutableStateOf<SparePart?>(null) }
    pendingDelete?.let { p ->
        ConfirmDialog(
            "Delete part?", "\"${p.name}\" will be removed from your inventory.", "Delete",
            onConfirm = { vm.delete(p); pendingDelete = null }, onDismiss = { pendingDelete = null },
        )
    }

    ScreenColumn("Spare parts") {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onBack) { Text("Back") }
                if (s.form == null) Button(onClick = vm::startNew) { Text("Add part") }
            }
        }
        item { ErrorText(s.error) }
        val f = s.form
        if (f != null) {
            item { SectionHeader(if (f.editingId != null) "Edit part" else "New part") }
            item { FormTextField("Name", f.name, { v -> vm.update { copy(name = v) } }, error = f.errors[PartForm.NAME], required = true) }
            item {
                ChoiceField("Category", PartCategory.entries.map { ChoiceOption(it.wire, it.label) }, f.category.wire, { v ->
                    vm.update { copy(category = PartCategory.fromWire(v)) }
                })
            }
            item { FormTextField("Brand", f.brand, { v -> vm.update { copy(brand = v) } }) }
            item { FormTextField("Part number", f.partNumber, { v -> vm.update { copy(partNumber = v) } }) }
            item {
                FormTextField(
                    "Quantity", f.quantity, { v -> vm.update { copy(quantity = v.filter(Char::isDigit)) } },
                    error = f.errors[PartForm.QUANTITY], keyboardType = KeyboardType.Number, required = true,
                )
            }
            item {
                FormTextField(
                    "Unit cost", f.unitCost, { v -> vm.update { copy(unitCost = v.filter { c -> c.isDigit() || c == '.' }) } },
                    error = f.errors[PartForm.UNIT_COST], keyboardType = KeyboardType.Decimal,
                )
            }
            item { FormTextField("Where purchased", f.wherePurchased, { v -> vm.update { copy(wherePurchased = v) } }) }
            item { DateField("Purchase date", f.purchaseDate, { d -> vm.update { copy(purchaseDate = d) } }, clearable = true) }
            item { FormTextField("Storage location", f.storageLocation, { v -> vm.update { copy(storageLocation = v) } }) }
            item {
                ChoiceField("Condition", PartCondition.entries.map { ChoiceOption(it.wire, it.label) }, f.condition.wire, { v ->
                    vm.update { copy(condition = PartCondition.fromWire(v)) }
                })
            }
            item { SwitchRow("Consumed (used up)", f.isConsumed, { on -> vm.update { copy(isConsumed = on) } }) }
            if (vm.hasStorage) {
                item { SectionHeader("Photo") }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        f.photoPath?.let { StorageImage(storage, it, height = 120.dp) }
                        vm.pendingPhotoName()?.let { Text("New photo: $it", style = MaterialTheme.typography.bodySmall) }
                        AttachmentPickerRow(
                            onPicked = { uri, mime, name -> vm.pickPhoto(PendingAttachment(uri, mime, name)) },
                            onError = { m -> vm.update { copy(errors = errors + ("photo" to m)) } },
                            allowPdf = false,
                        )
                        if (f.photoPath != null || vm.pendingPhotoName() != null) TextButton(onClick = vm::clearPhoto) { Text("Remove photo") }
                    }
                }
                item { SectionHeader("Receipt") }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        f.receiptPath?.let { Text("Receipt on file", style = MaterialTheme.typography.bodySmall) }
                        vm.pendingReceiptName()?.let { Text("New receipt: $it", style = MaterialTheme.typography.bodySmall) }
                        AttachmentPickerRow(
                            onPicked = { uri, mime, name -> vm.pickReceipt(PendingAttachment(uri, mime, name)) },
                            onError = { m -> vm.update { copy(errors = errors + ("receipt" to m)) } },
                        )
                        if (f.receiptPath != null || vm.pendingReceiptName() != null) TextButton(onClick = vm::clearReceipt) { Text("Remove receipt") }
                    }
                }
                f.errors["photo"]?.let { item { ErrorText(it) } }
                f.errors["receipt"]?.let { item { ErrorText(it) } }
            }
            item { FormTextField("Notes", f.notes, { v -> vm.update { copy(notes = v) } }, singleLine = false) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = vm::save, enabled = !s.saving) { Text(if (s.saving) "Saving..." else "Save") }
                    OutlinedButton(onClick = vm::cancel) { Text("Cancel") }
                }
            }
        }
        if (s.items.isEmpty() && f == null) item { EmptyState("No spare parts yet.") }
        if (s.items.isNotEmpty() && f == null) {
            item { Text("On hand: ${Formatters.currency(PartForm.onHandValue(s.items))}", style = MaterialTheme.typography.titleSmall) }
        }
        items(s.items, key = { it.id }) { p ->
            ListItem(
                overlineContent = { Text(listOf(p.category.label, p.condition.label).joinToString(" - ").uppercase()) },
                headlineContent = { Text("${p.quantity} x ${p.name}" + if (p.isConsumed) " (consumed)" else "") },
                supportingContent = {
                    Text(
                        listOfNotNull(
                            p.brand, p.partNumber?.let { "P/N $it" }, p.unitCost?.let { Formatters.currency(it) + " ea" }, p.storageLocation,
                        ).joinToString(" - "),
                    )
                },
                trailingContent = {
                    Row {
                        TextButton(onClick = { vm.markConsumed(p, !p.isConsumed) }) { Text(if (p.isConsumed) "Restock" else "Used") }
                        TextButton(onClick = { vm.startEdit(p) }) { Text("Edit") }
                        TextButton(onClick = { pendingDelete = p }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
                    }
                },
            )
        }
    }
}
