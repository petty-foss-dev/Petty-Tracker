package com.isaaclamb.pettytracker.data.backup

import com.isaaclamb.pettytracker.data.Attachment
import com.isaaclamb.pettytracker.data.Document
import com.isaaclamb.pettytracker.data.OwnerType
import com.isaaclamb.pettytracker.data.Product
import com.isaaclamb.pettytracker.data.Settings
import com.isaaclamb.pettytracker.data.Subscription
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipException
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

@Serializable
data class BackupManifest(
    val format: String = FORMAT,
    val version: Int = VERSION,
    val exportedAt: String,
    val products: List<Product> = emptyList(),
    val subscriptions: List<Subscription> = emptyList(),
    val documents: List<Document> = emptyList(),
    val attachments: List<Attachment> = emptyList(),
    val settings: Settings? = null,
) {
    companion object {
        const val FORMAT = "petty-tracker-backup"

        // Written before the app was renamed from Enve Keep.
        const val LEGACY_FORMAT = "enve-keep-backup"
        const val VERSION = 1
    }
}

class InvalidBackupException(message: String) : Exception(message)

/** Pure zip read/write for backups, kept free of Android types so it can be unit tested. */
object BackupArchive {
    const val MANIFEST = "backup.json"
    private const val ATTACHMENT_PREFIX = "attachments/"
    private const val MAX_MANIFEST_BYTES = 64L * 1024 * 1024
    private const val MAX_TOTAL_BYTES = 4L * 1024 * 1024 * 1024
    private val SAFE_FILE_NAME = Regex("[A-Za-z0-9][A-Za-z0-9_-]{0,127}(\\.[A-Za-z0-9]{1,10})?")

    val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun isSafeFileName(name: String) = SAFE_FILE_NAME.matches(name)

    fun write(manifest: BackupManifest, attachmentsDir: File, output: OutputStream) {
        ZipOutputStream(output.buffered()).use { zip ->
            zip.putNextEntry(ZipEntry(MANIFEST))
            zip.write(json.encodeToString(BackupManifest.serializer(), manifest).toByteArray())
            zip.closeEntry()
            manifest.attachments.forEach { attachment ->
                zip.putNextEntry(ZipEntry(ATTACHMENT_PREFIX + attachment.fileName))
                File(attachmentsDir, attachment.fileName).inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
    }

    /**
     * Extracts attachments into [stagingDir]/attachments and returns the validated manifest.
     * Only `backup.json` and flat `attachments/<safe name>` entries are accepted, so an archive
     * can never write outside the staging directory.
     */
    fun read(input: InputStream, stagingDir: File): BackupManifest {
        val attachmentsDir = File(stagingDir, "attachments").apply { mkdirs() }
        val root = attachmentsDir.canonicalFile
        val extracted = mutableSetOf<String>()
        var manifestBytes: ByteArray? = null
        var total = 0L

        // Android 14+ rejects traversal entry names itself with a ZipException.
        try {
            ZipInputStream(input.buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val name = entry.name
                    when {
                        entry.isDirectory && name == ATTACHMENT_PREFIX -> Unit
                        name == MANIFEST -> {
                            if (manifestBytes != null) throw InvalidBackupException("Duplicate manifest")
                            val bytes = zip.readLimited(MAX_MANIFEST_BYTES)
                            manifestBytes = bytes
                            total += bytes.size
                        }
                        name.startsWith(ATTACHMENT_PREFIX) -> {
                            val fileName = name.removePrefix(ATTACHMENT_PREFIX)
                            if (!isSafeFileName(fileName) || !extracted.add(fileName)) {
                                throw InvalidBackupException("Unexpected entry: $name")
                            }
                            val target = File(attachmentsDir, fileName).canonicalFile
                            if (target.parentFile != root) throw InvalidBackupException("Unexpected entry: $name")
                            target.outputStream().use { out ->
                                total += zip.copyLimited(out, MAX_TOTAL_BYTES - total)
                            }
                        }
                        else -> throw InvalidBackupException("Unexpected entry: $name")
                    }
                }
            }
        } catch (e: ZipException) {
            throw InvalidBackupException("Corrupt archive: ${e.message}")
        }

        val bytes = manifestBytes ?: throw InvalidBackupException("Missing $MANIFEST")
        val manifest = runCatching {
            json.decodeFromString(BackupManifest.serializer(), bytes.decodeToString())
        }.getOrElse { throw InvalidBackupException("Unreadable manifest: ${it.message}") }
        validate(manifest, extracted)
        val referenced = manifest.attachments.map { it.fileName }.toSet()
        (extracted - referenced).forEach { File(attachmentsDir, it).delete() }
        return manifest
    }

    private fun validate(manifest: BackupManifest, files: Set<String>) {
        if (manifest.format !in setOf(BackupManifest.FORMAT, BackupManifest.LEGACY_FORMAT)) {
            throw InvalidBackupException("Not a petty: Tracker backup")
        }
        if (manifest.version > BackupManifest.VERSION) {
            throw InvalidBackupException("Backup was made by a newer version of petty: Tracker")
        }
        fun requireUnique(ids: List<Long>, label: String) {
            if (ids.toSet().size != ids.size || ids.any { it <= 0 }) throw InvalidBackupException("Invalid $label ids")
        }
        requireUnique(manifest.products.map { it.id }, "product")
        requireUnique(manifest.subscriptions.map { it.id }, "subscription")
        requireUnique(manifest.documents.map { it.id }, "document")
        requireUnique(manifest.attachments.map { it.id }, "attachment")
        val productIds = manifest.products.map { it.id }.toSet()
        val documentIds = manifest.documents.map { it.id }.toSet()
        manifest.attachments.forEach { attachment ->
            val ownerExists = when (attachment.ownerType) {
                OwnerType.PRODUCT -> attachment.ownerId in productIds
                OwnerType.DOCUMENT -> attachment.ownerId in documentIds
            }
            if (!ownerExists || attachment.fileName !in files) {
                throw InvalidBackupException("Attachment ${attachment.displayName} is missing")
            }
        }
        if (manifest.attachments.map { it.fileName }.toSet().size != manifest.attachments.size) {
            throw InvalidBackupException("Duplicate attachment files")
        }
        if (manifest.subscriptions.any { it.cycleCount < 1 }) throw InvalidBackupException("Invalid billing cycle")
    }

    private fun InputStream.readLimited(limit: Long): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        copyLimited(out, limit)
        return out.toByteArray()
    }

    private fun InputStream.copyLimited(out: OutputStream, limit: Long): Long {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var copied = 0L
        while (true) {
            val read = read(buffer)
            if (read < 0) return copied
            copied += read
            if (copied > limit) throw InvalidBackupException("Backup is too large")
            out.write(buffer, 0, read)
        }
    }
}
