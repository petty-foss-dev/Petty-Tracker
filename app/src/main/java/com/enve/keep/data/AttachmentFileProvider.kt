package com.enve.keep.data

import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider

/** Reports an attachment's original name to receiving apps instead of its random storage name. */
class AttachmentFileProvider : FileProvider() {
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val cursor = super.query(uri, projection, selection, selectionArgs, sortOrder)
        val displayName = uri.getQueryParameter(DISPLAY_NAME_PARAM) ?: return cursor
        cursor.use {
            val result = MatrixCursor(it.columnNames, 1)
            if (it.moveToFirst()) {
                result.addRow(
                    it.columnNames.mapIndexed { index, column ->
                        when {
                            column == OpenableColumns.DISPLAY_NAME -> displayName
                            it.getType(index) == Cursor.FIELD_TYPE_INTEGER -> it.getLong(index)
                            it.getType(index) == Cursor.FIELD_TYPE_NULL -> null
                            else -> it.getString(index)
                        }
                    }
                )
            }
            return result
        }
    }

    companion object {
        const val DISPLAY_NAME_PARAM = "displayName"
    }
}
