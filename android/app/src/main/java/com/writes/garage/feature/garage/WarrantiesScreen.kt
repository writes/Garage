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
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.domain.WarrantyForm
import com.writes.garage.core.model.Warranty
import com.writes.garage.core.model.WarrantyType
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
import java.time.Instant

@Composable
fun WarrantiesScreen(vehicleId: String, onBack: () -> Unit) {
    val vm = appViewModel(key = "warranties-$vehicleId") { WarrantiesViewModel(it.warranties, vehicleId) }
    val s by vm.state.collectAsState()
    var pendingDelete by remember { mutableStateOf<Warranty?>(null) }
    pendingDelete?.let { w ->
        ConfirmDialog(
            "Delete warranty?", "This record will be removed.", "Delete",
            onConfirm = { vm.delete(w); pendingDelete = null }, onDismiss = { pendingDelete = null },
        )
    }

    ScreenColumn("Warranty") {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onBack) { Text("Back") }
                if (s.form == null) Button(onClick = vm::startNew) { Text("Add warranty") }
            }
        }
        item { ErrorText(s.error) }
        val f = s.form
        if (f != null) {
            item { SectionHeader(if (f.editingId != null) "Edit warranty" else "New warranty") }
            item {
                ChoiceField("Type", WarrantyType.entries.map { ChoiceOption(it.wire, it.label) }, f.type.wire, { v ->
                    vm.update { copy(type = WarrantyType.fromWire(v)) }
                })
            }
            item { FormTextField("Provider", f.provider, { v -> vm.update { copy(provider = v) } }) }
            item { FormTextField("Plan name", f.plan, { v -> vm.update { copy(plan = v) } }) }
            item { DateField("Coverage start", f.startDate, { d -> d?.let { vm.update { copy(startDate = it) } } }, required = true) }
            item { DateField("Coverage end", f.endDate, { d -> vm.update { copy(endDate = d) } }, error = f.errors[WarrantyForm.END_DATE], clearable = true) }
            item { Term("Basic term (months)", f.basicMonths, f.errors["basicMonths"]) { v -> vm.update { copy(basicMonths = v) } } }
            item { Term("Basic term (miles)", f.basicMiles, f.errors["basicMiles"]) { v -> vm.update { copy(basicMiles = v) } } }
            item { Term("Powertrain term (months)", f.powertrainMonths, f.errors["powertrainMonths"]) { v -> vm.update { copy(powertrainMonths = v) } } }
            item { Term("Powertrain term (miles)", f.powertrainMiles, f.errors["powertrainMiles"]) { v -> vm.update { copy(powertrainMiles = v) } } }
            item { Term("Corrosion term (months)", f.corrosionMonths, f.errors["corrosionMonths"]) { v -> vm.update { copy(corrosionMonths = v) } } }
            item { Term("Roadside term (months)", f.roadsideMonths, f.errors["roadsideMonths"]) { v -> vm.update { copy(roadsideMonths = v) } } }
            item { Term("Mileage limit", f.mileageLimit, f.errors["mileageLimit"]) { v -> vm.update { copy(mileageLimit = v) } } }
            item {
                FormTextField(
                    "Deductible", f.deductible, { v -> vm.update { copy(deductible = v.filter { c -> c.isDigit() || c == '.' }) } },
                    error = f.errors["deductible"], keyboardType = KeyboardType.Decimal,
                )
            }
            item { FormTextField("Contract number", f.contractNumber, { v -> vm.update { copy(contractNumber = v) } }) }
            item { FormTextField("Provider phone", f.providerPhone, { v -> vm.update { copy(providerPhone = v) } }, keyboardType = KeyboardType.Phone) }
            item { FormTextField("Coverage description", f.coverageDescription, { v -> vm.update { copy(coverageDescription = v) } }, singleLine = false) }
            item { FormTextField("Exclusions", f.exclusions, { v -> vm.update { copy(exclusions = v) } }, singleLine = false) }
            item { FormTextField("Notes", f.notes, { v -> vm.update { copy(notes = v) } }, singleLine = false) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = vm::save, enabled = !s.saving) { Text(if (s.saving) "Saving..." else "Save") }
                    OutlinedButton(onClick = vm::cancel) { Text("Cancel") }
                }
            }
        }
        if (s.items.isEmpty() && f == null) item { EmptyState("No warranty records yet.") }
        val now = Instant.now()
        items(s.items, key = { it.id }) { w ->
            ListItem(
                overlineContent = { Text(if (w.isActive(now)) "ACTIVE" else "EXPIRED", color = if (w.isActive(now)) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) },
                headlineContent = { Text(listOfNotNull(w.warrantyType.label, w.providerName, w.planName).joinToString(" - ")) },
                supportingContent = {
                    Text(
                        listOfNotNull(
                            "From ${Formatters.date(w.coverageStart ?: w.startDate)}", w.endsAt?.let { "to ${Formatters.date(it)}" },
                            w.mileageLimit?.let { "limit ${Formatters.odometer(it)}" }, w.deductible?.let { "deductible ${Formatters.currency(it)}" },
                        ).joinToString(" "),
                    )
                },
                trailingContent = {
                    Row {
                        TextButton(onClick = { vm.startEdit(w) }) { Text("Edit") }
                        TextButton(onClick = { pendingDelete = w }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
                    }
                },
            )
        }
    }
}

@Composable
private fun Term(label: String, value: String, error: String?, onChange: (String) -> Unit) =
    FormTextField(label, value, { v -> onChange(v.filter(Char::isDigit)) }, error = error, keyboardType = KeyboardType.Number)
