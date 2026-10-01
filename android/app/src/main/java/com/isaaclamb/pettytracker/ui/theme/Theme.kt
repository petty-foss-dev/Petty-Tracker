package com.isaaclamb.pettytracker.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.isaaclamb.pettytracker.data.ThemeMode

// The Petty palette: cool grays around a blue-green accent, plain and functional.
private val Light = lightColorScheme(
    primary = Color(0xFF0F7A8A),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFE2F1F3),
    onPrimaryContainer = Color(0xFF0F6573),
    secondary = Color(0xFF0F7A8A),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFE2F1F3),
    onSecondaryContainer = Color(0xFF0F6573),
    tertiary = Color(0xFF0F7A8A),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFE2F1F3),
    onTertiaryContainer = Color(0xFF1B2328),
    error = Color(0xFFB23A31),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFF7E4E2),
    onErrorContainer = Color(0xFFB23A31),
    background = Color(0xFFF3F5F6),
    onBackground = Color(0xFF1B2328),
    surface = Color(0xFFF3F5F6),
    onSurface = Color(0xFF1B2328),
    surfaceVariant = Color(0xFFFFFFFF),
    onSurfaceVariant = Color(0xFF5C6870),
    outline = Color(0xFF7A858C),
    outlineVariant = Color(0xFFDDE2E5),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFFFFFF),
    surfaceContainer = Color(0xFFEAEEF0),
    surfaceContainerHigh = Color(0xFFFFFFFF),
    surfaceContainerHighest = Color(0xFFE4E8EA),
)

private fun dark(pureBlack: Boolean): ColorScheme {
    val background = if (pureBlack) Color.Black else Color(0xFF0E1113)
    val elevated = if (pureBlack) Color(0xFF0B0D0E) else Color(0xFF181D20)
    return darkColorScheme(
        primary = Color(0xFF4FC1C9),
        onPrimary = Color(0xFF0B1F22),
        primaryContainer = Color(0xFF173238),
        onPrimaryContainer = Color(0xFF7FD3D9),
        secondary = Color(0xFF4FC1C9),
        onSecondary = Color(0xFF0B1F22),
        secondaryContainer = Color(0xFF173238),
        onSecondaryContainer = Color(0xFF7FD3D9),
        tertiary = Color(0xFF4FC1C9),
        onTertiary = Color(0xFF0B1F22),
        tertiaryContainer = Color(0xFF173238),
        onTertiaryContainer = Color(0xFFE6EBEE),
        error = Color(0xFFEE8277),
        onError = Color(0xFF2A0F0C),
        errorContainer = Color(0xFF3A201E),
        onErrorContainer = Color(0xFFF4A79F),
        background = background,
        onBackground = Color(0xFFE6EBEE),
        surface = background,
        onSurface = Color(0xFFE6EBEE),
        surfaceVariant = elevated,
        onSurfaceVariant = Color(0xFF9AA5AC),
        outline = Color(0xFF707B82),
        outlineVariant = Color(0xFF262C30),
        surfaceContainerLowest = background,
        surfaceContainerLow = elevated,
        surfaceContainer = if (pureBlack) Color(0xFF0B0D0E) else Color(0xFF13171A),
        surfaceContainerHigh = elevated,
        surfaceContainerHighest = if (pureBlack) Color(0xFF17191A) else Color(0xFF22292D),
    )
}

@Immutable
data class StatusColors(
    val soon: Color,
    val soonContainer: Color,
    val ok: Color,
    val okContainer: Color,
)

private val LightStatus = StatusColors(
    soon = Color(0xFF9A6400),
    soonContainer = Color(0xFFF6EEDC),
    ok = Color(0xFF2F7D55),
    okContainer = Color(0xFFE3F1E9),
)

private val DarkStatus = StatusColors(
    soon = Color(0xFFE2B04A),
    soonContainer = Color(0xFF362C17),
    ok = Color(0xFF6CC79A),
    okContainer = Color(0xFF1C3229),
)

val LocalStatusColors = staticCompositionLocalOf { LightStatus }

@Composable
fun ThemeMode.isDark(): Boolean = when (this) {
    ThemeMode.SYSTEM -> isSystemInDarkTheme()
    ThemeMode.LIGHT -> false
    ThemeMode.DARK -> true
}

@Composable
fun TrackerTheme(dark: Boolean, pureBlack: Boolean, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalStatusColors provides if (dark) DarkStatus else LightStatus) {
        MaterialTheme(colorScheme = if (dark) dark(pureBlack) else Light, content = content)
    }
}
