package com.isaaclamb.pettytracker.ui

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.isaaclamb.pettytracker.TrackerApplication
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.data.Attachment
import com.isaaclamb.pettytracker.data.AttachmentStore
import com.isaaclamb.pettytracker.data.OwnerType
import kotlinx.coroutines.launch
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

@Composable
inline fun <reified VM : ViewModel> trackerViewModel(
    crossinline create: (TrackerApplication, SavedStateHandle) -> VM,
): VM = viewModel(
    factory = viewModelFactory {
        initializer {
            create(this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as TrackerApplication, createSavedStateHandle())
        }
    }
)

/** Holds an editor's state as JSON in the SavedStateHandle so drafts survive process death. */
abstract class FormViewModel<F : Any>(
    private val handle: SavedStateHandle,
    private val serializer: KSerializer<F>,
    initial: F,
) : ViewModel() {
    protected val restored: Boolean = handle.contains(FORM_KEY)

    var form by mutableStateOf(handle.get<String>(FORM_KEY)?.let { json.decodeFromString(serializer, it) } ?: initial)
        private set

    var message by mutableStateOf<Int?>(null)

    fun update(transform: (F) -> F) {
        form = transform(form)
        handle[FORM_KEY] = json.encodeToString(serializer, form)
    }

    private companion object {
        const val FORM_KEY = "form"
        val json = Json { ignoreUnknownKeys = true }
    }
}

@Serializable
data class AttachmentDraft(
    val current: List<Attachment> = emptyList(),
    val added: List<Attachment> = emptyList(),
    val removed: List<Attachment> = emptyList(),
)

abstract class AttachmentFormViewModel<F : Any>(
    handle: SavedStateHandle,
    serializer: KSerializer<F>,
    initial: F,
    val attachmentStore: AttachmentStore,
    private val ownerType: OwnerType,
) : FormViewModel<F>(handle, serializer, initial) {
    protected abstract fun F.draft(): AttachmentDraft
    protected abstract fun F.withDraft(draft: AttachmentDraft): F

    val attachments: List<Attachment> get() = form.draft().current

    var importing by mutableStateOf(false)
        private set

    protected var saved = false

    fun addFiles(uris: List<Uri>) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            importing = true
            uris.forEach { uri ->
                runCatching { attachmentStore.import(uri, ownerType) }
                    .onSuccess(::add)
                    .onFailure { message = R.string.attachment_import_failed }
            }
            importing = false
        }
    }

    fun newPhotoFile(): File = attachmentStore.newPhotoFile()

    fun onPhotoResult(fileName: String, success: Boolean) {
        val file = attachmentStore.file(fileName)
        if (success && file.length() > 0) {
            val name = "Photo ${LocalDateTime.now().format(PHOTO_NAME_FORMAT)}.jpg"
            add(attachmentStore.photoAttachment(file, ownerType, name))
        } else {
            file.delete()
        }
    }

    fun remove(attachment: Attachment) {
        val draft = form.draft()
        val next = if (attachment in draft.added) {
            attachmentStore.delete(listOf(attachment.fileName))
            draft.copy(current = draft.current - attachment, added = draft.added - attachment)
        } else {
            draft.copy(current = draft.current - attachment, removed = draft.removed + attachment)
        }
        update { it.withDraft(next) }
    }

    private fun add(attachment: Attachment) = update {
        val draft = it.draft()
        it.withDraft(draft.copy(current = draft.current + attachment, added = draft.added + attachment))
    }

    override fun onCleared() {
        if (!saved) attachmentStore.delete(form.draft().added.map { it.fileName })
    }

    private companion object {
        val PHOTO_NAME_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH.mm.ss")
    }
}
