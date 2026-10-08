package com.writes.garage.feature.garage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Formatters
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.appViewModel

@Composable
fun RecallsScreen(vehicleId: String, onBack: () -> Unit) {
    val vm = appViewModel(key = "recalls-$vehicleId") { RecallsViewModel(it.functions, it.vehicles, vehicleId) }
    val s by vm.state.collectAsState()

    ScreenColumn("Recalls") {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onBack) { Text("Back") }
                OutlinedButton(onClick = vm::refresh, enabled = !s.loading) { Text("Check again") }
            }
        }
        item { ErrorText(s.error) }
        if (s.loading) item { EmptyState("Checking...") }
        else if (s.error == null && s.recalls.isEmpty()) item { EmptyState("No open recalls found for this VIN.") }
        items(s.recalls, key = { it.id }) { r ->
            ListItem(
                overlineContent = { Text(listOfNotNull(r.status.wire.uppercase(), r.campaignNumber).joinToString(" - ")) },
                headlineContent = { Text(r.title) },
                supportingContent = {
                    Text(
                        listOfNotNull(
                            r.componentAffected,
                            r.dateAnnounced?.let { "Announced ${Formatters.date(it)}" },
                            r.description,
                        ).joinToString("\n"),
                    )
                },
            )
        }
    }
}
