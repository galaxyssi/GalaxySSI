package com.galaxyssi.chat

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.FileNotFoundException

/** Read-only grants expose authenticated random-access bytes, never a decrypted cache file. */
class HealthOriginalContentProvider : ContentProvider() {
    override fun onCreate() = true
    private fun id(uri: Uri): String {
        val value = uri.pathSegments.singleOrNull() ?: throw FileNotFoundException("Invalid health original")
        if (runCatching { java.util.UUID.fromString(value).toString() == value }.getOrDefault(false)) return value
        throw FileNotFoundException("Invalid health original")
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Health originals are read-only")
        return HealthOriginalStore(requireNotNull(context)).use { store ->
            val original = store.original(id(uri)) ?: throw FileNotFoundException("Health original is missing")
            store.descriptor(original)
        }
    }
    override fun getType(uri: Uri): String? = HealthOriginalStore(requireNotNull(context)).use { it.original(id(uri))?.mime }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val columns = projection?.filter { it in listOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE) }
            ?: listOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns.toTypedArray()).apply {
            HealthOriginalStore(requireNotNull(context)).use { store ->
                store.original(id(uri))?.let { original -> addRow(columns.map { if (it == OpenableColumns.DISPLAY_NAME) original.name else original.size }) }
            }
        }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = throw UnsupportedOperationException()
    companion object {
        fun uri(context: Context, id: String): Uri = Uri.parse("content://${context.packageName}.health-originals/$id")
    }
}
