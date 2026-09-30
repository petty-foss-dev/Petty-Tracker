package com.enve.keep.domain

import com.enve.keep.data.Document
import com.enve.keep.data.Product
import com.enve.keep.data.Settings
import com.enve.keep.data.Subscription
import java.text.Normalizer
import java.time.LocalDate
import java.time.temporal.ChronoUnit

enum class RecordKind { WARRANTY, SUBSCRIPTION, DOCUMENT }

enum class DeadlineStatus { NONE, OK, SOON, TODAY, PAST }

data class Deadline(
    val kind: RecordKind,
    val id: Long,
    val title: String,
    val date: LocalDate,
) {
    fun daysFrom(today: LocalDate): Long = ChronoUnit.DAYS.between(today, date)
}

fun deadlineStatus(date: LocalDate?, today: LocalDate, leadDays: Int): DeadlineStatus {
    if (date == null) return DeadlineStatus.NONE
    val days = ChronoUnit.DAYS.between(today, date)
    return when {
        days < 0 -> DeadlineStatus.PAST
        days == 0L -> DeadlineStatus.TODAY
        days <= leadDays -> DeadlineStatus.SOON
        else -> DeadlineStatus.OK
    }
}

/** Upcoming dates sort soonest first; past dates sort most recent first. */
fun deadlineSortKey(date: LocalDate?, status: DeadlineStatus): Long? =
    date?.toEpochDay()?.let { if (status == DeadlineStatus.PAST) -it else it }

val DeadlineStatus.sortRank: Int
    get() = when (this) {
        DeadlineStatus.TODAY -> 0
        DeadlineStatus.SOON -> 1
        DeadlineStatus.OK -> 2
        DeadlineStatus.NONE -> 3
        DeadlineStatus.PAST -> 4
    }

fun Settings.leadDays(kind: RecordKind): Int = when (kind) {
    RecordKind.WARRANTY -> warrantyLeadDays
    RecordKind.SUBSCRIPTION -> subscriptionLeadDays
    RecordKind.DOCUMENT -> documentLeadDays
}

fun Product.deadline(): Deadline? = warrantyExpires?.let { Deadline(RecordKind.WARRANTY, id, name, it) }

fun Subscription.deadline(): Deadline? =
    if (isActive) Deadline(RecordKind.SUBSCRIPTION, id, name, nextRenewal) else null

fun Document.deadline(): Deadline? = expiresOn?.let { Deadline(RecordKind.DOCUMENT, id, title, it) }

fun Product.matches(query: String) = matchesAny(query, name, brand, model, serialNumber, retailer, notes)

fun Subscription.matches(query: String) = matchesAny(query, name, notes)

fun Document.matches(query: String) = matchesAny(query, title, issuer, reference, notes)

private fun matchesAny(query: String, vararg fields: String): Boolean {
    val terms = fold(query).split(' ').filter { it.isNotBlank() }
    if (terms.isEmpty()) return true
    val haystack = fields.joinToString(" ") { fold(it) }
    return terms.all { it in haystack }
}

private val diacritics = Regex("\\p{Mn}+")

private fun fold(text: String): String =
    diacritics.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase()
