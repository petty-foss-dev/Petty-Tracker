@file:UseSerializers(LocalDateSerializer::class, BigDecimalSerializer::class)

package com.isaaclamb.pettytracker.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import java.math.BigDecimal
import java.time.LocalDate

@Serializable
@Entity(tableName = "products")
data class Product(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val brand: String = "",
    val model: String = "",
    val serialNumber: String = "",
    val purchaseDate: LocalDate? = null,
    val retailer: String = "",
    val price: BigDecimal? = null,
    val currency: String,
    val warrantyExpires: LocalDate? = null,
    val notes: String = "",
    // The product's page on the seller's or maker's site; saved copies are attachments labelled PRODUCT_PAGE.
    val productUrl: String = "",
)

@Serializable
enum class CycleUnit { DAYS, WEEKS, MONTHS, YEARS }

@Serializable
@Entity(tableName = "subscriptions")
data class Subscription(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val price: BigDecimal? = null,
    val currency: String,
    val cycleCount: Int = 1,
    val cycleUnit: CycleUnit = CycleUnit.MONTHS,
    val nextRenewal: LocalDate,
    // Original billing date the schedule is derived from, so month-end renewals don't drift.
    val anchorDate: LocalDate = nextRenewal,
    val canceledOn: LocalDate? = null,
    val notes: String = "",
) {
    val isActive: Boolean get() = canceledOn == null
}

@Serializable
@Entity(tableName = "documents")
data class Document(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val issuer: String = "",
    val reference: String = "",
    val issuedOn: LocalDate? = null,
    val expiresOn: LocalDate? = null,
    val notes: String = "",
)

@Serializable
enum class OwnerType { PRODUCT, DOCUMENT }

/** What a file shows, so a product's photos, parts and manuals can be told apart. */
@Serializable
enum class AttachmentLabel { ITEM, PART, INSTRUCTIONS, PRODUCT_PAGE, WARRANTY, OTHER }

@Serializable
@Entity(tableName = "attachments", indices = [Index("ownerType", "ownerId")])
data class Attachment(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val ownerType: OwnerType,
    val ownerId: Long,
    val displayName: String,
    val mimeType: String,
    val fileName: String,
    val sizeBytes: Long,
    val label: AttachmentLabel = AttachmentLabel.OTHER,
) {
    val isImage: Boolean get() = mimeType.startsWith("image/")
}

/** Any record a link can point at. Receipts exist only on iOS, so Android never sees links to them. */
@Serializable
enum class RecordType { PRODUCT, SUBSCRIPTION, DOCUMENT }

data class RecordRef(val type: RecordType, val id: Long)

/** A cross-reference between two records, shown on both. [note] says how they relate, such as "Insurance". */
@Serializable
@Entity(tableName = "record_links", indices = [Index("fromType", "fromId"), Index("toType", "toId")])
data class RecordLink(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val fromType: RecordType,
    val fromId: Long,
    val toType: RecordType,
    val toId: Long,
    val note: String = "",
) {
    val from: RecordRef get() = RecordRef(fromType, fromId)
    val to: RecordRef get() = RecordRef(toType, toId)

    fun other(than: RecordRef): RecordRef? = when (than) {
        from -> to
        to -> from
        else -> null
    }
}

@Entity(tableName = "sent_reminders")
data class SentReminder(@PrimaryKey val key: String)
