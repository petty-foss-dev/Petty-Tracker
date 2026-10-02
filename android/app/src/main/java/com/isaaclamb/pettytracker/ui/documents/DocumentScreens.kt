package com.isaaclamb.pettytracker.ui.documents

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavController
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.RecordRef
import com.isaaclamb.pettytracker.data.RecordType
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.domain.deadlineStatus
import com.isaaclamb.pettytracker.ui.DocumentDetailRoute
import com.isaaclamb.pettytracker.ui.DocumentEditRoute
import com.isaaclamb.pettytracker.ui.Formats
import com.isaaclamb.pettytracker.ui.components.AttachmentEditor
import com.isaaclamb.pettytracker.ui.components.ConfirmDialog
import com.isaaclamb.pettytracker.ui.components.DateField
import com.isaaclamb.pettytracker.ui.components.DetailAttachments
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
import com.isaaclamb.pettytracker.ui.components.RelatedSection
import com.isaaclamb.pettytracker.ui.components.SearchField
import com.isaaclamb.pettytracker.ui.components.SectionHeader
import com.isaaclamb.pettytracker.ui.components.StatusSection
import com.isaaclamb.pettytracker.ui.components.TabScaffold
import com.isaaclamb.pettytracker.ui.components.deadlineText
import com.isaaclamb.pettytracker.ui.trackerViewModel
import java.time.LocalDate

@Composable
fun DocumentListScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, _ -> DocumentListViewModel(app) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val filter by viewModel.filter.collectAsStateWithLifecycle()

    TabScaffold(
        title = stringResource(R.string.tab_documents),
        navController = navController,
        fabLabel = stringResource(R.string.action_add_document),
        onAdd = { navController.navigate(DocumentEditRoute()) },
    ) {
        if (!state.loaded) return@TabScaffold
        if (!state.hasAny) {
            item {
                EmptyState(
                    icon = Icons.Outlined.Badge,
                    title = stringResource(R.string.documents_empty_title),
                    body = stringResource(R.string.documents_empty_body),
                )
            }
            return@TabScaffold
        }
        item { SearchField(query, { viewModel.query.value = it }, stringResource(R.string.search_documents)) }
        item {
            FilterChips(DocumentFilter.entries, filter, label = { stringResource(it.label) }) { viewModel.filter.value = it }
        }
        if (state.items.isEmpty()) {
            item { NoMatches() }
        }
        StatusSection.group(state.items) { it.status }.forEach { (section, items) ->
            item(key = "section-$section") { SectionHeader(stringResource(section.title(RecordKind.DOCUMENT))) }
            items(items, key = { it.document.id }) { item ->
                RecordCard(
                    kind = RecordKind.DOCUMENT,
                    title = item.document.title,
                    subtitle = item.document.subtitle(),
                    status = item.status,
                    statusText = item.document.expiresOn?.let { deadlineText(RecordKind.DOCUMENT, it) }
                        ?: stringResource(R.string.document_no_expiry),
                    onClick = { navController.navigate(DocumentDetailRoute(item.document.id)) },
                )
            }
        }
    }
}

private val DocumentFilter.label: Int
    get() = when (this) {
        DocumentFilter.ALL -> R.string.filter_all
        DocumentFilter.VALID -> R.string.filter_valid
        DocumentFilter.EXPIRING -> R.string.filter_expiring
        DocumentFilter.EXPIRED -> R.string.filter_expired
    }

fun Document.subtitle(): String = listOf(issuer, reference).filter { it.isNotBlank() }.joinToString(" · ")

