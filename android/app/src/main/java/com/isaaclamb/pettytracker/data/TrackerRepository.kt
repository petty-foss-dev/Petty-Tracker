package com.isaaclamb.pettytracker.data

import androidx.room.withTransaction
import com.isaaclamb.pettytracker.data.db.TrackerDatabase
import kotlinx.coroutines.flow.Flow

class TrackerRepository(
    private val database: TrackerDatabase,
    private val attachmentStore: AttachmentStore,
) {
    private val dao = database.dao()

    val products: Flow<List<Product>> = dao.products()
    val subscriptions: Flow<List<Subscription>> = dao.subscriptions()
    val documents: Flow<List<Document>> = dao.documents()

    fun product(id: Long) = dao.product(id)
    fun subscription(id: Long) = dao.subscription(id)
    fun document(id: Long) = dao.document(id)
    fun attachments(type: OwnerType, ownerId: Long) = dao.attachments(type, ownerId)

    suspend fun saveProduct(product: Product, added: List<Attachment>, removed: List<Attachment>): Long =
        saveWithAttachments(OwnerType.PRODUCT, added, removed) {
            val id = dao.upsertProduct(product)
            if (product.id == 0L) id else product.id
        }

    suspend fun saveDocument(document: Document, added: List<Attachment>, removed: List<Attachment>): Long =
        saveWithAttachments(OwnerType.DOCUMENT, added, removed) {
            val id = dao.upsertDocument(document)
            if (document.id == 0L) id else document.id
        }

    suspend fun saveSubscription(subscription: Subscription): Long {
        val id = dao.upsertSubscription(subscription)
        return if (subscription.id == 0L) id else subscription.id
    }

    suspend fun deleteProduct(id: Long) = deleteWithAttachments(OwnerType.PRODUCT, id) { dao.deleteProduct(id) }

    suspend fun deleteDocument(id: Long) = deleteWithAttachments(OwnerType.DOCUMENT, id) { dao.deleteDocument(id) }

    suspend fun deleteSubscription(id: Long) = dao.deleteSubscription(id)

    suspend fun updateSubscription(id: Long, transform: (Subscription) -> Subscription) {
        database.withTransaction {
            dao.subscriptionNow(id)?.let { dao.upsertSubscription(transform(it)) }
        }
    }

    /** Attaches files already copied into the store, deleting the copies if the insert fails. */
    suspend fun addAttachments(type: OwnerType, ownerId: Long, added: List<Attachment>) {
        try {
            dao.insertAttachments(added.map { it.copy(id = 0, ownerType = type, ownerId = ownerId) })
        } catch (e: Exception) {
            attachmentStore.delete(added.map { it.fileName })
            throw e
        }
    }

    suspend fun removeAttachment(attachment: Attachment) {
        dao.deleteAttachments(listOf(attachment))
        attachmentStore.delete(listOf(attachment.fileName))
    }

    suspend fun referencedFileNames(): Set<String> = dao.attachmentFileNames().toSet()

    private suspend fun saveWithAttachments(
        type: OwnerType,
        added: List<Attachment>,
        removed: List<Attachment>,
        upsert: suspend () -> Long,
    ): Long {
        val id = database.withTransaction {
            val id = upsert()
            dao.insertAttachments(added.map { it.copy(id = 0, ownerType = type, ownerId = id) })
            dao.deleteAttachments(removed)
            id
        }
        attachmentStore.delete(removed.map { it.fileName })
        return id
    }

    private suspend fun deleteWithAttachments(type: OwnerType, id: Long, delete: suspend () -> Unit) {
        val files = database.withTransaction {
            val files = dao.attachmentsNow(type, id).map { it.fileName }
            dao.deleteAttachmentsFor(type, id)
            delete()
            files
        }
        attachmentStore.delete(files)
    }
}
