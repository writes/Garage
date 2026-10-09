package com.writes.garage.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.writes.garage.core.domain.AccentScheme
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ProGate
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.appViewModel

@Composable
fun ThemeScreen(onBack: () -> Unit, onUpgrade: () -> Unit) {
    val vm = appViewModel { ThemeViewModel(it.profile, it.purchases) }
    val s by vm.state.collectAsState()

    ScreenColumn("Theme") {
        item {
            ProGate(isPro = s.isPro, onUpgrade = onUpgrade, lockedMessage = "Themes are part of Garage Pro. Preview the accents below.") {
                Text("Recolors buttons and highlights across the app, instantly.", style = MaterialTheme.typography.bodyMedium)
            }
        }
        item { ErrorText(s.error) }
        s.schemes.forEach { (scheme, locked) ->
            item(key = scheme.id) {
                ListItem(
                    modifier = Modifier.clickable { if (!vm.select(scheme)) onUpgrade() },
                    leadingContent = { Swatch(scheme) },
                    headlineContent = { Text(scheme.displayName) },
                    trailingContent = {
                        when {
                            locked -> Text("Pro", style = MaterialTheme.typography.labelMedium)
                            (s.selected ?: AccentScheme.CLASSIC) == scheme -> Text("Selected", color = MaterialTheme.colorScheme.primary)
                        }
                    },
                )
            }
        }
        item { OutlinedButton(onClick = onBack) { Text("Back") } }
    }
}

@Composable
private fun Swatch(scheme: AccentScheme) {
    // Dark swatch (the app is dark-first); Classic shows the default accent.
    val color = scheme.darkArgb?.let { Color(it) } ?: MaterialTheme.colorScheme.primary
    Box(Modifier.size(28.dp).clip(CircleShape).background(color))
}
