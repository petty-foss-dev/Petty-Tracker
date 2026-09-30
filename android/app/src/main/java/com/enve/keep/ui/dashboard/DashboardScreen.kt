package com.enve.keep.ui.dashboard

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import com.enve.keep.R
import com.enve.keep.domain.RecordKind
import com.enve.keep.reminders.ReminderNotifications
import com.enve.keep.reminders.ReminderScheduler
import com.enve.keep.domain.Money
import com.enve.keep.ui.KeepNavigationBar
import com.enve.keep.ui.SearchRoute
import com.enve.keep.ui.SettingsRoute
import com.enve.keep.ui.Tab
import com.enve.keep.ui.components.EmptyState
import com.enve.keep.ui.components.RecordCard
import com.enve.keep.ui.components.SectionHeader
import com.enve.keep.ui.components.deadlineText
import com.enve.keep.ui.components.icon
import com.enve.keep.ui.components.label
import com.enve.keep.ui.createRecord
import com.enve.keep.ui.keepViewModel
import com.enve.keep.ui.openRecord
import com.enve.keep.ui.selectTab

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(navController: NavController) {
    val viewModel = keepViewModel { app, _ -> DashboardViewModel(app) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    var choosingType by rememberSaveable { mutableStateOf(false) }

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
        bottomBar = { KeepNavigationBar(navController) },
        floatingActionButton = {
            if (!state.isEmpty) {
                ExtendedFloatingActionButton(
                    onClick = { choosingType = true },
                    icon = { Icon(Icons.Outlined.Add, contentDescription = null) },
                    text = { Text(stringResource(R.string.action_add)) },
                )
            }
        },
    ) { padding ->
        if (!state.loaded) return@Scaffold
        LazyColumn(
            contentPadding = PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = padding.calculateTopPadding() + 4.dp,
                bottom = padding.calculateBottomPadding() + 88.dp,
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
            if (state.pastDue.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.section_needs_attention)) }
                items(state.pastDue, key = { "past-${it.deadline.kind}-${it.deadline.id}" }) { entry ->
                    val deadline = entry.deadline
                    RecordCard(
                        kind = deadline.kind,
                        title = deadline.title,
                        subtitle = stringResource(deadline.kind.label),
                        status = entry.status,
                        statusText = deadlineText(deadline.kind, deadline.date),
                        onClick = { navController.openRecord(deadline.kind, deadline.id) },
                        trailing = if (deadline.kind == RecordKind.SUBSCRIPTION) {
                            {
                                IconButton(onClick = { viewModel.markRenewed(deadline.id) }) {
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
            }
            item { SectionHeader(stringResource(R.string.section_coming_up)) }
            if (state.upcoming.isEmpty()) {
                item {
                    Text(
                        stringResource(R.string.coming_up_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 4.dp),
                    )
                }
            }
            items(state.upcoming, key = { "soon-${it.deadline.kind}-${it.deadline.id}" }) { entry ->
                val deadline = entry.deadline
                RecordCard(
                    kind = deadline.kind,
                    title = deadline.title,
                    subtitle = stringResource(deadline.kind.label),
                    status = entry.status,
                    statusText = deadlineText(deadline.kind, deadline.date),
                    onClick = { navController.openRecord(deadline.kind, deadline.id) },
                )
            }
            item { SectionHeader(stringResource(R.string.section_overview)) }
            item {
                CategoryCard(
                    tab = Tab.WARRANTIES,
                    count = pluralStringResource(R.plurals.products_count, state.warranties.count, state.warranties.count),
                    detail = state.warranties.next?.let { deadlineText(RecordKind.WARRANTY, it.date) + " · " + it.title },
                    onClick = { navController.selectTab(Tab.WARRANTIES) },
                )
            }
            item {
                val spend = state.monthlyTotals.entries.sortedBy { it.key }
                    .joinToString(" + ") { (currency, amount) -> Money.format(amount, currency) }
                CategoryCard(
                    tab = Tab.SUBSCRIPTIONS,
                    count = pluralStringResource(R.plurals.active_subscriptions, state.subscriptions.count, state.subscriptions.count),
                    detail = listOfNotNull(
                        spend.takeIf { it.isNotEmpty() }?.let { stringResource(R.string.per_month_estimate, it) },
                        state.subscriptions.next?.let { deadlineText(RecordKind.SUBSCRIPTION, it.date) + " · " + it.title },
                    ).joinToString("\n").ifEmpty { null },
                    onClick = { navController.selectTab(Tab.SUBSCRIPTIONS) },
                )
            }
            item {
                CategoryCard(
                    tab = Tab.DOCUMENTS,
                    count = pluralStringResource(R.plurals.documents_count, state.documents.count, state.documents.count),
                    detail = state.documents.next?.let { deadlineText(RecordKind.DOCUMENT, it.date) + " · " + it.title },
                    onClick = { navController.selectTab(Tab.DOCUMENTS) },
                )
            }
        }
    }

    if (choosingType) {
        ModalBottomSheet(onDismissRequest = { choosingType = false }) {
            Column(Modifier.navigationBarsPadding().padding(bottom = 16.dp)) {
                Text(
                    stringResource(R.string.add_sheet_title),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
                )
                RecordKind.entries.forEach { kind ->
                    ListItem(
                        headlineContent = { Text(stringResource(kind.addLabel)) },
                        supportingContent = { Text(stringResource(kind.addHint)) },
                        leadingContent = { Icon(kind.icon, contentDescription = null) },
                        modifier = Modifier.clickable(role = Role.Button) {
                            choosingType = false
                            navController.createRecord(kind)
                        },
                    )
                }
            }
        }
    }
}

private val RecordKind.addLabel: Int
    get() = when (this) {
        RecordKind.WARRANTY -> R.string.action_add_product
        RecordKind.SUBSCRIPTION -> R.string.action_add_subscription
        RecordKind.DOCUMENT -> R.string.action_add_document
    }

private val RecordKind.addHint: Int
    get() = when (this) {
        RecordKind.WARRANTY -> R.string.add_product_hint
        RecordKind.SUBSCRIPTION -> R.string.add_subscription_hint
        RecordKind.DOCUMENT -> R.string.add_document_hint
    }

@Composable
private fun CategoryCard(tab: Tab, count: String, detail: String?, onClick: () -> Unit) {
    OutlinedCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.padding(16.dp),
        ) {
            Icon(tab.icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(tab.label), style = MaterialTheme.typography.titleMedium)
                Text(count, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (detail != null) {
                    Text(
                        detail,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
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
