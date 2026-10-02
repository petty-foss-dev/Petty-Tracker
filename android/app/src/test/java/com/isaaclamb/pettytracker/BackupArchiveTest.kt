package com.isaaclamb.pettytracker

import com.isaaclamb.pettytracker.data.Attachment
import com.isaaclamb.pettytracker.data.AttachmentLabel
import com.isaaclamb.pettytracker.data.RecordLink
import com.isaaclamb.pettytracker.data.RecordType
import com.isaaclamb.pettytracker.data.CycleUnit
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.OwnerType
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.data.Settings
import com.isaaclamb.pettytracker.data.Subscription
import com.isaaclamb.pettytracker.data.backup.BackupArchive
import com.isaaclamb.pettytracker.data.backup.BackupManifest
import com.isaaclamb.pettytracker.data.backup.InvalidBackupException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.math.BigDecimal
import java.time.LocalDate
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class BackupArchiveTest {
    @get:Rule val temp = TemporaryFolder()

    private val manifest = BackupManifest(
        exportedAt = "2026-09-29T10:00:00Z",
        products = listOf(
            Product(
                id = 3,
                name = "Espresso machine",
                brand = "Brewco",
                serialNumber = "SN-42",
                purchaseDate = LocalDate.parse("2025-03-01"),
                price = BigDecimal("499.99"),
                currency = "EUR",
                warrantyExpires = LocalDate.parse("2027-03-01"),
            )
        ),
        subscriptions = listOf(
            Subscription(
                id = 7,
                name = "Music",
                price = BigDecimal("10.99"),
                currency = "USD",
                cycleUnit = CycleUnit.MONTHS,
                nextRenewal = LocalDate.parse("2026-10-31"),
                anchorDate = LocalDate.parse("2026-01-31"),
            )
        ),
        documents = listOf(Document(id = 2, title = "Passport", expiresOn = LocalDate.parse("2031-05-05"))),
        attachments = listOf(
            Attachment(5, OwnerType.PRODUCT, 3, "receipt.pdf", "application/pdf", "0f1e2d3c.pdf", 4),
            Attachment(6, OwnerType.DOCUMENT, 2, "scan.jpg", "image/jpeg", "a1b2c3.jpg", 3),
        ),
        settings = Settings(documentLeadDays = 90, defaultCurrency = "EUR"),
    )

    private fun zip(vararg entries: Pair<String, ByteArray>): ByteArray {
        val bytes = ByteArrayOutputStream()
        ZipOutputStream(bytes).use { zip ->
            entries.forEach { (name, data) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(data)
                zip.closeEntry()
            }
        }
        return bytes.toByteArray()
    }

    private fun manifestJson(value: BackupManifest = manifest) =
        BackupArchive.json.encodeToString(BackupManifest.serializer(), value).toByteArray()

    @Test
    fun roundTripsRecordsAndAttachments() {
        val source = temp.newFolder("source")
        File(source, "0f1e2d3c.pdf").writeBytes(byteArrayOf(1, 2, 3, 4))
        File(source, "a1b2c3.jpg").writeBytes(byteArrayOf(9, 8, 7))
        val archive = ByteArrayOutputStream().also { BackupArchive.write(manifest, source, it) }.toByteArray()

        val staging = temp.newFolder("staging")
        val restored = BackupArchive.read(ByteArrayInputStream(archive), staging)

        assertEquals(manifest, restored)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), File(staging, "attachments/0f1e2d3c.pdf").readBytes())
        assertArrayEquals(byteArrayOf(9, 8, 7), File(staging, "attachments/a1b2c3.jpg").readBytes())
    }

    @Test
    fun roundTripsLinksLabelsAndProductPages() {
        val source = temp.newFolder("source")
        File(source, "0f1e2d3c.pdf").writeBytes(byteArrayOf(1, 2, 3, 4))
        File(source, "a1b2c3.jpg").writeBytes(byteArrayOf(9, 8, 7))
        val linked = manifest.copy(
            products = manifest.products.map { it.copy(productUrl = "https://example.com/espresso") },
            attachments = manifest.attachments.map { if (it.id == 5L) it.copy(label = AttachmentLabel.INSTRUCTIONS) else it },
            links = listOf(RecordLink(id = 1, fromType = RecordType.PRODUCT, fromId = 3, toType = RecordType.DOCUMENT, toId = 2, note = "Insured")),
        )
        val archive = ByteArrayOutputStream().also { BackupArchive.write(linked, source, it) }.toByteArray()

        assertEquals(linked, BackupArchive.read(ByteArrayInputStream(archive), temp.newFolder("staging")))
    }

    @Test
    fun rejectsLinksToMissingRecords() {
        val dangling = manifest.copy(
            attachments = emptyList(),
            links = listOf(RecordLink(id = 1, fromType = RecordType.PRODUCT, fromId = 3, toType = RecordType.SUBSCRIPTION, toId = 99)),
        )
        assertThrows(InvalidBackupException::class.java) {
            BackupArchive.read(ByteArrayInputStream(zip(BackupArchive.MANIFEST to manifestJson(dangling))), temp.newFolder())
        }
    }

    @Test
    fun readsFilesAndProductsSavedBeforeLabelsAndPages() {
        val json = """{"format":"petty-tracker-backup","exportedAt":"x","products":[{"id":3,"name":"Desk","currency":"USD"}],"attachments":[{"id":5,"ownerType":"PRODUCT","ownerId":3,"displayName":"a","mimeType":"image/jpeg","fileName":"a.jpg","sizeBytes":1}]}"""
        val restored = BackupArchive.read(
            ByteArrayInputStream(zip(BackupArchive.MANIFEST to json.toByteArray(), "attachments/a.jpg" to byteArrayOf(1))),
            temp.newFolder(),
        )
        assertEquals(AttachmentLabel.OTHER, restored.attachments.single().label)
        assertEquals("", restored.products.single().productUrl)
        assertEquals(emptyList<RecordLink>(), restored.links)
    }

    @Test
    fun readsBackupFromBeforeRename() {
        val legacy = manifest.copy(format = BackupManifest.LEGACY_FORMAT, attachments = emptyList())
        val archive = zip(BackupArchive.MANIFEST to manifestJson(legacy))
        assertEquals(legacy, BackupArchive.read(ByteArrayInputStream(archive), temp.newFolder()))
    }

    @Test
    fun rejectsPathTraversal() {
        val hostile = listOf(
            "../evil.txt",
            "attachments/../../evil.txt",
            "attachments/..",
            "attachments/nested/file.jpg",
            "/attachments/abs.jpg",
            "attachments\\..\\evil.txt",
        )
        hostile.forEach { name ->
            val staging = temp.newFolder()
            val archive = zip(BackupArchive.MANIFEST to manifestJson(), name to byteArrayOf(1))
            assertThrows(name, InvalidBackupException::class.java) {
                BackupArchive.read(ByteArrayInputStream(archive), staging)
            }
            assertFalse(File(staging.parentFile, "evil.txt").exists())
        }
    }

    @Test
    fun rejectsMissingAttachment() {
        val archive = zip(BackupArchive.MANIFEST to manifestJson(), "attachments/0f1e2d3c.pdf" to byteArrayOf(1))
        assertThrows(InvalidBackupException::class.java) {
            BackupArchive.read(ByteArrayInputStream(archive), temp.newFolder())
        }
    }

    @Test
    fun rejectsForeignArchive() {
        val archive = zip(BackupArchive.MANIFEST to """{"format":"other","exportedAt":"x"}""".toByteArray())
        assertThrows(InvalidBackupException::class.java) {
            BackupArchive.read(ByteArrayInputStream(archive), temp.newFolder())
        }
        assertThrows(InvalidBackupException::class.java) {
            BackupArchive.read(ByteArrayInputStream(zip("notes.txt" to byteArrayOf(1))), temp.newFolder())
        }
    }

    @Test
    fun dropsUnreferencedFiles() {
        val empty = manifest.copy(attachments = emptyList())
        val staging = temp.newFolder()
        val archive = zip(BackupArchive.MANIFEST to manifestJson(empty), "attachments/stray.bin" to byteArrayOf(1))
        BackupArchive.read(ByteArrayInputStream(archive), staging)
        assertTrue(File(staging, "attachments").list()!!.isEmpty())
    }
}
