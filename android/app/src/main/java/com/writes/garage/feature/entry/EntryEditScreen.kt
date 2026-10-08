package com.writes.garage.feature.entry

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.runtime.LaunchedEffect
import com.writes.garage.feature.shared.AiConsentDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.TextButton
import androidx.compose.ui.Alignment
import com.writes.garage.core.data.WearSync
import com.writes.garage.feature.shared.AttachmentPickerRow
import com.writes.garage.feature.shared.LocalAppContainer
import com.writes.garage.feature.shared.ProGate
import kotlinx.coroutines.flow.first
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.writes.garage.core.model.EntryType
import com.writes.garage.feature.shared.ChoiceField
import com.writes.garage.feature.shared.ChoiceOption
import com.writes.garage.feature.shared.DateField
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.FormTextField
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.SwitchRow
import com.writes.garage.feature.shared.VehicleSwitcher
import com.writes.garage.feature.shared.appViewModel
import java.time.LocalDate

@Composable
fun EntryEditScreen(vehicleId: String?, entryId: String?, onDone: () -> Unit, onUpgrade: () -> Unit = {}) {
    val vm = appViewModel(key = "entry-edit-$vehicleId-$entryId") {
        EntryEditViewModel(
            it.entries, it.vehicles, vehicleId, entryId,
            wear = WearSync(it.wear), storage = it.storage, analytics = it.analytics,
            profile = it.profile, functions = it.functions, reviews = it.reviews,
            canAttach = { it.purchases.entitlement.value.isPro && (it.isDemo || it.profile.observeProfile().first()?.serverIsPro == true) },
        )
    }
    val s by vm.state.collectAsState()
    val isPro by LocalAppContainer.current.purchases.entitlement.collectAsState()
    val pdfPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) vm.importOilAnalysis(uri.toString())
    }
    LaunchedEffect(s.needsUpgrade) {
        if (s.needsUpgrade) {
            vm.upgradeHandled()
            onUpgrade()
        }
    }
    if (s.needsAiConsent) AiConsentDialog(onGrant = vm::grantImportConsent, onDismiss = vm::dismissImportConsent)

    ScreenColumn(if (entryId == null) "Add entry" else "Edit entry") {
        if (s.loading) {
            item { CircularProgressIndicator() }
            return@ScreenColumn
        }
        if (s.notFound) {
            item { EmptyState("Entry not found.") }
            item { OutlinedButton(onClick = onDone) { Text("Back") } }
            return@ScreenColumn
        }
        if (s.vehicleId == null) {
            item { EmptyState("Add a vehicle in Garage before logging entries.") }
            item { OutlinedButton(onClick = onDone) { Text("Back") } }
            return@ScreenColumn
        }

        if (entryId == null) {
            item { VehicleSwitcher(s.vehicles, s.vehicleId, vm::selectVehicle) }
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                EntryType.entries.forEach { type ->
                    FilterChip(selected = s.type == type, onClick = { vm.setType(type) }, label = { Text(type.displayName) })
                }
            }
        }
        item { DateField("Date", s.date, onPick = { d -> d?.let(vm::setDate) }, required = true) }
        item {
            FormTextField(
                "Odometer (mi)", s.odometer, vm::setOdometer,
                error = s.errors[EntryFormValidator.ODOMETER], keyboardType = KeyboardType.Number, required = true,
            )
        }
        s.warnings.forEach { w -> item(key = "warn-$w") { Text(w, color = MaterialTheme.colorScheme.tertiary, style = MaterialTheme.typography.bodySmall) } }
        item {
            FormTextField(
                "Cost", s.cost, vm::setCost,
                error = s.errors[EntryFormValidator.COST], keyboardType = KeyboardType.Decimal,
            )
        }
        item { FormTextField("Shop", s.shop, { v -> vm.update { copy(shop = v) } }) }
        item { SwitchRow("Did it myself (DIY)", s.isDiy, onChange = { v -> vm.update { copy(isDiy = v) } }) }

        if (s.type == EntryType.OIL_ANALYSIS && vm.importAvailable) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    OutlinedButton(onClick = { pdfPicker.launch(arrayOf("application/pdf")) }, enabled = !s.importing) {
                        Text(if (s.importing) "Reading report..." else "Import lab PDF")
                    }
                    Text(
                        "Fills the fields below from your lab report (sent to Garage's AI service). You review everything before saving.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    s.importNotice?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }
                }
            }
        }
        item { SectionHeader("${s.type.displayName} details") }
        var lastSection: String? = null
        EntryFieldSpecs.forType(s.type).fields.filter { it.isVisible(s.details) }.forEach { f ->
            if (f.section != null && f.section != lastSection) item(key = "section-${f.section}") { SectionHeader(f.section) }
            lastSection = f.section
            item(key = "field-${s.type.wire}-${f.key}") {
                DetailField(f, s.details[f.key].orEmpty(), s.errors[EntryFormValidator.detailKey(f.key)], f.isRequired(s.details)) { v ->
                    vm.setDetail(f.key, v)
                }
            }
        }

        item { FormTextField("Notes", s.notes, { v -> vm.update { copy(notes = v) } }, singleLine = false) }
        if (vm.attachmentsAvailable) {
            item { SectionHeader("Attachments") }
            item {
                ProGate(isPro = isPro.isPro, onUpgrade = onUpgrade, lockedMessage = "Attaching photos and PDFs to entries is a Garage Pro feature.") {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        s.attachmentPaths.forEach { path ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Text(path.substringAfterLast('/'), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, maxLines = 1)
                                TextButton(onClick = { vm.removeExistingAttachment(path) }) { Text("Remove") }
                            }
                        }
                        s.pendingAttachments.forEachIndexed { i, p ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Text("${p.displayName} (new)", Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, maxLines = 1)
                                TextButton(onClick = { vm.removePendingAttachment(i) }) { Text("Remove") }
                            }
                        }
                        AttachmentPickerRow(
                            onPicked = vm::addAttachment,
                            onError = { msg -> vm.update { copy(formError = msg) } },
                        )
                    }
                }
            }
        }
        item { ErrorText(s.formError) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { vm.save(onDone) }, enabled = !s.saving) { Text(if (s.saving) "Saving..." else "Save") }
                OutlinedButton(onClick = onDone) { Text("Cancel") }
            }
        }
    }
}

@Composable
private fun DetailField(f: FieldDef, value: String, error: String?, required: Boolean, onChange: (String) -> Unit) {
    when (f.kind) {
        FieldKind.TEXT -> FormTextField(f.label, value, onChange, error = error, required = required)
        FieldKind.MULTILINE, FieldKind.LIST ->
            FormTextField(f.label, value, onChange, error = error, singleLine = false, required = required)
        FieldKind.INTEGER -> FormTextField(
            f.label, value, { v -> onChange(v.filter(Char::isDigit)) },
            error = error, keyboardType = KeyboardType.Number, required = required,
        )
        FieldKind.DECIMAL -> FormTextField(
            f.label, value, { v -> onChange(v.filter { c -> c.isDigit() || c == '.' }) },
            error = error, keyboardType = KeyboardType.Decimal, required = required,
        )
        FieldKind.BOOLEAN -> SwitchRow(f.label, value == "true", onChange = { onChange(it.toString()) })
        FieldKind.CHOICE -> ChoiceField(
            f.label, f.choices.map { ChoiceOption(it.value, it.label) }, value, onChange, error = error, required = required,
        )
        FieldKind.DATE -> DateField(
            f.label, runCatching { LocalDate.parse(value) }.getOrNull(), { onChange(it?.toString().orEmpty()) },
            error = error, clearable = true,
        )
    }
}

