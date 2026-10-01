package com.isaaclamb.pettytracker.ui.products

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.Money
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.domain.deadlineStatus
import com.isaaclamb.pettytracker.ui.Formats
import com.isaaclamb.pettytracker.ui.ProductDetailRoute
import com.isaaclamb.pettytracker.ui.ProductEditRoute
import com.isaaclamb.pettytracker.ui.components.AttachmentEditor
import com.isaaclamb.pettytracker.ui.components.AttachmentList
import com.isaaclamb.pettytracker.ui.components.ConfirmDialog
import com.isaaclamb.pettytracker.ui.components.CurrencyField
import com.isaaclamb.pettytracker.ui.components.DateField
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
import com.isaaclamb.pettytracker.ui.components.shareText
import com.isaaclamb.pettytracker.ui.trackerViewModel
import java.time.LocalDate
import java.time.temporal.ChronoUnit

@Composable
fun ProductListScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, _ -> ProductListViewModel(app) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val filter by viewModel.filter.collectAsStateWithLifecycle()

    TabScaffold(
        title = stringResource(R.string.tab_warranties),
        navController = navController,
        fabLabel = stringResource(R.string.action_add_product),
        onAdd = { navController.navigate(ProductEditRoute()) },
    ) {
        if (!state.loaded) return@TabScaffold
        if (!state.hasAny) {
            item {
                EmptyState(
                    icon = Icons.Outlined.Inventory2,
                    title = stringResource(R.string.products_empty_title),
                    body = stringResource(R.string.products_empty_body),
                )
            }
            return@TabScaffold
        }
        item { SearchField(query, { viewModel.query.value = it }, stringResource(R.string.search_products)) }
        item {
            FilterChips(ProductFilter.entries, filter, label = { stringResource(it.label) }) { viewModel.filter.value = it }
        }
        if (state.items.isEmpty()) {
            item { NoMatches() }
        }
        items(state.items, key = { it.product.id }) { item ->
            RecordCard(
                kind = RecordKind.WARRANTY,
                title = item.product.name,
                subtitle = item.product.subtitle(),
                status = item.status,
                statusText = item.product.warrantyExpires?.let { deadlineText(RecordKind.WARRANTY, it) }
                    ?: stringResource(R.string.warranty_no_date),
                onClick = { navController.navigate(ProductDetailRoute(item.product.id)) },
            )
        }
    }
}

private val ProductFilter.label: Int
    get() = when (this) {
        ProductFilter.ALL -> R.string.filter_all
        ProductFilter.COVERED -> R.string.filter_covered
        ProductFilter.ENDING -> R.string.filter_ending
        ProductFilter.EXPIRED -> R.string.filter_expired
    }

fun Product.subtitle(): String = listOf(brand, model).filter { it.isNotBlank() }.joinToString(" · ").ifBlank { retailer }

@Composable
fun ProductDetailScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, handle -> ProductDetailViewModel(app, handle) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var confirmDelete by rememberSaveable { mutableStateOf(false) }

    val product = state.product
    LaunchedEffect(state.loaded, product) {
        if (state.loaded && product == null) navController.popBackStack()
    }
    if (product == null) return

    val shareSubject = stringResource(R.string.share_product_subject, product.name)
    val shareBody = productShareText(product)
    DetailScaffold(
        title = product.name,
        onBack = { navController.popBackStack() },
        actions = {
            IconButton(onClick = { shareText(context, shareSubject, shareBody) }) {
                Icon(Icons.Outlined.Share, contentDescription = stringResource(R.string.action_share_details))
            }
            IconButton(onClick = { navController.navigate(ProductEditRoute(product.id)) }) {
                Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.action_edit))
            }
            IconButton(onClick = { confirmDelete = true }) {
                Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.action_delete))
            }
        },
    ) {
        WarrantyCard(product, state.leadDays)
        SectionHeader(stringResource(R.string.section_details))
        SelectionContainer {
            Column {
                DetailRow(stringResource(R.string.field_brand), product.brand)
                DetailRow(stringResource(R.string.field_model), product.model)
                DetailRow(stringResource(R.string.field_serial), product.serialNumber)
                DetailRow(stringResource(R.string.field_purchase_date), product.purchaseDate?.let(Formats::date))
                DetailRow(stringResource(R.string.field_retailer), product.retailer)
                DetailRow(stringResource(R.string.field_price), product.price?.let { Money.format(it, product.currency) })
            }
        }
        SectionHeader(stringResource(R.string.section_attachments))
        if (state.attachments.isEmpty()) {
            Text(
                stringResource(R.string.attachments_none_product),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            AttachmentList(state.attachments, viewModel.attachmentStore)
        }
        if (product.notes.isNotBlank()) {
            SectionHeader(stringResource(R.string.field_notes))
            SelectionContainer { Text(product.notes, style = MaterialTheme.typography.bodyLarge) }
        }
    }

    if (confirmDelete) {
        ConfirmDialog(
            title = stringResource(R.string.delete_title, product.name),
            text = stringResource(R.string.delete_product_body),
            confirmLabel = stringResource(R.string.action_delete),
            onConfirm = viewModel::delete,
            onDismiss = { confirmDelete = false },
        )
    }
}

