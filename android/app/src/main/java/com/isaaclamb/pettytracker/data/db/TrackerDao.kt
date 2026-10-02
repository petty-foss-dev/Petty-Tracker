package com.isaaclamb.pettytracker.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import com.isaaclamb.pettytracker.data.Attachment
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.OwnerType
import com.isaaclamb.pettytracker.data.AttachmentLabel
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.data.RecordLink
import com.isaaclamb.pettytracker.data.RecordType
import com.isaaclamb.pettytracker.data.SentReminder
import com.isaaclamb.pettytracker.data.Subscription
import kotlinx.coroutines.flow.Flow

@Dao
interface TrackerDao {
    @Query("SELECT * FROM products ORDER BY name COLLATE NOCASE")
    fun products(): Flow<List<Product>>

    @Query("SELECT * FROM products WHERE id = :id")
    fun product(id: Long): Flow<Product?>

    @Query("SELECT * FROM products")
    suspend fun allProducts(): List<Product>

    @Upsert suspend fun upsertProduct(product: Product): Long

    @Query("DELETE FROM products WHERE id = :id")
    suspend fun deleteProduct(id: Long)

    @Query("SELECT * FROM subscriptions ORDER BY name COLLATE NOCASE")
    fun subscriptions(): Flow<List<Subscription>>

    @Query("SELECT * FROM subscriptions WHERE id = :id")
    fun subscription(id: Long): Flow<Subscription?>

    @Query("SELECT * FROM subscriptions WHERE id = :id")
    suspend fun subscriptionNow(id: Long): Subscription?

    @Query("SELECT * FROM subscriptions")
    suspend fun allSubscriptions(): List<Subscription>

    @Upsert suspend fun upsertSubscription(subscription: Subscription): Long

    @Query("DELETE FROM subscriptions WHERE id = :id")
    suspend fun deleteSubscription(id: Long)

    @Query("SELECT * FROM documents ORDER BY title COLLATE NOCASE")
    fun documents(): Flow<List<Document>>

    @Query("SELECT * FROM documents WHERE id = :id")
    fun document(id: Long): Flow<Document?>

    @Query("SELECT * FROM documents")
    suspend fun allDocuments(): List<Document>

    @Upsert suspend fun upsertDocument(document: Document): Long

    @Query("DELETE FROM documents WHERE id = :id")
    suspend fun deleteDocument(id: Long)

    @Query("SELECT * FROM attachments WHERE ownerType = :type AND ownerId = :ownerId ORDER BY id")
    fun attachments(type: OwnerType, ownerId: Long): Flow<List<Attachment>>

    @Query("SELECT * FROM attachments WHERE ownerType = :type AND ownerId = :ownerId")
    suspend fun attachmentsNow(type: OwnerType, ownerId: Long): List<Attachment>

    @Query("SELECT * FROM attachments")
    suspend fun allAttachments(): List<Attachment>

    @Query("SELECT fileName FROM attachments")
    suspend fun attachmentFileNames(): List<String>

    @Insert suspend fun insertAttachments(attachments: List<Attachment>)

    @Delete suspend fun deleteAttachments(attachments: List<Attachment>)

    @Query("DELETE FROM attachments WHERE ownerType = :type AND ownerId = :ownerId")
    suspend fun deleteAttachmentsFor(type: OwnerType, ownerId: Long)

    @Query("UPDATE attachments SET label = :label WHERE id = :id")
    suspend fun setAttachmentLabel(id: Long, label: AttachmentLabel)

    @Query("SELECT * FROM record_links WHERE (fromType = :type AND fromId = :id) OR (toType = :type AND toId = :id) ORDER BY id")
    fun links(type: RecordType, id: Long): Flow<List<RecordLink>>

    @Query("SELECT * FROM record_links WHERE (fromType = :aType AND fromId = :aId AND toType = :bType AND toId = :bId) OR (fromType = :bType AND fromId = :bId AND toType = :aType AND toId = :aId)")
    suspend fun linkBetween(aType: RecordType, aId: Long, bType: RecordType, bId: Long): RecordLink?

    @Query("SELECT * FROM record_links")
    suspend fun allLinks(): List<RecordLink>

    @Upsert suspend fun upsertLink(link: RecordLink)

    @Query("DELETE FROM record_links WHERE id = :id")
    suspend fun deleteLink(id: Long)

    @Query("DELETE FROM record_links WHERE (fromType = :type AND fromId = :id) OR (toType = :type AND toId = :id)")
    suspend fun deleteLinksFor(type: RecordType, id: Long)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun markReminderSent(reminder: SentReminder): Long

    @Query("DELETE FROM sent_reminders")
    suspend fun clearSentReminders()

    @Insert suspend fun insertProducts(items: List<Product>)
    @Insert suspend fun insertSubscriptions(items: List<Subscription>)
    @Insert suspend fun insertDocuments(items: List<Document>)
    @Insert suspend fun insertLinks(items: List<RecordLink>)

    @Query("DELETE FROM products") suspend fun clearProducts()
    @Query("DELETE FROM subscriptions") suspend fun clearSubscriptions()
    @Query("DELETE FROM documents") suspend fun clearDocuments()
    @Query("DELETE FROM attachments") suspend fun clearAttachments()
    @Query("DELETE FROM record_links") suspend fun clearLinks()
}
