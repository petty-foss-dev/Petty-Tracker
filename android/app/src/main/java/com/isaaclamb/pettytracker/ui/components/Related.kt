package com.isaaclamb.pettytracker.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.LinkOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.TrackerApplication
import com.isaaclamb.pettytracker.data.RecordRef
import com.isaaclamb.pettytracker.data.RecordType
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.matchesAny
import com.isaaclamb.pettytracker.ui.openRecord
import com.isaaclamb.pettytracker.ui.trackerViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class RelatedRecord(val ref: RecordRef, val title: String, val note: String = "", val linkId: Long = 0)

data class RelatedState(val related: List<RelatedRecord> = emptyList(), val candidates: List<RelatedRecord> = emptyList())

class RelatedViewModel(private val app: TrackerApplication, private val ref: RecordRef) : ViewModel() {
    private val repository = app.container.repository

    val state: StateFlow<RelatedState> = combine(
        repository.links(ref),
        repository.products,
        repository.subscriptions,
        repository.documents,
    ) { links, products, subscriptions, documents ->
        val records = products.map { RelatedRecord(RecordRef(RecordType.PRODUCT, it.id), it.name) } +
            documents.map { RelatedRecord(RecordRef(RecordType.DOCUMENT, it.id), it.title) } +
            subscriptions.map { RelatedRecord(RecordRef(RecordType.SUBSCRIPTION, it.id), it.name) }
        val titles = records.associate { it.ref to it.title }
        val related = links.mapNotNull { link ->
            link.other(ref)?.let { other -> titles[other]?.let { RelatedRecord(other, it, link.note, link.id) } }
        }
        val linked = related.map { it.ref }.toSet()
        RelatedState(related, records.filter { it.ref != ref && it.ref !in linked })
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), RelatedState())

    fun link(other: RecordRef, note: String) {
        viewModelScope.launch { repository.addLink(ref, other, note.trim()) }
    }

    fun unlink(linkId: Long) {
        viewModelScope.launch { repository.unlink(linkId) }
    }
}

val RecordType.kind: RecordKind
    get() = when (this) {
        RecordType.PRODUCT -> RecordKind.WARRANTY
        RecordType.SUBSCRIPTION -> RecordKind.SUBSCRIPTION
        RecordType.DOCUMENT -> RecordKind.DOCUMENT
    }

private val RecordType.title: Int
    get() = when (this) {
        RecordType.PRODUCT -> R.string.record_product
        RecordType.SUBSCRIPTION -> R.string.kind_subscription
        RecordType.DOCUMENT -> R.string.kind_document
    }

/** Cross-references to other records, shown on detail screens. Screens with their own Link action hide it until used. */
@Composable
fun RelatedSection(ref: RecordRef, navController: NavController, showsWhenEmpty: Boolean = true) {
    val viewModel = trackerViewModel { app, _ -> RelatedViewModel(app, ref) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    var picking by rememberSaveable { mutableStateOf(false) }
    if (!showsWhenEmpty && state.related.isEmpty()) return

    SectionHeader(stringResource(R.string.section_related))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (state.related.isEmpty()) {
            Text(
                stringResource(R.string.related_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        state.related.forEach { record ->
            RecordCard(
                kind = record.ref.type.kind,
                title = record.title,
                subtitle = listOf(stringResource(record.ref.type.title), record.note).filter { it.isNotBlank() }.joinToString(" · "),
                status = DeadlineStatus.NONE,
                statusText = null,
                onClick = { navController.openRecord(record.ref.type.kind, record.ref.id) },
                trailing = {
                    IconButton(onClick = { viewModel.unlink(record.linkId) }) {
                        Icon(Icons.Outlined.LinkOff, contentDescription = stringResource(R.string.action_unlink_named, record.title))
                    }
                },
            )
        }
        OutlinedButton(onClick = { picking = true }, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Outlined.Link, contentDescription = null)
            Text(stringResource(R.string.action_link_record), modifier = Modifier.padding(start = 8.dp))
        }
    }
    if (picking) RecordLinkSheet(ref) { picking = false }
}

/** Picks another record to link to [ref], with an optional note. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordLinkSheet(ref: RecordRef, onDismiss: () -> Unit) {
    val viewModel = trackerViewModel { app, _ -> RelatedViewModel(app, ref) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    var note by rememberSaveable { mutableStateOf("") }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.navigationBarsPadding().imePadding().padding(horizontal = 16.dp),
        ) {
            Text(stringResource(R.string.title_link_record), style = MaterialTheme.typography.titleLarge)
            FormTextField(note, { note = it }, stringResource(R.string.field_link_note))
            SearchField(query, { query = it }, stringResource(R.string.search_records))
            val matches = state.candidates.filter { matchesAny(query, it.title) }
            if (matches.isEmpty()) {
                Text(
                    stringResource(R.string.link_nothing_to_link),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 16.dp),
                )
            }
            LazyColumn {
                items(matches, key = { "${it.ref.type}-${it.ref.id}" }) { record ->
                    ListItem(
                        headlineContent = { Text(record.title) },
                        supportingContent = { Text(stringResource(record.ref.type.title)) },
                        leadingContent = { Icon(record.ref.type.kind.icon, contentDescription = null) },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                        modifier = Modifier.clickable(role = Role.Button) {
                            viewModel.link(record.ref, note)
                            onDismiss()
                        },
                    )
                }
            }
        }
    }
}
