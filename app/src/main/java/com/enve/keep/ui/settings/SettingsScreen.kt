package com.enve.keep.ui.settings

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings as AndroidSettings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import com.enve.keep.KeepApplication
import com.enve.keep.R
import com.enve.keep.data.Settings
import com.enve.keep.data.ThemeMode
import com.enve.keep.data.backup.InvalidBackupException
import com.enve.keep.domain.Money
import com.enve.keep.reminders.ReminderNotifications
import com.enve.keep.reminders.ReminderScheduler
import com.enve.keep.ui.components.BackButton
import com.enve.keep.ui.components.ConfirmDialog
import com.enve.keep.ui.components.CurrencyField
import com.enve.keep.ui.components.SectionHeader
import com.enve.keep.ui.keepViewModel
import kotlinx.coroutines.launch
import java.time.LocalDate

sealed interface SettingsMessage {
    data object Exported : SettingsMessage
    data class Imported(val records: Int, val attachments: Int) : SettingsMessage
    data class Failed(val invalid: Boolean) : SettingsMessage
}

class SettingsViewModel(private val app: KeepApplication) : ViewModel() {
    private val repository = app.container.settingsRepository
    val settings = repository.settings

    var busy by mutableStateOf(false)
        private set
    var message by mutableStateOf<SettingsMessage?>(null)

    fun update(transform: (Settings) -> Settings, recheck: Boolean = false) {
        viewModelScope.launch {
            repository.update(transform)
            if (recheck) ReminderScheduler.checkNow(app)
        }
    }

    fun export(uri: Uri) = runBackupTask {
        app.container.backupManager.export(uri)
        SettingsMessage.Exported
    }

    fun import(uri: Uri) = runBackupTask {
        val summary = app.container.backupManager.import(uri)
        ReminderScheduler.checkNow(app)
        SettingsMessage.Imported(summary.products + summary.subscriptions + summary.documents, summary.attachments)
    }

    private fun runBackupTask(task: suspend () -> SettingsMessage) {
        if (busy) return
        busy = true
        viewModelScope.launch {
            message = try {
                task()
            } catch (e: InvalidBackupException) {
                SettingsMessage.Failed(invalid = true)
            } catch (e: Exception) {
                SettingsMessage.Failed(invalid = false)
            }
            busy = false
        }
    }
}

