@file:UseSerializers(LocalDateSerializer::class)

package com.isaaclamb.pettytracker.ui.documents

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.toRoute
import com.isaaclamb.pettytracker.TrackerApplication
import com.isaaclamb.pettytracker.data.Attachment
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.LocalDateSerializer
import com.isaaclamb.pettytracker.data.OwnerType
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.deadlineSortKey
import com.isaaclamb.pettytracker.domain.deadlineStatus
import com.isaaclamb.pettytracker.domain.matches
import com.isaaclamb.pettytracker.domain.sortRank
import com.isaaclamb.pettytracker.ui.AttachmentDraft
import com.isaaclamb.pettytracker.ui.AttachmentFormViewModel
import com.isaaclamb.pettytracker.ui.RecordDetailViewModel
import com.isaaclamb.pettytracker.ui.DocumentDetailRoute
import com.isaaclamb.pettytracker.ui.DocumentEditRoute
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import java.time.LocalDate

enum class DocumentFilter { ALL, VALID, EXPIRING, EXPIRED }

data class DocumentItem(val document: Document, val status: DeadlineStatus)

data class DocumentListState(
    val loaded: Boolean = false,
    val hasAny: Boolean = false,
    val items: List<DocumentItem> = emptyList(),
)

class DocumentListViewModel(app: TrackerApplication) : ViewModel() {
    val query = MutableStateFlow("")
    val filter = MutableStateFlow(DocumentFilter.ALL)

    val state: StateFlow<DocumentListState> = combine(
        app.container.repository.documents,
        app.container.settingsRepository.settings,
        query,
        filter,
    ) { documents, settings, query, filter ->
        val today = LocalDate.now()
        val items = documents
            .filter { it.matches(query) }
            .map { DocumentItem(it, deadlineStatus(it.expiresOn, today, settings.documentLeadDays)) }
            .filter {
                when (filter) {
                    DocumentFilter.ALL -> true
                    DocumentFilter.VALID -> it.status != DeadlineStatus.PAST
                    DocumentFilter.EXPIRING -> it.status == DeadlineStatus.SOON || it.status == DeadlineStatus.TODAY
                    DocumentFilter.EXPIRED -> it.status == DeadlineStatus.PAST
                }
            }
            .sortedWith(compareBy({ it.status.sortRank }, { deadlineSortKey(it.document.expiresOn, it.status) }))
        DocumentListState(loaded = true, hasAny = documents.isNotEmpty(), items = items)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DocumentListState())
}

data class DocumentDetailState(
    val loaded: Boolean = false,
    val document: Document? = null,
    val attachments: List<Attachment> = emptyList(),
    val leadDays: Int = 0,
)

class DocumentDetailViewModel(app: TrackerApplication, handle: SavedStateHandle) :
    RecordDetailViewModel(app, OwnerType.DOCUMENT, handle.toRoute<DocumentDetailRoute>().id) {

    val state: StateFlow<DocumentDetailState> = combine(
        app.container.repository.document(id),
        app.container.repository.attachments(OwnerType.DOCUMENT, id),
        app.container.settingsRepository.settings,
    ) { document, attachments, settings ->
        DocumentDetailState(true, document, attachments, settings.documentLeadDays)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DocumentDetailState())

    fun delete() {
        viewModelScope.launch { app.container.repository.deleteDocument(id) }
    }
}

@Serializable
data class DocumentForm(
    val loaded: Boolean = false,
    val changed: Boolean = false,
    val showErrors: Boolean = false,
    val title: String = "",
    val issuer: String = "",
    val reference: String = "",
    val issuedOn: LocalDate? = null,
    val expiresOn: LocalDate? = null,
    val notes: String = "",
    val attachments: AttachmentDraft = AttachmentDraft(),
) {
    val titleError get() = showErrors && title.isBlank()
    val expiresBeforeIssued get() = issuedOn != null && expiresOn != null && expiresOn.isBefore(issuedOn)
}

class DocumentEditViewModel(private val app: TrackerApplication, handle: SavedStateHandle) :
    AttachmentFormViewModel<DocumentForm>(
        handle,
        DocumentForm.serializer(),
        DocumentForm(),
        app.container.attachmentStore,
        OwnerType.DOCUMENT,
    ) {
    val id = handle.toRoute<DocumentEditRoute>().id
    private var saving = false

    override fun DocumentForm.draft() = attachments
    override fun DocumentForm.withDraft(draft: AttachmentDraft) = copy(attachments = draft, changed = true)

    init {
        if (!restored) viewModelScope.launch {
            val repository = app.container.repository
            val document = if (id != 0L) repository.document(id).first() else null
            if (document == null) {
                update { it.copy(loaded = true) }
            } else {
                val attachments = repository.attachments(OwnerType.DOCUMENT, id).first()
                update {
                    DocumentForm(
                        loaded = true,
                        title = document.title,
                        issuer = document.issuer,
                        reference = document.reference,
                        issuedOn = document.issuedOn,
                        expiresOn = document.expiresOn,
                        notes = document.notes,
                        attachments = AttachmentDraft(current = attachments),
                    )
                }
            }
        }
    }

    fun edit(transform: (DocumentForm) -> DocumentForm) = update { transform(it).copy(changed = true) }

    fun save(onSaved: (id: Long, isNew: Boolean) -> Unit) {
        val form = form
        if (form.title.isBlank()) {
            update { it.copy(showErrors = true) }
            return
        }
        if (saving) return
        saving = true
        viewModelScope.launch {
            val document = Document(
                id = id,
                title = form.title.trim(),
                issuer = form.issuer.trim(),
                reference = form.reference.trim(),
                issuedOn = form.issuedOn,
                expiresOn = form.expiresOn,
                notes = form.notes.trim(),
            )
            val savedId = app.container.repository.saveDocument(document, form.attachments.added, form.attachments.removed)
            saved = true
            onSaved(savedId, id == 0L)
        }
    }
}
