package com.writes.garage.feature.stats

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Formatters
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.appViewModel

@Composable
fun StatsScreen() {
    val vm = appViewModel { StatsViewModel(it.vehicles, it.entries, it.wear) }
    val s by vm.state.collectAsState()

    ScreenColumn("Stats") {
        if (s.vehicleName == null) {
            item { EmptyState("No vehicle selected.") }
            return@ScreenColumn
        }
        item { Text("${s.vehicleName} - ${s.entryCount} entries", style = MaterialTheme.typography.titleMedium) }

        item { SectionHeader("Cost of ownership") }
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(Formatters.currency(s.totalCostOfOwnership), style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.primary)
                    Text(
                        if (s.purchasePrice != null) "Purchase ${Formatters.currency(s.purchasePrice)} + ${Formatters.currency(s.totalCost)} logged"
                        else "${Formatters.currency(s.totalCost)} logged (add a purchase price in Garage to include it)",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
        item { Metric("Cost per mile", Formatters.costPerMile(s.summary?.costPerMile)) }
        item { Metric("Cost per month", Formatters.currency(s.summary?.costPerMonth)) }
        item { Metric("Miles covered by log", s.summary?.milesCovered?.let { Formatters.odometer(it) } ?: "-") }

        item { SectionHeader("Cost by type") }
        if (s.costByType.isEmpty()) {
            item { EmptyState("No costs logged yet.") }
        } else {
            item { HorizontalBarChart(s.costByType.map { (type, cost) -> BarDatum(type.displayName, cost) }) }
        }

        item { SectionHeader("Fuel economy") }
        item { Metric("Average", Formatters.mpg(s.averageMpg)) }
        if (s.mpgSeries.size >= 2) {
            item { LineChart(s.mpgSeries.map { it.mpg }, valueText = { Formatters.mpg(it) }) }
            item { Text("MPG per fill-up, oldest to newest", style = MaterialTheme.typography.labelSmall) }
        } else {
            item { EmptyState("Log at least two fill-ups with gallons to see a trend.") }
        }

        if (s.wearHistory.isNotEmpty()) {
            item { SectionHeader("Wear history") }
            s.wearHistory.forEach { w ->
                item(key = "wear-${w.item.wire}") {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(w.item.label, style = MaterialTheme.typography.labelLarge)
                        LineChart(w.points, valueText = { "${Math.round(it)}%" })
                    }
                }
            }
        }

        s.trackDay?.let { t ->
            item { SectionHeader("Track days") }
            item { Metric("Events", t.events.toString()) }
            item { Metric("Total spent", Formatters.currency(t.totalCost)) }
            item { Metric("Laps", t.totalLaps.toString()) }
            item { Metric("Heat cycles added", t.heatCycles.toString()) }
            item { Metric("Best lap", t.bestLapLabel?.let { l -> t.bestLapVenue?.let { "$l @ $it" } ?: l } ?: "-") }
            if (t.venues.isNotEmpty()) item { Metric("Venues", t.venues.joinToString(", ")) }
        }
    }
}

@Composable
private fun Metric(label: String, value: String) {
    ListItem(headlineContent = { Text(label) }, trailingContent = { Text(value) })
}
