package com.isaaclamb.pettytracker.data.backup

import android.content.Context
import android.net.Uri
import androidx.room.withTransaction
import com.isaaclamb.pettytracker.data.AttachmentStore
import com.isaaclamb.pettytracker.data.SettingsRepository
import com.isaaclamb.pettytracker.data.db.TrackerDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant

data class ImportSummary(val products: Int, val subscriptions: Int, val documents: Int, val attachments: Int)

class BackupManager(
    private val context: Context,
    private val database: TrackerDatabase,
    private val attachmentStore: AttachmentStore,
    private val settingsRepository: SettingsRepository,
) {
    private val dao = database.dao()

    suspend fun export(uri: Uri) = withContext(Dispatchers.IO) {
        val settings = settingsRepository.current()
        val manifest = database.withTransaction {
            BackupManifest(
                exportedAt = Instant.now().toString(),
                products = dao.allProducts(),
                subscriptions = dao.allSubscriptions(),
                documents = dao.allDocuments(),
                attachments = dao.allAttachments(),
                links = dao.allLinks(),
                settings = settings,
            )
        }
        val output = context.contentResolver.openOutputStream(uri, "wt") ?: error("Unable to open $uri")
        output.use { BackupArchive.write(manifest, attachmentStore.directory, it) }
    }

    /** Replaces all local data with the backup's contents. Nothing changes if the archive is invalid. */
    suspend fun import(uri: Uri): ImportSummary = withContext(Dispatchers.IO) {
        val filesDir = context.filesDir
        val staging = File(filesDir, "import-staging").apply { deleteRecursively(); mkdirs() }
        try {
            val input = context.contentResolver.openInputStream(uri) ?: error("Unable to open $uri")
            val manifest = input.use { BackupArchive.read(it, staging) }

            val live = attachmentStore.directory
            val previous = File(filesDir, "attachments-previous").apply { deleteRecursively() }
            check(live.renameTo(previous)) { "Unable to stage current attachments" }
            if (!File(staging, "attachments").renameTo(live)) {
                check(previous.renameTo(live)) { "Unable to restore current attachments" }
                error("Unable to move imported attachments")
            }
            try {
                database.withTransaction {
                    dao.clearAttachments()
                    dao.clearLinks()
                    dao.clearProducts()
                    dao.clearSubscriptions()
                    dao.clearDocuments()
                    dao.clearSentReminders()
                    dao.insertProducts(manifest.products)
                    dao.insertSubscriptions(manifest.subscriptions)
                    dao.insertDocuments(manifest.documents)
                    dao.insertAttachments(manifest.attachments)
                    dao.insertLinks(manifest.links)
                }
            } catch (e: Exception) {
                live.deleteRecursively()
                previous.renameTo(live)
                throw e
            }
            previous.deleteRecursively()
            manifest.settings?.let { imported ->
                settingsRepository.update { imported.copy(reminderPromptDismissed = it.reminderPromptDismissed) }
            }
            ImportSummary(
                products = manifest.products.size,
                subscriptions = manifest.subscriptions.size,
                documents = manifest.documents.size,
                attachments = manifest.attachments.size,
            )
        } finally {
            staging.deleteRecursively()
        }
    }
}
