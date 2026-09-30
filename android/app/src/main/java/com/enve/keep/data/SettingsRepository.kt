package com.enve.keep.data

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import java.util.Currency
import java.util.Locale

@Serializable
enum class ThemeMode { SYSTEM, LIGHT, DARK }

@Serializable
data class Settings(
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val remindersEnabled: Boolean = true,
    val warrantyLeadDays: Int = 30,
    val subscriptionLeadDays: Int = 7,
    val documentLeadDays: Int = 60,
    val defaultCurrency: String = localCurrency(),
    val reminderPromptDismissed: Boolean = false,
)

private fun localCurrency(): String =
    runCatching { Currency.getInstance(Locale.getDefault()).currencyCode }.getOrDefault("USD")

private val Context.dataStore by preferencesDataStore("settings")

class SettingsRepository(private val context: Context) {
    val settings: Flow<Settings> = context.dataStore.data.map { it.toSettings() }

    suspend fun current(): Settings = settings.first()

    suspend fun update(transform: (Settings) -> Settings) {
        context.dataStore.edit { prefs ->
            val next = transform(prefs.toSettings())
            prefs[THEME] = next.themeMode.name
            prefs[REMINDERS] = next.remindersEnabled
            prefs[WARRANTY_LEAD] = next.warrantyLeadDays
            prefs[SUBSCRIPTION_LEAD] = next.subscriptionLeadDays
            prefs[DOCUMENT_LEAD] = next.documentLeadDays
            prefs[CURRENCY] = next.defaultCurrency
            prefs[PROMPT_DISMISSED] = next.reminderPromptDismissed
        }
    }

    private fun Preferences.toSettings(): Settings {
        val defaults = Settings()
        return Settings(
            themeMode = this[THEME]?.let { runCatching { ThemeMode.valueOf(it) }.getOrNull() } ?: defaults.themeMode,
            remindersEnabled = this[REMINDERS] ?: defaults.remindersEnabled,
            warrantyLeadDays = this[WARRANTY_LEAD] ?: defaults.warrantyLeadDays,
            subscriptionLeadDays = this[SUBSCRIPTION_LEAD] ?: defaults.subscriptionLeadDays,
            documentLeadDays = this[DOCUMENT_LEAD] ?: defaults.documentLeadDays,
            defaultCurrency = this[CURRENCY] ?: defaults.defaultCurrency,
            reminderPromptDismissed = this[PROMPT_DISMISSED] ?: defaults.reminderPromptDismissed,
        )
    }

    private companion object {
        val THEME = stringPreferencesKey("theme_mode")
        val REMINDERS = booleanPreferencesKey("reminders_enabled")
        val WARRANTY_LEAD = intPreferencesKey("warranty_lead_days")
        val SUBSCRIPTION_LEAD = intPreferencesKey("subscription_lead_days")
        val DOCUMENT_LEAD = intPreferencesKey("document_lead_days")
        val CURRENCY = stringPreferencesKey("default_currency")
        val PROMPT_DISMISSED = booleanPreferencesKey("reminder_prompt_dismissed")
    }
}
