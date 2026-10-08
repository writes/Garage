package com.writes.garage.feature.handover

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Formatters
import com.writes.garage.core.model.ReportSection
import com.writes.garage.feature.shared.DateField
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ProGate
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SwitchRow
import com.writes.garage.feature.shared.appViewModel

@Composable
fun HandoverScreen(onBack: () -> Unit, onUpgrade: () -> Unit = {}) {
    val app = LocalContext.current.applicationContext
    val vm = appViewModel {
        HandoverViewModel(
            it.vehicles, it.entries, it.reminders, it.functions, CacheExportFileStore(app), it.purchases.entitlement,
            records = HandoverRecords(it.recalls, it.warranties, it.parts, it.detailing, it.gallery, it.wear),
            storage = it.storage, analytics = it.analytics, reviews = it.reviews,
        )
    }
    val s by vm.state.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(s.pendingShare) {
        val f = s.pendingShare ?: return@LaunchedEffect
        shareExportedFile(context, f)
        vm.shareHandled()
    }

    ScreenColumn("Handover export") {
        val v = s.vehicle
        if (v == null) {
            item { EmptyState("Add a vehicle to export its records.") }
        } else {
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(v.displayName, style = MaterialTheme.typography.titleMedium)
                        Text(
                            "${s.entryCount} log entries - ${Formatters.odometer(v.currentOdometer)}",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
            item {
                Text(
                    "Share a resale-ready record of this vehicle. Files are created on this device and handed to the app you pick.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            if (s.busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            item { SectionHeader("Record PDF") }
            item {
                ProGate(isPro = s.isPro, onUpgrade = onUpgrade, lockedMessage = "The resale record PDF is a Garage Pro feature. CSV and calendar exports stay free.") {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        DateField("From (optional)", s.startDate, { vm.setStartDate(it) }, clearable = true)
                        DateField("To (optional)", s.endDate, { vm.setEndDate(it) }, clearable = true)
                        Text("Sections", style = MaterialTheme.typography.labelLarge)
                        ReportSection.entries.forEach { sec ->
                            SwitchRow(sec.title, sec in s.sections, { on -> vm.setSection(sec, on) })
                        }
                        Button(onClick = vm::exportPdf, enabled = !s.busy && s.sections.isNotEmpty(), modifier = Modifier.fillMaxWidth()) {
                            Text("Export PDF dossier")
                        }
                    }
                }
            }
            item { SectionHeader("Other exports") }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = vm::exportCsv, enabled = !s.busy && s.entryCount > 0, modifier = Modifier.fillMaxWidth()) {
                        Text("Export entries (CSV)")
                    }
                    OutlinedButton(onClick = vm::exportIcs, enabled = !s.busy && s.datedReminderCount > 0, modifier = Modifier.fillMaxWidth()) {
                        Text("Export reminders (ICS, ${s.datedReminderCount})")
                    }
                }
            }
            s.message?.let { item { Text(it, style = MaterialTheme.typography.bodySmall) } }
            item { ErrorText(s.error) }
        }
        item { OutlinedButton(onClick = onBack) { Text("Back") } }
    }
}
