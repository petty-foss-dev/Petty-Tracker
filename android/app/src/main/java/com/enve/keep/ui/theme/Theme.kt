package com.enve.keep.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.enve.keep.data.ThemeMode

private val LightColors = lightColorScheme(
    primary = Color(0xFF2E6A5C),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFCDE9DF),
    onPrimaryContainer = Color(0xFF0A2B23),
    secondary = Color(0xFF52635E),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFDCE7E2),
    onSecondaryContainer = Color(0xFF111F1B),
    tertiary = Color(0xFF4A6178),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFD2E4FA),
    onTertiaryContainer = Color(0xFF041D31),
    error = Color(0xFFB0302A),
    errorContainer = Color(0xFFFADAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFF6F8F6),
    onBackground = Color(0xFF191C1B),
    surface = Color(0xFFF6F8F6),
    onSurface = Color(0xFF191C1B),
    surfaceVariant = Color(0xFFDDE4E0),
    onSurfaceVariant = Color(0xFF414945),
    outline = Color(0xFF717975),
    outlineVariant = Color(0xFFC1C8C4),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF0F3F1),
    surfaceContainer = Color(0xFFEAEEEC),
    surfaceContainerHigh = Color(0xFFE4E9E6),
    surfaceContainerHighest = Color(0xFFDEE3E0),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF93D3C2),
    onPrimary = Color(0xFF00382D),
    primaryContainer = Color(0xFF145143),
    onPrimaryContainer = Color(0xFFAFEFDD),
    secondary = Color(0xFFB6CBC4),
    onSecondary = Color(0xFF21352F),
    secondaryContainer = Color(0xFF384B45),
    onSecondaryContainer = Color(0xFFD2E7DF),
    tertiary = Color(0xFFB2C9E3),
    onTertiary = Color(0xFF1B3247),
    tertiaryContainer = Color(0xFF33495F),
    onTertiaryContainer = Color(0xFFD2E4FA),
    error = Color(0xFFFFB4AB),
    errorContainer = Color(0xFF8C1D18),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF101413),
    onBackground = Color(0xFFE0E3E1),
    surface = Color(0xFF101413),
    onSurface = Color(0xFFE0E3E1),
    surfaceVariant = Color(0xFF3F4945),
    onSurfaceVariant = Color(0xFFBFC9C4),
    outline = Color(0xFF89938E),
    outlineVariant = Color(0xFF3F4945),
    surfaceContainerLowest = Color(0xFF0B0F0E),
    surfaceContainerLow = Color(0xFF181C1B),
    surfaceContainer = Color(0xFF1C201F),
    surfaceContainerHigh = Color(0xFF262B29),
    surfaceContainerHighest = Color(0xFF313634),
)

@Immutable
data class StatusColors(
    val soon: Color,
    val onSoon: Color,
    val soonContainer: Color,
    val onSoonContainer: Color,
)

private val LightStatus = StatusColors(
    soon = Color(0xFF8A5100),
    onSoon = Color(0xFFFFFFFF),
    soonContainer = Color(0xFFFFDDB8),
    onSoonContainer = Color(0xFF2C1600),
)

private val DarkStatus = StatusColors(
    soon = Color(0xFFFFB961),
    onSoon = Color(0xFF482900),
    soonContainer = Color(0xFF693C00),
    onSoonContainer = Color(0xFFFFDDB8),
)

val LocalStatusColors = staticCompositionLocalOf { LightStatus }

@Composable
fun ThemeMode.isDark(): Boolean = when (this) {
    ThemeMode.SYSTEM -> isSystemInDarkTheme()
    ThemeMode.LIGHT -> false
    ThemeMode.DARK -> true
}

@Composable
fun KeepTheme(dark: Boolean, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalStatusColors provides if (dark) DarkStatus else LightStatus) {
        MaterialTheme(colorScheme = if (dark) DarkColors else LightColors, content = content)
    }
}
