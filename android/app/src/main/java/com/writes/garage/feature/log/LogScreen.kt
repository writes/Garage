package com.writes.garage.feature.log

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.model.EntryType
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.VehicleSwitcher
import com.writes.garage.feature.shared.appViewModel

@Composable
fun LogScreen(onOpenEntry: (vehicleId: String, entryId: String) -> Unit, onAddEntry: () -> Unit) {
    val vm = appViewModel { LogViewModel(it.vehicles, it.entries) }
    val state by vm.state.collectAsState()
    val error by vm.error.collectAsState()

    ScreenColumn("Log") {
        item { com.writes.garage.feature.shared.ErrorText(error) }
        item { VehicleSwitcher(state.vehicles, state.activeVehicleId, vm::selectVehicle) }
        item {
            OutlinedTextField(
                value = state.search,
                onValueChange = vm::setSearch,
                label = { Text("Search shop, notes, type") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                EntryType.entries.forEach { type ->
                    FilterChip(
                        selected = type in state.types,
                        onClick = { vm.toggleType(type) },
                        label = { Text(type.displayName) },
                    )
                }
            }
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onAddEntry, enabled = state.hasVehicle) { Text("Add entry") }
                Text(
                    "${state.entries.size} of ${state.totalCount}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (state.isFiltering) TextButton(onClick = vm::clearFilters) { Text("Clear filters") }
            }
        }
        if (!state.hasVehicle) {
            item { EmptyState("No vehicle yet. Add one in Garage to start logging.") }
        } else if (state.entries.isEmpty()) {
            item { EmptyState(if (state.isFiltering) "No matching entries." else "No entries yet.") }
        }
        state.groups.forEach { group ->
            item(key = "month-${group.month}") {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(group.label, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
                    Text(Formatters.currency(group.total), style = MaterialTheme.typography.labelLarge)
                }
            }
            items(group.entries, key = { it.id }) { e ->
                ListItem(
                    modifier = Modifier.clickable { onOpenEntry(e.vehicleId, e.id) },
                    headlineContent = { Text(e.entryType.displayName) },
                    supportingContent = {
                        Text(listOfNotNull(Formatters.date(e.entryDate), e.shopName, Formatters.odometer(e.odometerReading)).joinToString(" - "))
                    },
                    trailingContent = { Text(Formatters.currency(e.cost)) },
                )
            }
        }
    }
}
