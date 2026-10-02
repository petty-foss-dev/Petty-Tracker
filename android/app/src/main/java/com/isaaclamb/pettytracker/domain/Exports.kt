package com.isaaclamb.pettytracker.domain

import com.isaaclamb.pettytracker.data.CycleUnit
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.data.Settings
import com.isaaclamb.pettytracker.data.Subscription
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** Wording for exported files, supplied from string resources so the exporters stay plain Kotlin. */
interface ExportText {
    fun warrantyEnds(name: String): String
    fun expires(title: String): String
    fun renews(name: String, price: String?): String
    fun serialNumber(value: String): String
    fun documentNumber(value: String): String
    fun cycle(count: Int, unit: CycleUnit): String
    fun type(kind: RecordKind): String
    fun status(status: DeadlineStatus, kind: RecordKind): String
    fun price(amount: BigDecimal, currency: String): String
    val canceled: String
}

data class ExportRecords(
    val products: List<Product>,
    val subscriptions: List<Subscription>,
    val documents: List<Document>,
    val settings: Settings,
)

/**
 * An iCalendar (RFC 5545) file of upcoming warranty ends, document expiries and subscription renewals, matching
 * the iOS export. Every event is all-day and carries an alert at the reminder lead time.
 */
object CalendarExport {
    // Renewals are listed one event each, so month-end billing dates stay exact.
    const val RENEWAL_HORIZON_MONTHS = 24L
    const val MAX_RENEWALS_PER_SUBSCRIPTION = 60

    data class Event(val uid: String, val day: LocalDate, val summary: String, val details: List<String>, val alertDaysBefore: Int)

    fun events(records: ExportRecords, today: LocalDate, text: ExportText): List<Event> {
        val settings = records.settings
        val events = mutableListOf<Event>()
        records.products.forEach { product ->
            val expires = product.warrantyExpires ?: return@forEach
            if (expires.isBefore(today)) return@forEach
            events += Event(
                uid = "warranty-${product.id}",
                day = expires,
                summary = text.warrantyEnds(product.name),
                details = listOf(
                    listOf(product.brand, product.model).filter { it.isNotBlank() }.joinToString(" "),
                    product.serialNumber.takeIf { it.isNotBlank() }?.let(text::serialNumber).orEmpty(),
                    product.productUrl,
                ),
                alertDaysBefore = settings.warrantyLeadDays,
            )
        }
        records.documents.forEach { document ->
            val expires = document.expiresOn ?: return@forEach
            if (expires.isBefore(today)) return@forEach
            events += Event(
                uid = "document-${document.id}",
                day = expires,
                summary = text.expires(document.title),
                details = listOf(document.issuer, document.reference.takeIf { it.isNotBlank() }?.let(text::documentNumber).orEmpty()),
                alertDaysBefore = settings.documentLeadDays,
            )
        }
        val horizon = today.plusMonths(RENEWAL_HORIZON_MONTHS)
        records.subscriptions.filter { it.isActive }.forEach { subscription ->
            val price = subscription.price?.let { text.price(it, subscription.currency) }
            var day = subscription.nextRenewal
            var listed = 0
            while (!day.isAfter(horizon) && listed < MAX_RENEWALS_PER_SUBSCRIPTION) {
                if (!day.isBefore(today)) {
                    events += Event(
                        uid = "subscription-${subscription.id}-$day",
                        day = day,
                        summary = text.renews(subscription.name, price),
                        details = listOf(text.cycle(subscription.cycleCount, subscription.cycleUnit)),
                        alertDaysBefore = settings.subscriptionLeadDays,
                    )
                    listed++
                }
                day = Renewals.nextAfter(subscription.anchorDate, subscription.cycleCount, subscription.cycleUnit, day)
            }
        }
        return events.sortedWith(compareBy({ it.day }, { it.uid }))
    }

