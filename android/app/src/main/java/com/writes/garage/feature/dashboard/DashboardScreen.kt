package com.writes.garage.feature.dashboard

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.writes.garage.R
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.domain.MaintenanceStatus
import com.writes.garage.core.domain.ReminderStatus
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.LocalAppContainer
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.VehicleSwitcher
import com.writes.garage.feature.shared.appViewModel

@Composable
fun DashboardScreen(
    onAddEntry: () -> Unit,
    onScanReceipt: () -> Unit,
    onVoice: () -> Unit,
    onHandover: () -> Unit,
    onOpenEntry: (vehicleId: String, entryId: String) -> Unit,
) {
    val vm = appViewModel { DashboardViewModel(it.vehicles, it.entries, it.reminders) }
    val state by vm.state.collectAsState()
    val error by vm.error.collectAsState()
    val isDemo = LocalAppContainer.current.isDemo

    ScreenColumn("Dashboard") {
        item { com.writes.garage.feature.shared.ErrorText(error) }
        if (isDemo) item { Text(stringResource(R.string.demo_banner), style = MaterialTheme.typography.labelMedium) }
        val vehicle = state.activeVehicle
        if (vehicle == null) {
            item { EmptyState(if (state.loading) "Loading..." else "No vehicles yet. Add one in Garage.") }
            return@ScreenColumn
        }
        item { VehicleSwitcher(state.vehicles, vehicle.id, vm::selectVehicle) }
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(vehicle.displayName, style = MaterialTheme.typography.titleLarge)
                    Text("${vehicle.year} ${vehicle.make} ${vehicle.model}", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        Formatters.odometer(vehicle.currentOdometer),
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onAddEntry) { Text("Add entry") }
                OutlinedButton(onClick = onScanReceipt) { Text("Receipt") }
                OutlinedButton(onClick = onVoice) { Text("Voice") }
            }
        }
        item { OutlinedButton(onClick = onHandover) { Text("Export / handover") } }

        if (state.attention.isNotEmpty()) {
            item { SectionHeader("Needs attention") }
            items(state.attention, key = { "attn-${it.item.name}" }) { due ->
                ListItem(
                    headlineContent = { Text(due.item.label) },
                    supportingContent = {
                        Text(
                            when (due.status) {
                                MaintenanceStatus.NEVER_LOGGED -> "Never logged"
                                MaintenanceStatus.OVERDUE -> "Overdue since ${Formatters.date(due.dueDate)}"
                                else -> "Due ${Formatters.date(due.dueDate)}"
                            },
                        )
                    },
                    trailingContent = { StatusLabel(due.status.name.replace('_', ' '), due.status == MaintenanceStatus.OVERDUE) },
                )
            }
        }

        item { SectionHeader("Reminders") }
        if (state.reminders.isEmpty()) item { EmptyState("Nothing due.") }
        items(state.reminders, key = { "rem-${it.reminder.id}" }) { row ->
            val r = row.reminder
            ListItem(
                headlineContent = { Text(r.title) },
                supportingContent = {
                    Text(listOfNotNull(r.dueDate?.let { "Due ${Formatters.date(it)}" }, r.dueMileage?.let { "at ${Formatters.odometer(it)}" }).joinToString(" "))
                },
                trailingContent = {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        StatusLabel(row.status.label(), row.status == ReminderStatus.OVERDUE)
                        TextButton(onClick = { vm.completeReminder(r) }) { Text("Done") }
                    }
                },
            )
        }

        item { SectionHeader("Recent entries") }
        if (state.recentEntries.isEmpty()) item { EmptyState("No entries yet.") }
        items(state.recentEntries, key = { it.id }) { e ->
            ListItem(
                modifier = Modifier.clickable { onOpenEntry(e.vehicleId, e.id) },
                headlineContent = { Text(e.entryType.displayName) },
                supportingContent = { Text("${Formatters.date(e.entryDate)} - ${Formatters.odometer(e.odometerReading)}") },
                trailingContent = { Text(Formatters.currency(e.cost)) },
            )
        }
    }
}

@Composable
private fun StatusLabel(text: String, alert: Boolean) {
    Text(
        text.lowercase().replaceFirstChar(Char::uppercase),
        style = MaterialTheme.typography.labelMedium,
        color = if (alert) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

private fun ReminderStatus.label(): String = when (this) {
    ReminderStatus.OVERDUE -> "Overdue"
    ReminderStatus.DUE_SOON -> "Due soon"
    ReminderStatus.UPCOMING -> "Upcoming"
    ReminderStatus.NO_SCHEDULE -> "Unscheduled"
    ReminderStatus.COMPLETED -> "Done"
}
