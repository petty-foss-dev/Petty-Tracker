@file:UseSerializers(LocalDateSerializer::class, BigDecimalSerializer::class)

package com.enve.keep.data

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
) {
    val isImage: Boolean get() = mimeType.startsWith("image/")
}

@Entity(tableName = "sent_reminders")
data class SentReminder(@PrimaryKey val key: String)
