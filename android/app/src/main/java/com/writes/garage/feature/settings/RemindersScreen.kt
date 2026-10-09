package com.writes.garage.feature.settings

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.domain.ReminderDueDatePreset
import com.writes.garage.core.domain.ReminderForm
import com.writes.garage.core.domain.ReminderStatus
import com.writes.garage.core.model.EntryType
import com.writes.garage.core.model.Reminder
import com.writes.garage.feature.handover.CacheExportFileStore
import com.writes.garage.feature.handover.shareExportedFile
import com.writes.garage.feature.shared.ConfirmDialog
import com.writes.garage.feature.shared.DateField
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.FormTextField
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.SwitchRow
import com.writes.garage.feature.shared.appViewModel

@Composable
fun RemindersScreen(onBack: () -> Unit) {
    val app = LocalContext.current.applicationContext
    val vm = appViewModel { RemindersViewModel(it.vehicles, it.reminders, CacheExportFileStore(app), analytics = it.analytics) }
    val s by vm.state.collectAsState()
    val context = LocalContext.current
    var pendingDelete by remember { mutableStateOf<Reminder?>(null) }

    LaunchedEffect(s.pendingShare) {
        val f = s.pendingShare ?: return@LaunchedEffect
        shareExportedFile(context, f)
        vm.shareHandled()
    }
    pendingDelete?.let { r ->
        ConfirmDialog(
            title = "Delete reminder?", message = "\"${r.title}\" will be removed.", confirmLabel = "Delete",
            onConfirm = { vm.delete(r); pendingDelete = null }, onDismiss = { pendingDelete = null },
        )
    }

    ScreenColumn("Reminders") {
        val v = s.vehicle
        if (v == null) {
            item { EmptyState("Add a vehicle in Garage to set reminders.") }
            item { OutlinedButton(onClick = onBack) { Text("Back") } }
            return@ScreenColumn
        }
        item { Text(v.displayName, style = MaterialTheme.typography.titleMedium) }

        item { SectionHeader(if (s.form.isEditing) "Edit reminder" else "New reminder") }
        item { FormTextField("Title", s.form.title, { t -> vm.updateForm { copy(title = t) } }, error = s.form.errors[ReminderForm.TITLE], required = true) }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = s.form.entryType == null, onClick = { vm.setEntryType(null) }, label = { Text("Any type") })
                EntryType.entries.forEach { t ->
                    FilterChip(selected = s.form.entryType == t, onClick = { vm.setEntryType(t) }, label = { Text(t.displayName) })
                }
            }
        }
        item { SwitchRow("Remind me on a date", s.form.hasDueDate, { on -> vm.updateForm { copy(hasDueDate = on) } }) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ReminderDueDatePreset.entries.forEach { p -> OutlinedButton(onClick = { vm.applyPreset(p) }) { Text(p.label) } }
            }
        }
        if (s.form.hasDueDate) {
            item { DateField("Due date", s.form.dueDate, { d -> d?.let { vm.updateForm { copy(dueDate = it) } } }, error = s.form.errors[ReminderForm.DUE_DATE]) }
        }
        s.mileageOnlyHint?.let { item { Text(it, style = MaterialTheme.typography.bodySmall) } }
        item {
            FormTextField(
                "Due mileage", s.form.dueMileage, { t -> vm.updateForm { copy(dueMileage = t.filter(Char::isDigit)) } },
                error = s.form.errors[ReminderForm.DUE_MILEAGE], keyboardType = KeyboardType.Number,
            )
        }
        item {
            FormTextField(
                "Repeat every X months", s.form.repeatMonths, { t -> vm.updateForm { copy(repeatMonths = t.filter(Char::isDigit)) } },
                error = s.form.errors[ReminderForm.REPEAT_MONTHS], keyboardType = KeyboardType.Number,
            )
        }
        item {
            FormTextField(
                "Repeat every X miles", s.form.repeatMiles, { t -> vm.updateForm { copy(repeatMiles = t.filter(Char::isDigit)) } },
                error = s.form.errors[ReminderForm.REPEAT_MILES], keyboardType = KeyboardType.Number,
            )
        }
        item { FormTextField("Notes", s.form.notes, { t -> vm.updateForm { copy(notes = t) } }, singleLine = false) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = vm::save, enabled = !s.saving) { Text(if (s.form.isEditing) "Save changes" else "Save reminder") }
                if (s.form.isEditing) OutlinedButton(onClick = vm::cancelEdit) { Text("Cancel") }
            }
        }
        if (s.saved) item { Text("Reminder saved", color = MaterialTheme.colorScheme.primary) }
        item { ErrorText(s.error) }

        item { SectionHeader("Your reminders") }
        if (s.outstanding.isEmpty() && s.completed.isEmpty()) item { EmptyState("No reminders yet.") }
        items(s.outstanding, key = { "out-${it.reminder.id}" }) { row ->
            val r = row.reminder
            ListItem(
                headlineContent = { Text(r.title) },
                supportingContent = {
                    Text(
                        listOfNotNull(
                            r.dueDate?.let { "Due ${Formatters.date(it)}" },
                            r.dueMileage?.let { "at ${Formatters.odometer(it)}" },
                            if (row.status == ReminderStatus.OVERDUE) "Overdue" else null,
                        ).joinToString(" - ").ifEmpty { "Unscheduled" },
                    )
                },
                trailingContent = {
                    Row(Modifier.horizontalScroll(rememberScrollState())) {
                        TextButton(onClick = { vm.beginEditing(r) }) { Text("Edit") }
                        TextButton(onClick = { vm.markDone(r) }) { Text("Done") }
                        if (r.dueDate != null) TextButton(onClick = { vm.exportCalendar(r) }) { Text("Calendar") }
                        TextButton(onClick = { pendingDelete = r }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
                    }
                },
            )
        }
        if (s.completed.isNotEmpty()) item { SectionHeader("Completed") }
        items(s.completed, key = { "done-${it.id}" }) { r ->
            ListItem(
                headlineContent = { Text(r.title) },
                supportingContent = { Text("Done ${r.completedAt?.let { Formatters.date(it) }.orEmpty()}") },
                trailingContent = { TextButton(onClick = { pendingDelete = r }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
            )
        }
        item { OutlinedButton(onClick = onBack) { Text("Back") } }
    }
}
