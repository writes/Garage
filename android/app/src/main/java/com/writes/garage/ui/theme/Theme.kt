package com.writes.garage.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Accent = Color(0xFFE5412D)

private val DarkColors = darkColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    secondary = Color(0xFFFFB4A8),
    background = Color(0xFF101114),
    onBackground = Color(0xFFF2F2F2),
    surface = Color(0xFF17181C),
    onSurface = Color(0xFFF2F2F2),
    surfaceVariant = Color(0xFF23252B),
    onSurfaceVariant = Color(0xFFB8BAC2),
    error = Color(0xFFFF6B5E),
)

private val LightColors = lightColorScheme(
    primary = Color(0xFFC62E1B),
    onPrimary = Color.White,
    background = Color(0xFFFAFAFA),
    surface = Color.White,
)

/** Dark-first automotive theme. */
@Composable
fun GarageTheme(darkTheme: Boolean = true, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (darkTheme) DarkColors else LightColors, content = content)
}
