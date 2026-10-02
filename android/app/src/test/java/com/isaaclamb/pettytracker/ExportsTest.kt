package com.isaaclamb.pettytracker

import com.isaaclamb.pettytracker.data.CycleUnit
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.data.Settings
import com.isaaclamb.pettytracker.data.Subscription
import com.isaaclamb.pettytracker.domain.CalendarExport
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.ExportRecords
import com.isaaclamb.pettytracker.domain.ExportText
import com.isaaclamb.pettytracker.domain.RecordKind
import com.isaaclamb.pettytracker.domain.RecordsCsv
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate

class ExportsTest {
    private val today = LocalDate.parse("2026-10-01")

    private val text = object : ExportText {
        override fun warrantyEnds(name: String) = "Warranty ends: $name"
        override fun expires(title: String) = "Expires: $title"
        override fun renews(name: String, price: String?) = if (price == null) "Renews: $name" else "Renews: $name ($price)"
        override fun serialNumber(value: String) = "Serial number: $value"
        override fun documentNumber(value: String) = "Number: $value"
        override fun cycle(count: Int, unit: CycleUnit) = if (count == 1) "Every ${unit.name.lowercase().dropLast(1)}" else "Every $count"
        override fun type(kind: RecordKind) = when (kind) {
            RecordKind.WARRANTY -> "Product"
            RecordKind.SUBSCRIPTION -> "Subscription"
            RecordKind.DOCUMENT -> "Document"
        }
        override fun status(status: DeadlineStatus, kind: RecordKind) = status.name
        override fun price(amount: BigDecimal, currency: String) = "$$amount"
        override val canceled = "Canceled"
    }

    private val records = ExportRecords(
        products = listOf(
            Product(id = 1, name = "Laptop", currency = "USD", warrantyExpires = LocalDate.parse("2026-10-12")),
            Product(id = 2, name = "Old blender", currency = "USD", warrantyExpires = LocalDate.parse("2026-01-01")),
        ),
        subscriptions = listOf(
            Subscription(
                id = 4, name = "Cloud", price = BigDecimal("9.99"), currency = "USD",
                nextRenewal = LocalDate.parse("2026-10-31"), anchorDate = LocalDate.parse("2024-01-31"),
            ),
            Subscription(
                id = 5, name = "Gone", currency = "USD", nextRenewal = LocalDate.parse("2026-10-05"),
                canceledOn = LocalDate.parse("2026-09-01"),
            ),
        ),
        documents = listOf(Document(id = 3, title = "Passport", reference = "X1", expiresOn = LocalDate.parse("2027-03-08"))),
        settings = Settings(defaultCurrency = "USD"),
    )

    @Test
    fun listsUpcomingDatesWithReminderLeadTimes() {
        val events = CalendarExport.events(records, today, text)
        assertFalse(events.any { it.uid == "warranty-2" })
        assertFalse(events.any { it.uid.startsWith("subscription-5") })
        assertEquals(30, events.first { it.uid == "warranty-1" }.alertDaysBefore)
        assertEquals(60, events.first { it.uid == "document-3" }.alertDaysBefore)
    }

    @Test
    fun monthEndRenewalsStayAtMonthEnd() {
        val renewals = CalendarExport.events(records, today, text).filter { it.uid.startsWith("subscription-4") }.map { it.day.toString() }
        assertEquals(listOf("2026-10-31", "2026-11-30", "2026-12-31", "2027-01-31"), renewals.take(4))
        assertEquals(CalendarExport.RENEWAL_HORIZON_MONTHS.toInt(), renewals.size)
    }

    @Test
    fun writesAValidCalendarFile() {
        val ics = CalendarExport.make(records, today, Instant.EPOCH, text)
        val lines = ics.split("\r\n")
        assertEquals("BEGIN:VCALENDAR", lines.first())
        assertTrue(ics.endsWith("END:VCALENDAR\r\n"))
        assertEquals(lines.count { it == "BEGIN:VEVENT" }, lines.count { it == "END:VEVENT" })
        assertTrue("DTSTART;VALUE=DATE:20261012" in lines)
        assertTrue("DTSTAMP:19700101T000000Z" in lines)
        assertTrue("SUMMARY:Renews: Cloud ($9.99)" in lines)
        assertTrue(lines.all { it.toByteArray(Charsets.UTF_8).size <= 75 })
    }

    @Test
    fun escapesTextAndFoldsLongLines() {
        assertEquals("a\\, b\\; c\\\\d\\ne", CalendarExport.escape("a, b; c\\d\ne"))
        val line = "SUMMARY:" + "é".repeat(60)
        val folded = CalendarExport.fold(line)
        assertTrue(folded.split("\r\n ").all { it.toByteArray(Charsets.UTF_8).size <= 75 })
        assertEquals(line, folded.replace("\r\n ", ""))
    }

    @Test
    fun spreadsheetListsEveryRecordWithItsStatus() {
        val sheet = ExportRecords(
            products = listOf(
                Product(id = 1, name = "=Desk", brand = "Oak, Co", currency = "USD", warrantyExpires = LocalDate.parse("2026-10-12"), productUrl = "https://example.com/desk"),
            ),
            subscriptions = listOf(
                Subscription(id = 2, name = "Music", price = BigDecimal("119.88"), currency = "USD", cycleUnit = CycleUnit.YEARS, nextRenewal = LocalDate.parse("2027-01-01")),
            ),
            documents = listOf(Document(id = 3, title = "Licence", expiresOn = LocalDate.parse("2026-09-01"))),
            settings = Settings(defaultCurrency = "USD"),
        )
        val rows = RecordsCsv.make(sheet, today, text).split("\r\n")
        assertTrue(rows[0].startsWith("Type,Name,Due Date,Status"))
        assertEquals("Product,'=Desk,2026-10-12,SOON,\"Oak, Co\",,,,,,USD,,,,,,,https://example.com/desk,", rows[1])
        assertTrue(rows[2].startsWith("Subscription,Music,2027-01-01,OK,,,,,,119.88,USD,Every year,9.99,"))
        assertTrue(rows[3].startsWith("Document,Licence,2026-09-01,PAST,"))
    }
}
