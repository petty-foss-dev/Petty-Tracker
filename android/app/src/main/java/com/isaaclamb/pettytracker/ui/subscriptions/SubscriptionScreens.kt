package com.isaaclamb.pettytracker.ui.subscriptions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.data.CycleUnit
import com.isaaclamb.pettytracker.data.Subscription
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.Money
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.domain.Renewals
import com.isaaclamb.pettytracker.ui.Formats
import com.isaaclamb.pettytracker.ui.SubscriptionDetailRoute
import com.isaaclamb.pettytracker.ui.SubscriptionEditRoute
import com.isaaclamb.pettytracker.ui.components.ConfirmDialog
import com.isaaclamb.pettytracker.ui.components.CurrencyField
import com.isaaclamb.pettytracker.ui.components.DateField
import com.isaaclamb.pettytracker.ui.components.DetailCard
import com.isaaclamb.pettytracker.ui.components.DetailRow
import com.isaaclamb.pettytracker.ui.components.DetailScaffold
import com.isaaclamb.pettytracker.ui.components.EditScaffold
import com.isaaclamb.pettytracker.ui.components.EmptyState
import com.isaaclamb.pettytracker.ui.components.FilterChips
import com.isaaclamb.pettytracker.ui.components.FormTextField
import com.isaaclamb.pettytracker.ui.components.KindBadge
import com.isaaclamb.pettytracker.ui.components.NoMatches
import com.isaaclamb.pettytracker.ui.components.RecordCard
import com.isaaclamb.pettytracker.ui.components.SearchField
import com.isaaclamb.pettytracker.ui.components.SectionHeader
import com.isaaclamb.pettytracker.ui.components.TabScaffold
import com.isaaclamb.pettytracker.ui.components.deadlineText
import com.isaaclamb.pettytracker.ui.trackerViewModel
import java.math.BigDecimal
import java.time.LocalDate

@Composable
fun SubscriptionListScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, _ -> SubscriptionListViewModel(app) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val filter by viewModel.filter.collectAsStateWithLifecycle()

    TabScaffold(
        title = stringResource(R.string.tab_subscriptions),
        navController = navController,
        fabLabel = stringResource(R.string.action_add_subscription),
        onAdd = { navController.navigate(SubscriptionEditRoute()) },
    ) {
        if (!state.loaded) return@TabScaffold
        if (!state.hasAny) {
            item {
                EmptyState(
                    icon = Icons.Outlined.Autorenew,
                    title = stringResource(R.string.subscriptions_empty_title),
                    body = stringResource(R.string.subscriptions_empty_body),
                )
            }
            return@TabScaffold
        }
        if (state.activeCount > 0) {
            item { SpendSummary(state.activeCount, state.monthlyTotals) }
        }
        item { SearchField(query, { viewModel.query.value = it }, stringResource(R.string.search_subscriptions)) }
        item {
            FilterChips(SubscriptionFilter.entries, filter, label = { stringResource(it.label) }) { viewModel.filter.value = it }
        }
        if (state.items.isEmpty()) {
            item { NoMatches() }
        }
        items(state.items, key = { it.subscription.id }) { item ->
            val subscription = item.subscription
            RecordCard(
                kind = RecordKind.SUBSCRIPTION,
                title = subscription.name,
                subtitle = subscription.priceText(),
                status = item.status,
                statusText = subscription.statusText(),
                onClick = { navController.navigate(SubscriptionDetailRoute(subscription.id)) },
            )
        }
    }
}

private val SubscriptionFilter.label: Int
    get() = when (this) {
        SubscriptionFilter.ACTIVE -> R.string.filter_active
        SubscriptionFilter.CANCELED -> R.string.filter_canceled
        SubscriptionFilter.ALL -> R.string.filter_all
    }

@Composable
private fun SpendSummary(activeCount: Int, totals: Map<String, BigDecimal>) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                pluralStringResource(R.plurals.active_subscriptions, activeCount, activeCount),
                style = MaterialTheme.typography.labelLarge,
            )
            totals.entries.sortedBy { it.key }.forEach { (currency, amount) ->
                Text(
                    stringResource(R.string.per_month_estimate, Money.format(amount, currency)),
                    style = MaterialTheme.typography.headlineSmall,
                )
            }
        }
    }
}

