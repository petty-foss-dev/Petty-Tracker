package com.isaaclamb.pettytracker.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import com.isaaclamb.pettytracker.data.ThemeMode

// The Hearth palette shared with Enve Book Player: warm Ink and Paper surfaces around an ember accent.
private val Ember = Color(0xFFF5921A)
private val EmberOnPaper = Color(0xFF89520F)

private val Paper = lightColorScheme(
    primary = EmberOnPaper,
    onPrimary = Color(0xFFFFF7EA),
    primaryContainer = Color(0xFFFDEEDA),
    onPrimaryContainer = EmberOnPaper,
    secondary = EmberOnPaper,
    onSecondary = Color(0xFFFFF7EA),
    secondaryContainer = Color(0xFFFDEEDA),
    onSecondaryContainer = EmberOnPaper,
    tertiary = EmberOnPaper,
    onTertiary = Color(0xFFFFF7EA),
    tertiaryContainer = Color(0xFFFDEEDA),
    onTertiaryContainer = Color(0xFF231F1B),
    error = Color(0xFFA8453A),
    onError = Color(0xFFFFF7EA),
    errorContainer = Color(0xFFF3E5E3),
    onErrorContainer = Color(0xFFA8453A),
    background = Color(0xFFF7F2E9),
    onBackground = Color(0xFF231F1B),
    surface = Color(0xFFF7F2E9),
    onSurface = Color(0xFF231F1B),
    surfaceVariant = Color(0xFFFFFFFF),
    onSurfaceVariant = Color(0xFF6E6459),
    outline = Color(0xFF766B5F),
    outlineVariant = Color(0xFFE4DDD2),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFFFFFF),
    surfaceContainer = Color(0xFFF1EBE1),
    surfaceContainerHigh = Color(0xFFFFFFFF),
    surfaceContainerHighest = Color(0xFFEFE8DB),
)

private fun ink(pureBlack: Boolean): ColorScheme {
    val background = if (pureBlack) Color.Black else Color(0xFF0C0A09)
    val elevated = if (pureBlack) Color(0xFF0C0C0D) else Color(0xFF191512)
    return darkColorScheme(
        primary = Ember,
        onPrimary = Color(0xFF1A120A),
        primaryContainer = Color(0xFF412C13),
        onPrimaryContainer = Ember,
        secondary = Ember,
        onSecondary = Color(0xFF1A120A),
        secondaryContainer = Color(0xFF412C13),
        onSecondaryContainer = Ember,
        tertiary = Ember,
        onTertiary = Color(0xFF1A120A),
        tertiaryContainer = Color(0xFF412C13),
        onTertiaryContainer = Color(0xFFF0E9DC),
        error = Color(0xFFD06A5C),
        onError = Color(0xFF1A120A),
        errorContainer = Color(0xFF3E2621),
        onErrorContainer = Color(0xFFE79A8F),
        background = background,
        onBackground = Color(0xFFF0E9DC),
        surface = background,
        onSurface = Color(0xFFF0E9DC),
        surfaceVariant = elevated,
        onSurfaceVariant = Color(0xFFA99F92),
        outline = Color(0xFF80786D),
        outlineVariant = Color(0xFF2A2522),
        surfaceContainerLowest = background,
        surfaceContainerLow = elevated,
        surfaceContainer = if (pureBlack) Color(0xFF0C0C0D) else Color(0xFF141110),
        surfaceContainerHigh = elevated,
        surfaceContainerHighest = if (pureBlack) Color(0xFF1A1817) else Color(0xFF231E1A),
    )
}

@Immutable
data class StatusColors(
    val soon: Color,
    val soonContainer: Color,
    val ok: Color,
    val okContainer: Color,
)

private val PaperStatus = StatusColors(
    soon = Color(0xFF93601B),
    soonContainer = Color(0xFFEEE6DB),
    ok = Color(0xFF4F7942),
    okContainer = Color(0xFFE6ECE5),
)

private val InkStatus = StatusColors(
    soon = Color(0xFFE0A458),
    soonContainer = Color(0xFF3D2F1F),
    ok = Color(0xFF8FBF7F),
    okContainer = Color(0xFF2E3426),
)

val LocalStatusColors = staticCompositionLocalOf { PaperStatus }

/** Serif for screen titles and headline numbers, as in Enve Book Player; sans everywhere else. */
private val HearthTypography = Typography().run {
    copy(
        displayLarge = displayLarge.copy(fontFamily = FontFamily.Serif),
        displayMedium = displayMedium.copy(fontFamily = FontFamily.Serif),
        displaySmall = displaySmall.copy(fontFamily = FontFamily.Serif),
        headlineLarge = headlineLarge.copy(fontFamily = FontFamily.Serif),
        headlineMedium = headlineMedium.copy(fontFamily = FontFamily.Serif),
        headlineSmall = headlineSmall.copy(fontFamily = FontFamily.Serif),
        titleLarge = titleLarge.copy(fontFamily = FontFamily.Serif),
    )
}

@Composable
fun ThemeMode.isDark(): Boolean = when (this) {
    ThemeMode.SYSTEM -> isSystemInDarkTheme()
    ThemeMode.LIGHT -> false
    ThemeMode.DARK -> true
}

@Composable
fun TrackerTheme(dark: Boolean, pureBlack: Boolean, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalStatusColors provides if (dark) InkStatus else PaperStatus) {
        MaterialTheme(
            colorScheme = if (dark) ink(pureBlack) else Paper,
            typography = HearthTypography,
            content = content,
        )
    }
}
