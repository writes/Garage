package com.writes.garage.feature.stats

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.Formatters

data class BarDatum(val label: String, val value: Double)

/** Horizontal bar chart: label | bar drawn on a Canvas | value. Bars scale to the largest value. */
@Composable
fun HorizontalBarChart(data: List<BarDatum>, modifier: Modifier = Modifier, valueText: (Double) -> String = Formatters::currency) {
    val max = data.maxOfOrNull { it.value }?.takeIf { it > 0 } ?: return
    val bar = MaterialTheme.colorScheme.primary
    val track = MaterialTheme.colorScheme.surfaceVariant
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        data.forEach { d ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    d.label, modifier = Modifier.width(112.dp), maxLines = 1, overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.labelMedium,
                )
                Canvas(Modifier.weight(1f).height(14.dp)) {
                    val radius = CornerRadius(size.height / 2, size.height / 2)
                    drawRoundRect(track, size = size, cornerRadius = radius)
                    val w = (size.width * (d.value / max)).toFloat().coerceAtLeast(size.height)
                    drawRoundRect(bar, size = Size(w, size.height), cornerRadius = radius)
                }
                Text(valueText(d.value), modifier = Modifier.width(80.dp), style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

/** Simple line chart (values in order, left to right) with min/max captions. Needs at least two points. */
@Composable
fun LineChart(values: List<Double>, modifier: Modifier = Modifier, valueText: (Double) -> String = { "%.1f".format(it) }) {
    if (values.size < 2) return
    val line = MaterialTheme.colorScheme.primary
    val grid = MaterialTheme.colorScheme.surfaceVariant
    val lo = values.min()
    val hi = values.max()
    val span = (hi - lo).takeIf { it > 1e-9 } ?: 1.0
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("low ${valueText(lo)}", style = MaterialTheme.typography.labelSmall)
            Text("high ${valueText(hi)}", style = MaterialTheme.typography.labelSmall)
        }
        Canvas(Modifier.fillMaxWidth().height(140.dp)) {
            val pad = 8.dp.toPx()
            val w = size.width - 2 * pad
            val h = size.height - 2 * pad
            for (i in 0..2) {
                val y = pad + h * i / 2f
                drawLine(grid, Offset(pad, y), Offset(size.width - pad, y), strokeWidth = 1.dp.toPx())
            }
            fun point(i: Int) = Offset(
                pad + w * i / (values.size - 1),
                pad + h * (1f - ((values[i] - lo) / span).toFloat()),
            )
            val path = Path().apply {
                moveTo(point(0).x, point(0).y)
                for (i in 1 until values.size) lineTo(point(i).x, point(i).y)
            }
            drawPath(path, line, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round))
            for (i in values.indices) drawCircle(line, radius = 3.5.dp.toPx(), center = point(i))
        }
    }
}
