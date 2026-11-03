package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.util.Locale

internal data class ChatImagePreviewSource(val uri: Uri, val name: String, val mimeType: String, val sizeBytes: Long) {
    fun save(context: Context): Result<String> = runCatching {
        require(uri.scheme in setOf("content", "file") && mimeType.startsWith("image/")) {
            "Image source is unavailable"
        }
        AgentPrivateAttachmentExport.export(context, uri, name, mimeType).getOrThrow()
    }

    companion object {
        // Provider metadata and filesystem access run on the preview worker, never on the UI thread.
        fun resolve(context: Context, uri: Uri, title: String, mimeType: String, sizeBytes: Long): ChatImagePreviewSource {
            var name = title
            var size = sizeBytes
            if (uri.scheme == "content") runCatching {
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 && !cursor.isNull(it) }
                            ?.let { name = cursor.getString(it).orEmpty().ifBlank { name } }
                        cursor.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !cursor.isNull(it) }
                            ?.let { size = cursor.getLong(it) }
                    }
                }
            }
            if (uri.scheme == "file") uri.path?.let { path ->
                val file = File(path)
                if (name.isBlank()) name = file.name
                size = file.length()
            }
            val providerMime = if (uri.scheme == "content") runCatching {
                context.contentResolver.getType(uri).orEmpty()
            }.getOrDefault("") else ""
            val type = listOf(providerMime, mimeType).firstOrNull {
                it.startsWith("image/") && it != "image/*"
            }?.substringBefore(';') ?: MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase(Locale.ROOT)).orEmpty()
            val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(type).orEmpty()
            if (name.isBlank()) name = "image-${System.currentTimeMillis()}"
            if (extension.isNotBlank() && !name.contains('.')) name += ".$extension"
            return ChatImagePreviewSource(uri, name, type, size.coerceAtLeast(0))
        }

        fun formatLabel(mimeType: String): String = when (val type = mimeType.substringAfter("image/", "").uppercase(Locale.ROOT)) {
            "SVG+XML" -> "SVG"
            "X-MS-BMP" -> "BMP"
            "*" -> ""
            else -> type
        }
    }
}

internal class ChatImageSaveState {
    enum class Status { READY, SAVING, SAVED }
    var status = Status.READY
        private set
    fun begin(): Boolean {
        if (status != Status.READY) return false
        status = Status.SAVING
        return true
    }
    fun finish(success: Boolean) {
        if (status == Status.SAVING) status = if (success) Status.SAVED else Status.READY
    }
}
