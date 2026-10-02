package com.isaaclamb.pettytracker.ui.dashboard

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.domain.Money
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.reminders.ReminderNotifications
import com.isaaclamb.pettytracker.reminders.ReminderScheduler
import com.isaaclamb.pettytracker.ui.SearchRoute
import com.isaaclamb.pettytracker.ui.SettingsRoute
import com.isaaclamb.pettytracker.ui.Tab
import com.isaaclamb.pettytracker.ui.TrackerNavigationBar
import com.isaaclamb.pettytracker.ui.components.ActionTile
import com.isaaclamb.pettytracker.ui.components.EmptyState
import com.isaaclamb.pettytracker.ui.components.RecordCard
import com.isaaclamb.pettytracker.ui.components.SectionHeader
import com.isaaclamb.pettytracker.ui.components.deadlineText
import com.isaaclamb.pettytracker.ui.components.icon
import com.isaaclamb.pettytracker.ui.components.label
import com.isaaclamb.pettytracker.ui.createRecord
import com.isaaclamb.pettytracker.ui.openRecord
import com.isaaclamb.pettytracker.ui.selectTab
import com.isaaclamb.pettytracker.ui.theme.LocalStatusColors
import com.isaaclamb.pettytracker.ui.trackerViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, _ -> DashboardViewModel(app) }
    val state by viewModel.state.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.app_name)) },
                actions = {
                    IconButton(onClick = { navController.navigate(SearchRoute) }) {
                        Icon(Icons.Outlined.Search, contentDescription = stringResource(R.string.action_search))
                    }
                    IconButton(onClick = { navController.navigate(SettingsRoute) }) {
                        Icon(Icons.Outlined.Settings, contentDescription = stringResource(R.string.title_settings))
                    }
                },
            )
        },
        bottomBar = { TrackerNavigationBar(navController) },
    ) { padding ->
        if (!state.loaded) return@Scaffold
        LazyColumn(
            contentPadding = PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = padding.calculateTopPadding() + 4.dp,
                bottom = padding.calculateBottomPadding() + 24.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            if (state.remindersEnabled && !state.reminderPromptDismissed) {
                item { ReminderPermissionCard(onDismiss = viewModel::dismissReminderPrompt) }
            }
            if (state.isEmpty) {
                item { WelcomeState(onCreate = { navController.createRecord(it) }) }
                return@LazyColumn
            }
            item {
                SummaryTiles(state, onMonthlyClick = { navController.selectTab(Tab.SUBSCRIPTIONS) })
            }
            item { QuickAddRow(onCreate = { navController.createRecord(it) }) }
            if (state.pastDue.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.section_needs_attention)) }
                items(state.pastDue, key = { "past-${it.deadline.kind}-${it.deadline.id}" }) { entry ->
                    DeadlineCard(entry, navController, onMarkRenewed = viewModel::markRenewed)
                }
            }
            state.upcoming.forEach { (band, entries) ->
                item(key = "band-$band") { SectionHeader(stringResource(band.title)) }
                items(entries, key = { "soon-${it.deadline.kind}-${it.deadline.id}" }) { entry ->
                    DeadlineCard(entry, navController)
                }
            }
            if (state.pastDue.isEmpty() && state.upcoming.isEmpty()) {
                item {
                    Text(
                        stringResource(R.string.coming_up_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 8.dp),
                    )
                }
            }
        }
    }
}

private val DashboardBand.title: Int
    get() = when (this) {
        DashboardBand.WEEK -> R.string.section_next_7_days
        DashboardBand.MONTH -> R.string.section_next_30_days
        DashboardBand.LATER -> R.string.section_later
    }

@Composable
private fun DeadlineCard(entry: DashboardEntry, navController: NavController, onMarkRenewed: ((Long) -> Unit)? = null) {
    val deadline = entry.deadline
    RecordCard(
        kind = deadline.kind,
        title = deadline.title,
        subtitle = null,
        status = entry.status,
        statusText = deadlineText(deadline.kind, deadline.date),
        onClick = { navController.openRecord(deadline.kind, deadline.id) },
        trailing = if (onMarkRenewed != null && deadline.kind == RecordKind.SUBSCRIPTION) {
            {
                IconButton(onClick = { onMarkRenewed(deadline.id) }) {
                    Icon(
                        Icons.Outlined.CheckCircle,
                        contentDescription = stringResource(R.string.action_mark_renewed_named, deadline.title),
                    )
                }
            }
        } else {
            null
        },
    )
}

