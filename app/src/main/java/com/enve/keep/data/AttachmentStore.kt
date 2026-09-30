package com.enve.keep.data

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.exifinterface.media.ExifInterface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/** Imported files live under filesDir/attachments with random names; only granted URIs leave the app. */
class AttachmentStore(private val context: Context) {
    val directory: File get() = File(context.filesDir, DIRECTORY).apply { mkdirs() }

    fun file(fileName: String) = File(directory, fileName)

    fun uriFor(fileName: String): Uri =
        FileProvider.getUriForFile(context, "${context.packageName}.files", file(fileName))

    fun uriFor(attachment: Attachment): Uri = uriFor(attachment.fileName).buildUpon()
        .appendQueryParameter(AttachmentFileProvider.DISPLAY_NAME_PARAM, attachment.displayName)
        .build()

    suspend fun import(uri: Uri, ownerType: OwnerType): Attachment = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val mimeType = resolver.getType(uri) ?: "application/octet-stream"
        val displayName = resolver.displayName(uri) ?: "file"
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
            ?: displayName.substringAfterLast('.', "").takeIf { it.matches(EXTENSION) }
        val target = file(newFileName(extension))
        try {
            resolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "Unable to open $uri" }
                target.outputStream().use { input.copyTo(it) }
            }
        } catch (e: Exception) {
            target.delete()
            throw e
        }
        Attachment(
            ownerType = ownerType,
            ownerId = 0,
            displayName = displayName,
            mimeType = mimeType,
            fileName = target.name,
            sizeBytes = target.length(),
        )
    }

    /** Reserves a file for the camera to write into. */
    fun newPhotoFile(): File = file(newFileName("jpg"))

    fun photoAttachment(file: File, ownerType: OwnerType, displayName: String) = Attachment(
        ownerType = ownerType,
        ownerId = 0,
        displayName = displayName,
        mimeType = "image/jpeg",
        fileName = file.name,
        sizeBytes = file.length(),
    )

    fun delete(fileNames: Collection<String>) {
        fileNames.forEach { file(it).delete() }
    }

    /**
     * Removes files left behind by abandoned edits. Recent files are kept because an editor restored
     * after process death may still reference them.
     */
    suspend fun deleteOrphans(referenced: Set<String>) = withContext(Dispatchers.IO) {
        val cutoff = System.currentTimeMillis() - ORPHAN_AGE_MILLIS
        directory.listFiles()
            ?.filter { it.name !in referenced && it.lastModified() < cutoff }
            ?.forEach { it.deleteRecursively() }
    }

    suspend fun thumbnail(fileName: String, maxSize: Int): Bitmap? = withContext(Dispatchers.IO) {
        val path = file(fileName).path
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@withContext null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxSize && bounds.outHeight / (sample * 2) >= maxSize) sample *= 2
        val bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return@withContext null
        val degrees = runCatching { ExifInterface(path).rotationDegrees }.getOrDefault(0)
        if (degrees == 0) bitmap
        else Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees.toFloat()) }, true)
    }

    private fun newFileName(extension: String?) =
        UUID.randomUUID().toString() + (extension?.let { ".${it.lowercase()}" } ?: "")

    private fun ContentResolver.displayName(uri: Uri): String? =
        query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }

    companion object {
        const val DIRECTORY = "attachments"
        private const val ORPHAN_AGE_MILLIS = 24L * 60 * 60 * 1000
        private val EXTENSION = Regex("[A-Za-z0-9]{1,10}")
    }
}
