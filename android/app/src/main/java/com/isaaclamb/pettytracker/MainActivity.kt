package com.isaaclamb.pettytracker

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.ui.TrackerApp
import com.isaaclamb.pettytracker.ui.OpenRecord
import com.isaaclamb.pettytracker.ui.theme.TrackerTheme
import com.isaaclamb.pettytracker.ui.theme.isDark

class MainActivity : ComponentActivity() {
    private var openRequest by mutableStateOf<OpenRecord?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) openRequest = intent.toOpenRecord()
        val settingsRepository = (application as TrackerApplication).container.settingsRepository
        setContent {
            val settings by settingsRepository.settings.collectAsStateWithLifecycle(initialValue = null)
            val current = settings ?: return@setContent
            val dark = current.themeMode.isDark()
            LaunchedEffect(dark) {
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
            TrackerTheme(dark) {
                TrackerApp(openRequest = openRequest, onOpenHandled = { openRequest = null })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.toOpenRecord()?.let { openRequest = it }
    }

    private fun Intent.toOpenRecord(): OpenRecord? {
        val kind = getStringExtra(EXTRA_KIND)?.let { runCatching { RecordKind.valueOf(it) }.getOrNull() } ?: return null
        val id = getLongExtra(EXTRA_ID, 0).takeIf { it > 0 } ?: return null
        return OpenRecord(kind, id)
    }

    companion object {
        const val EXTRA_KIND = "com.isaaclamb.pettytracker.extra.KIND"
        const val EXTRA_ID = "com.isaaclamb.pettytracker.extra.ID"
    }
}