private val LEAD_DAY_OPTIONS = listOf(1, 3, 7, 14, 30, 60, 90)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(navController: NavController) {
    val viewModel = keepViewModel { app, _ -> SettingsViewModel(app) }
    val settings by viewModel.settings.collectAsStateWithLifecycle(null)
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    var pendingImport by rememberSaveable { mutableStateOf<String?>(null) }

    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        uri?.let(viewModel::export)
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        pendingImport = uri?.toString()
    }

    val messageText = when (val message = viewModel.message) {
        null -> null
        SettingsMessage.Exported -> stringResource(R.string.backup_exported)
        is SettingsMessage.Imported -> stringResource(
            R.string.backup_imported,
            pluralStringResource(R.plurals.records_count, message.records, message.records),
            pluralStringResource(R.plurals.attachments_count, message.attachments, message.attachments),
        )
        is SettingsMessage.Failed -> stringResource(if (message.invalid) R.string.backup_invalid else R.string.backup_failed)
    }
    LaunchedEffect(messageText) {
        if (messageText != null) {
            snackbar.showSnackbar(messageText)
            viewModel.message = null
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_settings)) },
                navigationIcon = { BackButton { navController.popBackStack() } },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        val current = settings ?: return@Scaffold
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, bottom = 32.dp),
        ) {
            SectionHeader(stringResource(R.string.settings_appearance))
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                ThemeMode.entries.forEachIndexed { index, mode ->
                    SegmentedButton(
                        selected = current.themeMode == mode,
                        onClick = { viewModel.update({ it.copy(themeMode = mode) }) },
                        shape = SegmentedButtonDefaults.itemShape(index, ThemeMode.entries.size),
                        label = { Text(stringResource(mode.label)) },
                    )
                }
            }

            SectionHeader(stringResource(R.string.settings_reminders))
            ReminderToggle(current.remindersEnabled) { enabled ->
                viewModel.update({ it.copy(remindersEnabled = enabled) }, recheck = enabled)
            }
            if (current.remindersEnabled) {
                NotificationAccessRow()
                LeadDaysField(stringResource(R.string.settings_lead_warranty), current.warrantyLeadDays) { days ->
                    viewModel.update({ it.copy(warrantyLeadDays = days) }, recheck = true)
                }
                LeadDaysField(stringResource(R.string.settings_lead_subscription), current.subscriptionLeadDays) { days ->
                    viewModel.update({ it.copy(subscriptionLeadDays = days) }, recheck = true)
                }
                LeadDaysField(stringResource(R.string.settings_lead_document), current.documentLeadDays) { days ->
                    viewModel.update({ it.copy(documentLeadDays = days) }, recheck = true)
                }
                Text(
                    stringResource(R.string.settings_reminder_schedule),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            SectionHeader(stringResource(R.string.settings_defaults))
            var currency by rememberSaveable { mutableStateOf(current.defaultCurrency) }
            CurrencyField(currency, { code ->
                currency = code
                if (Money.currency(code) != null) viewModel.update({ it.copy(defaultCurrency = code) })
            })

            SectionHeader(stringResource(R.string.settings_backup))
            Text(
                stringResource(R.string.settings_backup_body),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (viewModel.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(
                    onClick = { exportLauncher.launch("enve-keep-backup-${LocalDate.now()}.zip") },
                    enabled = !viewModel.busy,
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Outlined.Upload, contentDescription = null)
                    Text(stringResource(R.string.action_export), modifier = Modifier.padding(start = 8.dp))
                }
                OutlinedButton(
                    onClick = { importLauncher.launch(arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream")) },
                    enabled = !viewModel.busy,
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Outlined.Download, contentDescription = null)
                    Text(stringResource(R.string.action_import), modifier = Modifier.padding(start = 8.dp))
                }
            }

            SectionHeader(stringResource(R.string.settings_about))
            val version = remember {
                runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull()
            }
            Text(stringResource(R.string.about_version, version.orEmpty()), style = MaterialTheme.typography.bodyMedium)
            Text(
                stringResource(R.string.about_privacy),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                stringResource(R.string.about_license),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    pendingImport?.let { uri ->
        ConfirmDialog(
            title = stringResource(R.string.import_confirm_title),
            text = stringResource(R.string.import_confirm_body),
            confirmLabel = stringResource(R.string.action_replace),
            onConfirm = { viewModel.import(uri.toUri()) },
            onDismiss = { pendingImport = null },
        )
    }
}

private val ThemeMode.label: Int
    get() = when (this) {
        ThemeMode.SYSTEM -> R.string.theme_system
        ThemeMode.LIGHT -> R.string.theme_light
        ThemeMode.DARK -> R.string.theme_dark
    }

@Composable
private fun ReminderToggle(enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .toggleable(value = enabled, role = Role.Switch, onValueChange = onChange)
            .padding(vertical = 4.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.settings_reminders_toggle), style = MaterialTheme.typography.bodyLarge)
            Text(
                stringResource(R.string.settings_reminders_toggle_body),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(checked = enabled, onCheckedChange = null)
    }
}

@Composable
private fun NotificationAccessRow() {
    val context = LocalContext.current
    var allowed by remember { mutableStateOf(ReminderNotifications.canPost(context)) }
    var askedOnce by rememberSaveable { mutableStateOf(false) }
    LifecycleResumeEffect(Unit) {
        allowed = ReminderNotifications.canPost(context)
        onPauseOrDispose {}
    }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        askedOnce = true
        allowed = granted && ReminderNotifications.canPost(context)
        if (allowed) ReminderScheduler.checkNow(context)
    }
    if (allowed) return
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            stringResource(R.string.settings_notifications_blocked),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error,
        )
        OutlinedButton(onClick = {
            if (Build.VERSION.SDK_INT >= 33 && !askedOnce) {
                request.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                context.startActivity(
                    Intent(AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(AndroidSettings.EXTRA_APP_PACKAGE, context.packageName)
                )
            }
        }) { Text(stringResource(R.string.action_allow_notifications)) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LeadDaysField(label: String, days: Int, onChange: (Int) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded, { expanded = it }) {
        OutlinedTextField(
            value = pluralStringResource(R.plurals.days_before, days, days),
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded, { expanded = false }) {
            LEAD_DAY_OPTIONS.forEach { option ->
                DropdownMenuItem(
                    text = { Text(pluralStringResource(R.plurals.days_before, option, option)) },
                    onClick = {
                        onChange(option)
                        expanded = false
                    },
                )
            }
        }
    }
}