@Composable
fun DocumentDetailScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, handle -> DocumentDetailViewModel(app, handle) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    var confirmDelete by rememberSaveable { mutableStateOf(false) }

    val document = state.document
    LaunchedEffect(state.loaded, document) {
        if (state.loaded && document == null) navController.popBackStack()
    }
    if (document == null) return

    DetailScaffold(
        title = document.title,
        onBack = { navController.popBackStack() },
        actions = {
            IconButton(onClick = { navController.navigate(DocumentEditRoute(document.id)) }) {
                Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.action_edit))
            }
            IconButton(onClick = { confirmDelete = true }) {
                Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.action_delete))
            }
        },
    ) {
        val expires = document.expiresOn
        val status = deadlineStatus(expires, LocalDate.now(), state.leadDays)
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.padding(16.dp),
            ) {
                KindBadge(RecordKind.DOCUMENT, status)
                Column {
                    Text(
                        stringResource(
                            when (status) {
                                DeadlineStatus.NONE -> R.string.document_no_expiry
                                DeadlineStatus.PAST -> R.string.document_expired
                                DeadlineStatus.TODAY -> R.string.document_expires_today
                                DeadlineStatus.SOON -> R.string.document_expiring_soon
                                else -> R.string.document_valid
                            }
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    if (expires != null) {
                        Text(
                            deadlineText(RecordKind.DOCUMENT, expires, withDate = true),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
        SectionHeader(stringResource(R.string.section_details))
        DetailCard {
            DetailRow(stringResource(R.string.field_issuer), document.issuer)
            DetailRow(stringResource(R.string.field_reference), document.reference)
            DetailRow(stringResource(R.string.field_issued_on), document.issuedOn?.let(Formats::date))
            DetailRow(stringResource(R.string.field_expires_on), document.expiresOn?.let(Formats::date))
        }
        SectionHeader(stringResource(R.string.section_attachments))
        DetailAttachments(viewModel, state.attachments, stringResource(R.string.attachments_none_document))
        if (document.notes.isNotBlank()) {
            SectionHeader(stringResource(R.string.field_notes))
            SelectionContainer { Text(document.notes, style = MaterialTheme.typography.bodyLarge) }
        }
        RelatedSection(RecordRef(RecordType.DOCUMENT, document.id), navController)
    }

    if (confirmDelete) {
        ConfirmDialog(
            title = stringResource(R.string.delete_title, document.title),
            text = stringResource(R.string.delete_document_body),
            confirmLabel = stringResource(R.string.action_delete),
            onConfirm = viewModel::delete,
            onDismiss = { confirmDelete = false },
        )
    }
}

@Composable
fun DocumentEditScreen(navController: NavController) {
    val viewModel = trackerViewModel { app, handle -> DocumentEditViewModel(app, handle) }
    val form = viewModel.form

    EditScaffold(
        title = stringResource(if (viewModel.id == 0L) R.string.title_new_document else R.string.title_edit_document),
        viewModel = viewModel,
        changed = form.changed,
        onSave = {
            viewModel.save { id, isNew ->
                if (isNew) {
                    navController.navigate(DocumentDetailRoute(id)) {
                        popUpTo<DocumentEditRoute> { inclusive = true }
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
            form.title,
            { value -> viewModel.edit { it.copy(title = value) } },
            stringResource(R.string.field_document_title),
            error = if (form.titleError) stringResource(R.string.error_required) else null,
            capitalization = KeyboardCapitalization.Words,
        )
        FormTextField(
            form.issuer,
            { value -> viewModel.edit { it.copy(issuer = value) } },
            stringResource(R.string.field_issuer),
            capitalization = KeyboardCapitalization.Words,
        )
        FormTextField(
            form.reference,
            { value -> viewModel.edit { it.copy(reference = value) } },
            stringResource(R.string.field_reference),
            capitalization = KeyboardCapitalization.Characters,
        )

        SectionHeader(stringResource(R.string.section_dates))
        DateField(
            stringResource(R.string.field_issued_on),
            form.issuedOn,
            { date -> viewModel.edit { it.copy(issuedOn = date) } },
        )
        DateField(
            stringResource(R.string.field_expires_on),
            form.expiresOn,
            { date -> viewModel.edit { it.copy(expiresOn = date) } },
            supportingText = if (form.expiresBeforeIssued) stringResource(R.string.warning_expiry_before_issue) else null,
        )

        SectionHeader(stringResource(R.string.section_scans))
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
