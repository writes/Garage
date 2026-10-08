package com.writes.garage.feature.handover

import android.content.Intent
import android.net.Uri
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
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SwitchRow
import com.writes.garage.feature.shared.appViewModel

@Composable
fun HandoverScreen(onBack: () -> Unit) {
    val app = LocalContext.current.applicationContext
    val vm = appViewModel { HandoverViewModel(it.vehicles, it.entries, it.reminders, it.functions, CacheExportFileStore(app)) }
    val s by vm.state.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(s.pendingShare) {
        val f = s.pendingShare ?: return@LaunchedEffect
        val uri = Uri.parse(f.uri)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = f.mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, f.fileName)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = android.content.ClipData.newRawUri(f.fileName, uri)
        }
        runCatching { context.startActivity(Intent.createChooser(send, "Share ${f.fileName}")) }
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
            item { SwitchRow("Include open recalls in the PDF", s.includeRecalls, vm::setIncludeRecalls) }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = vm::exportPdf, enabled = !s.busy, modifier = Modifier.fillMaxWidth()) { Text("Export PDF dossier") }
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