    fun make(records: ExportRecords, today: LocalDate, now: Instant, text: ExportText): String {
        val stamp = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC).format(now)
        val lines = mutableListOf(
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Petty FOSS//petty: Tracker//EN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:${escape("petty: Tracker")}",
        )
        events(records, today, text).forEach { event ->
            val details = event.details.filter { it.isNotBlank() }.joinToString("\n")
            lines += listOf(
                "BEGIN:VEVENT",
                "UID:${event.uid}@petty-tracker",
                "DTSTAMP:$stamp",
                "DTSTART;VALUE=DATE:${compact(event.day)}",
                "DTEND;VALUE=DATE:${compact(event.day.plusDays(1))}",
                "SUMMARY:${escape(event.summary)}",
            )
            if (details.isNotEmpty()) lines += "DESCRIPTION:${escape(details)}"
            lines += listOf(
                "TRANSP:TRANSPARENT",
                "BEGIN:VALARM",
                "ACTION:DISPLAY",
                "DESCRIPTION:${escape(event.summary)}",
                "TRIGGER:-P${event.alertDaysBefore}D",
                "END:VALARM",
                "END:VEVENT",
            )
        }
        lines += "END:VCALENDAR"
        return lines.joinToString("\r\n", postfix = "\r\n") { fold(it) }
    }

    private fun compact(day: LocalDate) = day.toString().replace("-", "")

    /** Escapes TEXT values: backslash, semicolon, comma and newlines. */
    fun escape(value: String): String = value
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")

    /** Splits lines longer than 75 octets, continuing with a leading space, without breaking a character. */
    fun fold(line: String): String {
        val parts = mutableListOf<String>()
        val current = StringBuilder()
        var octets = 0
        var index = 0
        while (index < line.length) {
            val codePoint = line.codePointAt(index)
            val character = String(Character.toChars(codePoint))
            val size = character.toByteArray(Charsets.UTF_8).size
            val limit = if (parts.isEmpty()) 75 else 74
            if (octets + size > limit) {
                parts += current.toString()
                current.clear()
                octets = 0
            }
            current.append(character)
            octets += size
            index += Character.charCount(codePoint)
        }
        parts += current.toString()
        return parts.joinToString("\r\n ")
    }
}

/**
 * One spreadsheet of every product, subscription and document, with the same columns as the iOS export. Dates
 * are ISO `yyyy-MM-dd` and amounts plain decimals so any spreadsheet locale reads them.
 */
object RecordsCsv {
    val HEADER = listOf(
        "Type", "Name", "Due Date", "Status", "Brand", "Model", "Serial Number", "Purchase Date", "Retailer",
        "Price", "Currency", "Billing Cycle", "Per Month", "Canceled On", "Issued By", "Document Number",
        "Issued On", "Product Page", "Notes",
    )

    fun make(records: ExportRecords, today: LocalDate, text: ExportText): String {
        val settings = records.settings
        val rows = mutableListOf(HEADER)
        records.products.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name }).forEach { product ->
            val status = deadlineStatus(product.warrantyExpires, today, settings.warrantyLeadDays)
            rows += listOf(
                text.type(RecordKind.WARRANTY), safe(product.name), product.warrantyExpires.iso(),
                text.status(status, RecordKind.WARRANTY), safe(product.brand), safe(product.model), safe(product.serialNumber),
                product.purchaseDate.iso(), safe(product.retailer), product.price.plain(), product.currency,
                "", "", "", "", "", "", safe(product.productUrl), safe(product.notes),
            )
        }
        records.subscriptions.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name }).forEach { subscription ->
            val status = if (subscription.isActive) {
                text.status(deadlineStatus(subscription.nextRenewal, today, settings.subscriptionLeadDays), RecordKind.SUBSCRIPTION)
            } else {
                text.canceled
            }
            val monthly = subscription.price?.let {
                Renewals.monthlyCost(it, subscription.cycleCount, subscription.cycleUnit).setScale(2, RoundingMode.HALF_EVEN)
            }
            rows += listOf(
                text.type(RecordKind.SUBSCRIPTION), safe(subscription.name),
                (if (subscription.isActive) subscription.nextRenewal else null).iso(), status,
                "", "", "", "", "", subscription.price.plain(), subscription.currency,
                text.cycle(subscription.cycleCount, subscription.cycleUnit), monthly.plain(), subscription.canceledOn.iso(),
                "", "", "", "", safe(subscription.notes),
            )
        }
        records.documents.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title }).forEach { document ->
            val status = deadlineStatus(document.expiresOn, today, settings.documentLeadDays)
            rows += listOf(
                text.type(RecordKind.DOCUMENT), safe(document.title), document.expiresOn.iso(),
                text.status(status, RecordKind.DOCUMENT), "", "", "", "", "", "", "", "", "", "",
                safe(document.issuer), safe(document.reference), document.issuedOn.iso(), "", safe(document.notes),
            )
        }
        return rows.joinToString("\r\n", postfix = "\r\n") { row -> row.joinToString(",") { field(it) } }
    }

    private fun LocalDate?.iso() = this?.toString().orEmpty()

    private fun BigDecimal?.plain() = this?.stripTrailingZeros()?.let { if (it.scale() < 0) it.setScale(0) else it }?.toPlainString().orEmpty()

    fun field(value: String): String =
        if (value.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) "\"" + value.replace("\"", "\"\"") + "\"" else value

    /** Names and notes typed by people could start like a spreadsheet formula; a leading apostrophe keeps them text. */
    private fun safe(value: String): String = if (value.firstOrNull() in setOf('=', '+', '-', '@', '\t', '\r')) "'$value" else value
}