@Composable
fun cycleText(count: Int, unit: CycleUnit): String = pluralStringResource(
    when (unit) {
        CycleUnit.DAYS -> R.plurals.cycle_days
        CycleUnit.WEEKS -> R.plurals.cycle_weeks
        CycleUnit.MONTHS -> R.plurals.cycle_months
        CycleUnit.YEARS -> R.plurals.cycle_years
    },
    count,
    count,
)

@Composable
fun Subscription.priceText(): String {
    val cycle = cycleText(cycleCount, cycleUnit)
    return price?.let { stringResource(R.string.price_per_cycle, Money.format(it, currency), cycle) } ?: cycle
}

@Composable
fun Subscription.statusText(): String = canceledOn?.let { stringResource(R.string.subscription_canceled_on, Formats.date(it)) }
    ?: deadlineText(RecordKind.SUBSCRIPTION, nextRenewal)

@Composable
fun SubscriptionDetailScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, handle -> SubscriptionDetailViewModel(app, handle) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    var confirmDelete by rememberSaveable { mutableStateOf(false) }
    var confirmCancel by rememberSaveable { mutableStateOf(false) }

    val subscription = state.subscription
    LaunchedEffect(state.loaded, subscription) {
        if (state.loaded && subscription == null) navController.popBackStack()
    }
    if (subscription == null) return

    DetailScaffold(
        title = subscription.name,
        onBack = { navController.popBackStack() },
        actions = {
            IconButton(onClick = { navController.navigate(SubscriptionEditRoute(subscription.id)) }) {
                Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.action_edit))
            }
            IconButton(onClick = { confirmDelete = true }) {
                Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.action_delete))
            }
        },
    ) {
        val status = subscriptionStatus(subscription, LocalDate.now(), state.leadDays)
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    KindBadge(RecordKind.SUBSCRIPTION, status)
                    Column {
                        Text(subscription.statusText(), style = MaterialTheme.typography.titleMedium)
                        if (subscription.isActive) {
                            Text(
                                stringResource(
                                    if (status == DeadlineStatus.PAST) R.string.renewal_date_on else R.string.next_renewal_on,
                                    Formats.date(subscription.nextRenewal),
                                ),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                if (subscription.isActive) {
                    if (status == DeadlineStatus.PAST) {
                        Text(
                            stringResource(R.string.renewal_passed_hint),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = viewModel::markRenewed, modifier = Modifier.weight(1f)) {
                            Text(stringResource(R.string.action_mark_renewed))
                        }
                        OutlinedButton(onClick = { confirmCancel = true }, modifier = Modifier.weight(1f)) {
                            Text(stringResource(R.string.action_mark_canceled))
                        }
                    }
                } else {
                    FilledTonalButton(onClick = viewModel::reactivate, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.action_reactivate))
                    }
                }
            }
        }
        SectionHeader(stringResource(R.string.section_details))
        DetailCard {
            DetailRow(stringResource(R.string.field_price), subscription.priceText())
            val price = subscription.price
            if (price != null) {
                val monthly = Renewals.monthlyCost(price, subscription.cycleCount, subscription.cycleUnit)
                if (!(subscription.cycleUnit == CycleUnit.MONTHS && subscription.cycleCount == 1)) {
                    DetailRow(
                        stringResource(R.string.field_monthly_cost),
                        stringResource(R.string.per_month_estimate, Money.format(monthly, subscription.currency)),
                    )
                }
                if (!(subscription.cycleUnit == CycleUnit.YEARS && subscription.cycleCount == 1)) {
                    DetailRow(
                        stringResource(R.string.field_yearly_cost),
                        stringResource(R.string.per_year_estimate, Money.format(monthly * BigDecimal(12), subscription.currency)),
                    )
                }
            }
            DetailRow(stringResource(R.string.field_billing_cycle), cycleText(subscription.cycleCount, subscription.cycleUnit))
        }
        if (subscription.notes.isNotBlank()) {
            SectionHeader(stringResource(R.string.field_notes))
            SelectionContainer { Text(subscription.notes, style = MaterialTheme.typography.bodyLarge) }
        }
    }

    if (confirmCancel) {
        ConfirmDialog(
            title = stringResource(R.string.cancel_subscription_title),
            text = stringResource(R.string.cancel_subscription_body),
            confirmLabel = stringResource(R.string.action_mark_canceled),
            onConfirm = viewModel::cancel,
            onDismiss = { confirmCancel = false },
        )
    }
    if (confirmDelete) {
        ConfirmDialog(
            title = stringResource(R.string.delete_title, subscription.name),
            text = stringResource(R.string.delete_subscription_body),
            confirmLabel = stringResource(R.string.action_delete),
            onConfirm = viewModel::delete,
            onDismiss = { confirmDelete = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionEditScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, handle -> SubscriptionEditViewModel(app, handle) }
    val form = viewModel.form

    EditScaffold(
        title = stringResource(if (viewModel.id == 0L) R.string.title_new_subscription else R.string.title_edit_subscription),
        viewModel = viewModel,
        changed = form.changed,
        onSave = {
            viewModel.save { id, isNew ->
                if (isNew) {
                    navController.navigate(SubscriptionDetailRoute(id)) {
                        popUpTo<SubscriptionEditRoute> { inclusive = true }
                    }
                } else {
                    navController.popBackStack()
                }
            }
        },
        onClose = { navController.popBackStack() },
    ) {
        if (!form.loaded) return@EditScaffold
        FormTextField(
            form.name,
            { value -> viewModel.edit { it.copy(name = value) } },
            stringResource(R.string.field_subscription_name),
            error = if (form.nameError) stringResource(R.string.error_required) else null,
            capitalization = KeyboardCapitalization.Words,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FormTextField(
                form.price,
                { value -> viewModel.edit { it.copy(price = value) } },
                stringResource(R.string.field_price),
                modifier = Modifier.weight(1f),
                error = if (form.priceError) stringResource(R.string.error_price) else null,
                keyboardType = KeyboardType.Decimal,
            )
            CurrencyField(form.currency, { code -> viewModel.edit { it.copy(currency = code) } }, Modifier.weight(1f))
        }

        SectionHeader(stringResource(R.string.field_billing_cycle))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FormTextField(
                form.cycleCount,
                { value -> viewModel.edit { it.copy(cycleCount = value.filter(Char::isDigit).take(3)) } },
                stringResource(R.string.field_every),
                modifier = Modifier.weight(0.4f),
                error = if (form.cycleError) stringResource(R.string.error_cycle) else null,
                keyboardType = KeyboardType.Number,
            )
            var expanded by rememberSaveable { mutableStateOf(false) }
            val count = form.parsedCycle ?: 1
            ExposedDropdownMenuBox(expanded, { expanded = it }, modifier = Modifier.weight(0.6f)) {
                OutlinedTextField(
                    value = unitName(form.cycleUnit, count),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(stringResource(R.string.field_period)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
                )
                ExposedDropdownMenu(expanded, { expanded = false }) {
                    CycleUnit.entries.forEach { unit ->
                        DropdownMenuItem(
                            text = { Text(unitName(unit, count)) },
                            onClick = {
                                viewModel.edit { it.copy(cycleUnit = unit) }
                                expanded = false
                            },
                        )
                    }
                }
            }
        }
        DateField(
            stringResource(R.string.field_next_renewal),
            form.nextRenewal,
            { date -> viewModel.edit { it.copy(nextRenewal = date) } },
            clearable = false,
            error = if (form.renewalError) stringResource(R.string.error_required) else null,
            supportingText = stringResource(R.string.next_renewal_hint),
        )

        SectionHeader(stringResource(R.string.field_notes))
        FormTextField(
            form.notes,
            { value -> viewModel.edit { it.copy(notes = value) } },
            stringResource(R.string.field_notes),
            singleLine = false,
        )
    }
}

@Composable
private fun unitName(unit: CycleUnit, count: Int): String = pluralStringResource(
    when (unit) {
        CycleUnit.DAYS -> R.plurals.unit_days
        CycleUnit.WEEKS -> R.plurals.unit_weeks
        CycleUnit.MONTHS -> R.plurals.unit_months
        CycleUnit.YEARS -> R.plurals.unit_years
    },
    count,
)
