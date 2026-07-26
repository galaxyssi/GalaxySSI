package com.signalasi.chat

import android.content.Context
import android.util.Base64
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

/**
 * Replaces inline rich-output payloads with durable app-private files.
 *
 * Connector replies can contain hundreds of kilobytes of Base64 data. Keeping
 * that data in transcripts and recovery stores multiplies parsing, encryption,
 * and allocation costs on every subsequent turn.
 */
object AgentRichContentMaterializer {
    private const val DIRECTORY_NAME = "agent-rich-output"
    private const val MAX_MATERIALIZED_BYTES = 4 * 1024 * 1024

    @Synchronized
    fun materialize(context: Context, raw: String): String {
        val normalized = AgentRichContentCodec.normalize(raw)
        if (normalized.isBlank()) return ""
        val blocks = AgentRichContentCodec.decode(normalized)
        if (blocks.none { it.dataB64.isNotBlank() }) return normalized

        val directory = File(context.applicationContext.filesDir, DIRECTORY_NAME)
        val materialized = blocks.map { block ->
            materializeBlock(context.applicationContext, directory, block) ?: block
        }
        return AgentRichContentCodec.encode(materialized)
    }

    private fun materializeBlock(
        context: Context,
        directory: File,
        block: AgentRichBlock
    ): AgentRichBlock? {
        if (block.dataB64.isBlank()) return block
        val bytes = runCatching { Base64.decode(block.dataB64, Base64.DEFAULT) }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() && it.size <= MAX_MATERIALIZED_BYTES }
            ?: return null
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
        val target = File(directory, "$digest.${extensionFor(block)}")
        if (!target.isFile || target.length() != bytes.size.toLong()) {
            if (!directory.exists() && !directory.mkdirs()) return null
            val temporary = File(directory, "$digest.tmp")
            val written = runCatching {
                temporary.outputStream().buffered().use { it.write(bytes) }
                if (target.exists()) target.delete()
                temporary.renameTo(target) || run {
                    target.outputStream().buffered().use { it.write(bytes) }
                    temporary.delete()
                    true
                }
            }.getOrDefault(false)
            if (!written) {
                temporary.delete()
                return null
            }
        }
        return block.copy(
            uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.files",
                target
            ).toString(),
            dataB64 = "",
            metadata = block.metadata + mapOf(
                "size_bytes" to bytes.size.toString(),
                "sha256" to digest,
                "storage" to "app_private"
            )
        )
    }

    private fun extensionFor(block: AgentRichBlock): String = when (block.mimeType.lowercase()) {
        "image/jpeg" -> "jpg"
        "image/png" -> "png"
        "image/gif" -> "gif"
        "image/webp" -> "webp"
        "image/heic", "image/heif" -> "heic"
        "audio/mpeg" -> "mp3"
        "audio/mp4", "audio/x-m4a" -> "m4a"
        "audio/wav", "audio/x-wav" -> "wav"
        "video/mp4" -> "mp4"
        "application/pdf" -> "pdf"
        "application/zip" -> "zip"
        "text/plain" -> "txt"
        else -> when (block.type) {
            AgentRichBlockType.IMAGE, AgentRichBlockType.GALLERY -> "img"
            AgentRichBlockType.AUDIO -> "audio"
            AgentRichBlockType.VIDEO -> "video"
            else -> "bin"
        }
    }
}
