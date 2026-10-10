package com.galaxyssi.chat

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/** Public copies are created only by the attachment Save action. */
internal object AgentPrivateAttachmentExport {
    fun canSave(context: Context, block: AgentRichBlock): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val uri = runCatching { Uri.parse(block.uri) }.getOrNull() ?: return false
        return when (uri.scheme) {
            "content" -> uri.authority == "${context.packageName}.local-attachments" ||
                uri.authority == "${context.packageName}.files"
            "file" -> runCatching {
                File(requireNotNull(uri.path)).canonicalFile.toPath()
                    .startsWith(context.filesDir.canonicalFile.toPath())
            }.getOrDefault(false)
            else -> false
        }
    }

    fun save(context: Context, block: AgentRichBlock): Result<String> = runCatching {
        require(canSave(context, block)) { "Private attachment is unavailable" }
        val source = Uri.parse(block.uri)
        val name = block.title.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[\\p{Cntrl}]+"), "").trim().take(160).ifBlank { "attachment" }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, block.mimeType.ifBlank { "application/octet-stream" })
            put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/GalaxySSI")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val target = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: error("Download destination could not be created")
        val buffer = ByteArray(64 * 1024)
        try {
            resolver.openInputStream(source)?.use { input ->
                resolver.openOutputStream(target, "w")?.use { output ->
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                } ?: error("Download destination could not be opened")
            } ?: error("Private attachment could not be opened")
            check(resolver.update(target, ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }, null, null) > 0) { "Download could not be published" }
        } catch (failure: Throwable) {
            resolver.delete(target, null, null)
            throw failure
        } finally {
            buffer.fill(0)
        }
        "${Environment.DIRECTORY_DOWNLOADS}/GalaxySSI/$name"
    }
}
