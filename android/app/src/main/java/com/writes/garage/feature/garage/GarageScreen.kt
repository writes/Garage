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
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.model.Vehicle
import com.writes.garage.feature.shared.ConfirmDialog
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ProGate
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.appViewModel

@Composable
fun GarageScreen(
    onAddVehicle: () -> Unit,
    onEditVehicle: (String) -> Unit,
    onRecalls: (String) -> Unit,
    onUpgrade: () -> Unit,
) {
    val vm = appViewModel { GarageViewModel(it.vehicles, it.purchases) }
    val state by vm.state.collectAsState()
    val error by vm.error.collectAsState()
    var pendingDelete by remember { mutableStateOf<Vehicle?>(null) }

    pendingDelete?.let { v ->
        ConfirmDialog(
            title = "Delete ${v.displayName}?",
            message = "The vehicle and its log are removed from your garage.",
            confirmLabel = "Delete",
            onConfirm = { vm.delete(v.id); pendingDelete = null },
            onDismiss = { pendingDelete = null },
        )
    }

    ScreenColumn("Garage") {
        item {
            ProGate(
                isPro = state.canAdd,
                onUpgrade = onUpgrade,
                lockedMessage = "Your plan includes ${state.limit} vehicle${if (state.limit == 1) "" else "s"}. " +
                    "Upgrade to Garage Pro for up to 5.",
            ) {
                Button(onClick = onAddVehicle) { Text("Add vehicle (${state.vehicles.size}/${state.limit})") }
            }
        }
        item { ErrorText(error) }
        if (state.vehicles.isEmpty()) item { EmptyState("Your garage is empty.") }
        items(state.vehicles, key = { it.id }) { v ->
            VehicleCard(
                vehicle = v,
                active = v.id == state.activeId,
                onSelect = { vm.select(v.id) },
                onEdit = { onEditVehicle(v.id) },
                onRecalls = { onRecalls(v.id) },
                onDelete = { pendingDelete = v },
            )
        }
    }
}

@Composable
private fun VehicleCard(
    vehicle: Vehicle,
    active: Boolean,
    onSelect: () -> Unit,
    onEdit: () -> Unit,
    onRecalls: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (active) Text("ACTIVE", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            Text(vehicle.displayName, style = MaterialTheme.typography.titleMedium)
            Text(
                "${vehicle.year} ${vehicle.make} ${vehicle.model} - ${Formatters.odometer(vehicle.currentOdometer)}",
                style = MaterialTheme.typography.bodyMedium,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (!active) TextButton(onClick = onSelect) { Text("Set active") }
                TextButton(onClick = onEdit) { Text("Edit") }
                TextButton(onClick = onRecalls) { Text("Recalls") }
                TextButton(onClick = onDelete) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}