@Composable
private fun WarrantyCard(product: Product, leadDays: Int) {
    val today = LocalDate.now()
    val expires = product.warrantyExpires
    val status = deadlineStatus(expires, today, leadDays)
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                KindBadge(RecordKind.WARRANTY, status)
                Column {
                    Text(
                        stringResource(
                            when (status) {
                                DeadlineStatus.NONE -> R.string.warranty_no_date
                                DeadlineStatus.PAST -> R.string.warranty_expired
                                else -> R.string.warranty_active
                            }
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    if (expires != null) {
                        Text(
                            deadlineText(RecordKind.WARRANTY, expires, today, withDate = true),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            val start = product.purchaseDate
            if (start != null && expires != null && expires.isAfter(start) && status != DeadlineStatus.PAST) {
                val total = ChronoUnit.DAYS.between(start, expires).toFloat()
                val used = ChronoUnit.DAYS.between(start, today).coerceIn(0, total.toLong()).toFloat()
                val percentLeft = ((1 - used / total) * 100).toInt()
                LinearProgressIndicator(
                    progress = { used / total },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    stringResource(R.string.warranty_remaining_percent, percentLeft),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun productShareText(product: Product): String {
    val lines = listOfNotNull(
        product.name,
        product.brand.takeIf { it.isNotBlank() }?.let { stringResource(R.string.field_brand) + ": " + it },
        product.model.takeIf { it.isNotBlank() }?.let { stringResource(R.string.field_model) + ": " + it },
        product.serialNumber.takeIf { it.isNotBlank() }?.let { stringResource(R.string.field_serial) + ": " + it },
        product.purchaseDate?.let { stringResource(R.string.field_purchase_date) + ": " + Formats.date(it) },
        product.retailer.takeIf { it.isNotBlank() }?.let { stringResource(R.string.field_retailer) + ": " + it },
        product.price?.let { stringResource(R.string.field_price) + ": " + Money.format(it, product.currency) },
        product.warrantyExpires?.let { stringResource(R.string.field_warranty_expires) + ": " + Formats.date(it) },
        product.notes.takeIf { it.isNotBlank() },
    )
    return lines.joinToString("\n")
}

@Composable
fun ProductEditScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, handle -> ProductEditViewModel(app, handle) }
    val form = viewModel.form

    EditScaffold(
        title = stringResource(if (viewModel.id == 0L) R.string.title_new_product else R.string.title_edit_product),
        viewModel = viewModel,
        changed = form.changed,
        onSave = {
            viewModel.save { id, isNew ->
                if (isNew) {
                    navController.navigate(ProductDetailRoute(id)) {
                        popUpTo<ProductEditRoute> { inclusive = true }
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
            stringResource(R.string.field_product_name),
            error = if (form.nameError) stringResource(R.string.error_required) else null,
            capitalization = KeyboardCapitalization.Words,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FormTextField(
                form.brand,
                { value -> viewModel.edit { it.copy(brand = value) } },
                stringResource(R.string.field_brand),
                modifier = Modifier.weight(1f),
                capitalization = KeyboardCapitalization.Words,
            )
            FormTextField(
                form.model,
                { value -> viewModel.edit { it.copy(model = value) } },
                stringResource(R.string.field_model),
                modifier = Modifier.weight(1f),
                capitalization = KeyboardCapitalization.Characters,
            )
        }
        FormTextField(
            form.serialNumber,
            { value -> viewModel.edit { it.copy(serialNumber = value) } },
            stringResource(R.string.field_serial),
            capitalization = KeyboardCapitalization.Characters,
        )

        SectionHeader(stringResource(R.string.section_purchase))
        DateField(
            stringResource(R.string.field_purchase_date),
            form.purchaseDate,
            { date -> viewModel.edit { it.copy(purchaseDate = date) } },
        )
        FormTextField(
            form.retailer,
            { value -> viewModel.edit { it.copy(retailer = value) } },
            stringResource(R.string.field_retailer),
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

        SectionHeader(stringResource(R.string.section_warranty))
        DateField(
            stringResource(R.string.field_warranty_expires),
            form.warrantyExpires,
            { date -> viewModel.edit { it.copy(warrantyExpires = date) } },
            supportingText = if (form.warrantyBeforePurchase) stringResource(R.string.warning_warranty_before_purchase) else null,
        )
        Text(
            stringResource(if (form.purchaseDate != null) R.string.warranty_length_from_purchase else R.string.warranty_length_from_today),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(1L, 2L, 3L, 5L).forEach { years ->
                AssistChip(
                    onClick = { viewModel.setWarrantyYears(years) },
                    label = { Text(pluralStringResource(R.plurals.years, years.toInt(), years.toInt())) },
                )
            }
        }

        SectionHeader(stringResource(R.string.section_receipts))
        AttachmentEditor(viewModel)

        SectionHeader(stringResource(R.string.field_notes))
        FormTextField(
            form.notes,
            { value -> viewModel.edit { it.copy(notes = value) } },
            stringResource(R.string.field_notes),
            singleLine = false,
        )
    }
}
