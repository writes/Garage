package com.writes.garage.feature.garage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.domain.RecallRules
import com.writes.garage.core.model.Recall
import com.writes.garage.core.model.RecallStatus
import com.writes.garage.feature.shared.DateField
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.FormTextField
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.appViewModel
import java.time.LocalDate
import java.time.ZoneOffset

@Composable
fun RecallsScreen(vehicleId: String, onBack: () -> Unit) {
    val vm = appViewModel(key = "recalls-$vehicleId") { RecallsViewModel(it.functions, it.vehicles, it.recalls, vehicleId) }
    val s by vm.state.collectAsState()
    var completing by remember { mutableStateOf<Recall?>(null) }
    var adding by remember { mutableStateOf(false) }

    completing?.let { r ->
        CompleteRecallDialog(
            onDismiss = { completing = null },
            onConfirm = { shop, odo, date ->
                vm.markCompleted(r, shop, odo, date.atTime(12, 0).toInstant(ZoneOffset.UTC))
                completing = null
            },
        )
    }
    if (adding) {
        AddRecallDialog(onDismiss = { adding = false }, onAdd = { t, c, comp, d -> if (vm.addManual(t, c, comp, d)) adding = false })
    }

    ScreenColumn("Recalls") {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onBack) { Text("Back") }
                Button(onClick = vm::check, enabled = !s.checking) { Text(if (s.checking) "Checking..." else "Check for recalls") }
                OutlinedButton(onClick = { adding = true }) { Text("Add") }
            }
        }
        item { ErrorText(s.error) }
        s.lastCheck?.let { item { Text(it, style = MaterialTheme.typography.bodySmall) } }
        if (s.urgent.isNotEmpty()) {
            item { UrgentRecallBanner(s.urgent) }
        }
        if (s.recalls.isEmpty() && !s.checking && s.error == null) {
            item { EmptyState("No recalls on file. Check the VIN against NHTSA or add one manually.") }
        }
        items(s.recalls, key = { it.id }) { r ->
            RecallCard(
                r,
                onComplete = { completing = r },
                onNotApplicable = { vm.markNotApplicable(r) },
                onReopen = { vm.reopen(r) },
            )
        }
    }
}

/** Do-not-drive / park-outside advisories must never be flattened into ordinary text. */
@Composable
fun UrgentRecallBanner(urgent: List<Recall>, modifier: Modifier = Modifier) {
    val doNotDrive = urgent.any(RecallRules::isDoNotDrive)
    Card(
        modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                if (doNotDrive) "SAFETY: DO NOT DRIVE" else "SAFETY: PARK OUTSIDE",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
            Text(
                "${urgent.size} open recall${if (urgent.size == 1) "" else "s"} carry an urgent NHTSA advisory. " +
                    "Contact a dealer before driving.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
}

@Composable
private fun RecallCard(r: Recall, onComplete: () -> Unit, onNotApplicable: () -> Unit, onReopen: () -> Unit) {
    val urgent = RecallRules.isOutstanding(r) && (RecallRules.isDoNotDrive(r) || RecallRules.isParkOutside(r))
    Card(
        Modifier.fillMaxWidth(),
        colors = if (urgent) CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer) else CardDefaults.cardColors(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                listOfNotNull(r.status.label(), r.campaignNumber).joinToString(" - ").uppercase(),
                style = MaterialTheme.typography.labelSmall,
                color = if (urgent) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(r.title, style = MaterialTheme.typography.titleMedium)
            listOfNotNull(r.componentAffected, r.dateAnnounced?.let { "Announced ${Formatters.date(it)}" }).takeIf { it.isNotEmpty() }
                ?.let { Text(it.joinToString(" - "), style = MaterialTheme.typography.bodySmall) }
            r.description?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            r.notes?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (urgent) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                )
            }
            if (r.status == RecallStatus.COMPLETED) {
                val parts = listOfNotNull(
                    r.completedDate?.let { Formatters.date(it) }, r.completedShop, r.completedOdometer?.let { Formatters.odometer(it) },
                )
                if (parts.isNotEmpty()) Text("Completed: ${parts.joinToString(" - ")}", style = MaterialTheme.typography.bodySmall)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (r.status == RecallStatus.OUTSTANDING) {
                    TextButton(onClick = onComplete) { Text("Mark completed") }
                    TextButton(onClick = onNotApplicable) { Text("Not applicable") }
                } else {
                    TextButton(onClick = onReopen) { Text("Reopen") }
                }
            }
        }
    }
}

private fun RecallStatus.label() = when (this) {
    RecallStatus.OUTSTANDING -> "Outstanding"
    RecallStatus.COMPLETED -> "Completed"
    RecallStatus.NOT_APPLICABLE -> "Not applicable"
}

@Composable
private fun CompleteRecallDialog(onDismiss: () -> Unit, onConfirm: (shop: String, odometer: String, date: LocalDate) -> Unit) {
    var shop by remember { mutableStateOf("") }
    var odo by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(LocalDate.now()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Recall completed") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                DateField("Completed on", date, onPick = { d -> d?.let { date = it } })
                FormTextField("Shop", shop, { shop = it })
                FormTextField("Odometer", odo, { odo = it.filter(Char::isDigit) }, keyboardType = KeyboardType.Number)
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(shop, odo, date) }) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun AddRecallDialog(onDismiss: () -> Unit, onAdd: (title: String, campaign: String, component: String, description: String) -> Unit) {
    var title by remember { mutableStateOf("") }
    var campaign by remember { mutableStateOf("") }
    var component by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add recall") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FormTextField("Title", title, { title = it }, required = true)
                FormTextField("Campaign number", campaign, { campaign = it })
                FormTextField("Component", component, { component = it })
                FormTextField("Description", description, { description = it }, singleLine = false)
            }
        },
        confirmButton = { TextButton(onClick = { onAdd(title, campaign, component, description) }) { Text("Add") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
