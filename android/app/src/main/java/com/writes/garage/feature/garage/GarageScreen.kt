package com.writes.garage.feature.garage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
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

/** Per-vehicle record screens reachable from a vehicle card. */
enum class GarageSection(val label: String) {
    WARRANTIES("Warranty"),
    GALLERY("Photos"),
    WHEELS("Wheels"),
    PARTS("Spare parts"),
    DETAILING("Detailing"),
}

@Composable
fun GarageScreen(
    onAddVehicle: () -> Unit,
    onEditVehicle: (String) -> Unit,
    onRecalls: (String) -> Unit,
    onUpgrade: () -> Unit,
    onOpenSection: (GarageSection, String) -> Unit = { _, _ -> },
) {
    val vm = appViewModel { GarageViewModel(it.vehicles, it.purchases, it.recalls) }
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
        if (!state.isPro && state.vehicles.isNotEmpty()) {
            // Parity with iOS: photos, wheels, parts, detailing, warranty and recalls are Pro (they also write to Storage).
            item {
                ProGate(
                    isPro = false,
                    onUpgrade = onUpgrade,
                    lockedMessage = "Garage tools are part of Pro. Spare parts, detailing, warranty, photos, wheels, and recalls unlock with Pro.",
                ) {}
            }
        }
        if (state.vehicles.isEmpty()) item { EmptyState("Your garage is empty.") }
        items(state.vehicles, key = { it.id }) { v ->
            VehicleCard(
                vehicle = v,
                active = v.id == state.activeId,
                isPro = state.isPro,
                onSelect = { vm.select(v.id) },
                onEdit = { onEditVehicle(v.id) },
                onRecalls = { onRecalls(v.id) },
                openRecalls = state.openRecalls[v.id] ?: 0,
                onSection = { onOpenSection(it, v.id) },
                onDelete = { pendingDelete = v },
            )
        }
    }
}

@Composable
private fun VehicleCard(
    vehicle: Vehicle,
    active: Boolean,
    isPro: Boolean,
    onSelect: () -> Unit,
    onEdit: () -> Unit,
    onRecalls: () -> Unit,
    openRecalls: Int,
    onSection: (GarageSection) -> Unit,
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
                if (isPro) {
                    TextButton(onClick = onRecalls) {
                        Text(
                            if (openRecalls > 0) "Recalls ($openRecalls open)" else "Recalls",
                            color = if (openRecalls > 0) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                        )
                    }
                }
                TextButton(onClick = onDelete) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            }
            if (isPro) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    GarageSection.entries.forEach { sec -> OutlinedButton(onClick = { onSection(sec) }) { Text(sec.label) } }
                }
            }
        }
    }
}