@Composable
private fun SummaryTiles(state: DashboardState, onMonthlyClick: () -> Unit) {
    val statusColors = LocalStatusColors.current
    val spend = state.monthlyTotals.entries.minByOrNull { it.key }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
        SummaryTile(
            value = state.pastDue.size.toString(),
            label = stringResource(R.string.tile_overdue),
            color = if (state.pastDue.isEmpty()) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error,
            modifier = Modifier.weight(1f),
        )
        SummaryTile(
            value = state.upcomingCount.toString(),
            label = stringResource(R.string.tile_due_soon),
            color = if (state.upcomingCount == 0) MaterialTheme.colorScheme.onSurface else statusColors.soon,
            modifier = Modifier.weight(1f),
        )
        SummaryTile(
            value = spend?.let { Money.format(it.value, it.key) } ?: "–",
            label = if (state.monthlyTotals.size > 1 && spend != null) {
                stringResource(R.string.tile_per_month_currency, spend.key)
            } else {
                stringResource(R.string.tile_per_month)
            },
            color = MaterialTheme.colorScheme.onSurface,
            onClick = onMonthlyClick,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun SummaryTile(value: String, label: String, color: Color, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val shape = RoundedCornerShape(16.dp)
    val content: @Composable () -> Unit = {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            Text(
                value,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = color,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
    if (onClick != null) {
        Surface(onClick = onClick, shape = shape, color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = modifier, content = content)
    } else {
        Surface(shape = shape, color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = modifier.semantics(mergeDescendants = true) {}, content = content)
    }
}

@Composable
private fun QuickAddRow(onCreate: (RecordKind) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
        RecordKind.entries.forEach { kind ->
            ActionTile(
                icon = kind.icon,
                label = stringResource(kind.quickAddLabel),
                description = stringResource(kind.addLabel),
                onClick = { onCreate(kind) },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

private val RecordKind.quickAddLabel: Int
    get() = when (this) {
        RecordKind.WARRANTY -> R.string.quick_add_product
        RecordKind.SUBSCRIPTION -> R.string.kind_subscription
        RecordKind.DOCUMENT -> R.string.kind_document
    }

private val RecordKind.addLabel: Int
    get() = when (this) {
        RecordKind.WARRANTY -> R.string.action_add_product
        RecordKind.SUBSCRIPTION -> R.string.action_add_subscription
        RecordKind.DOCUMENT -> R.string.action_add_document
    }

@Composable
private fun WelcomeState(onCreate: (RecordKind) -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        EmptyState(
            icon = Icons.Outlined.Inventory2,
            title = stringResource(R.string.welcome_title),
            body = stringResource(R.string.welcome_body),
        )
        Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(horizontal = 32.dp)) {
            RecordKind.entries.forEach { kind ->
                FilledTonalButton(onClick = { onCreate(kind) }, modifier = Modifier.fillMaxWidth()) {
                    Icon(kind.icon, contentDescription = null)
                    Text(stringResource(kind.addLabel), modifier = Modifier.padding(start = 8.dp))
                }
            }
        }
    }
}

@Composable
private fun ReminderPermissionCard(onDismiss: () -> Unit) {
    val context = LocalContext.current
    var allowed by rememberSaveable { mutableStateOf(ReminderNotifications.canPost(context)) }
    var askedOnce by rememberSaveable { mutableStateOf(false) }
    LifecycleResumeEffect(Unit) {
        allowed = ReminderNotifications.canPost(context)
        onPauseOrDispose {}
    }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        allowed = granted && ReminderNotifications.canPost(context)
        askedOnce = true
        if (allowed) ReminderScheduler.checkNow(context)
    }
    if (allowed) return

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.tertiaryContainer,
            contentColor = MaterialTheme.colorScheme.onTertiaryContainer,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Outlined.NotificationsActive, contentDescription = null)
                Text(stringResource(R.string.reminder_prompt_title), style = MaterialTheme.typography.titleMedium)
            }
            Text(stringResource(R.string.reminder_prompt_body), style = MaterialTheme.typography.bodyMedium)
            Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_not_now)) }
                FilledTonalButton(onClick = {
                    if (Build.VERSION.SDK_INT >= 33 && !askedOnce) {
                        request.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else {
                        context.startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        )
                    }
                }) { Text(stringResource(R.string.action_allow)) }
            }
        }
    }
}
