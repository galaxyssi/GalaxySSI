package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import android.util.Base64
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
    private const val DIRECTORY_NAME = "agent-rich-output-v2"
    private const val MAX_MATERIALIZED_BYTES = 4 * 1024 * 1024

    @Synchronized
    fun materialize(context: Context, raw: String, assistantText: String = "", strictHtml: Boolean = false): String {
        val declared = if (raw.isBlank() && (assistantText.contains("```galaxyssi-rich", true) || assistantText.contains("```galaxyssi-html", true))) {
            AgentRichContentCodec.fromText(assistantText).takeIf { blocks -> blocks.any { it.type == AgentRichBlockType.HTML } }
                ?.let(AgentRichContentCodec::encode).orEmpty()
        } else raw
        val normalized = AgentRichContentCodec.normalize(declared)
        if (normalized.isBlank()) return ""
        val blocks = AgentRichContentCodec.decode(normalized)
        if (blocks.none {
                it.dataB64.isNotBlank() ||
                    it.type == AgentRichBlockType.HTML ||
                    Uri.parse(it.uri).scheme == "galaxyssi-artifact"
            }
        ) return normalized

        val directory = File(context.applicationContext.filesDir, DIRECTORY_NAME)
        val materialized = blocks.map { block ->
            val resolved = AgentDesktopArtifactStore.resolveBlock(context.applicationContext, block)
            materializeBlock(context.applicationContext, directory, resolved, strictHtml) ?: resolved
        }
        return AgentRichContentCodec.encode(materialized)
    }

    private fun materializeBlock(
        context: Context,
        directory: File,
        block: AgentRichBlock,
        strictHtml: Boolean
    ): AgentRichBlock? {
        val html = block.type == AgentRichBlockType.HTML
        if (block.dataB64.isBlank() && !html) return block
        val bytes = runCatching { if (html) block.text.toByteArray(Charsets.UTF_8)
            else Base64.decode(block.dataB64, Base64.DEFAULT) }
            .getOrNull()
            ?.takeIf { it.isNotEmpty() && it.size <= MAX_MATERIALIZED_BYTES }
            ?: return null
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
        val target = File(directory, "$digest.sasie")
        try {
            val alreadyStored = runCatching {
                AttachmentLocalStore.metadata(target).plaintextLength == bytes.size.toLong()
            }.getOrDefault(false)
            if (!alreadyStored) {
                if (!directory.exists() && !directory.mkdirs()) {
                    check(!html || !strictHtml) { "Private HTML attachment directory could not be created" }
                    return null
                }
                val write = runCatching { AttachmentLocalStore.storeBytes(bytes, target) }
                if (html && strictHtml) write.getOrThrow()
                if (write.isFailure) return null
            }
            val displayName = if (html) block.title.ifBlank { "animation" }.let {
                if (it.endsWith(".html", true) || it.endsWith(".htm", true)) it else "$it.html"
            } else block.title.ifBlank { "$digest.${extensionFor(block)}" }
            val mime = if (html) "text/html" else block.mimeType
            return block.copy(
                type = if (html) AgentRichBlockType.FILE else block.type,
                title = displayName,
                text = if (html) "" else block.text,
                mimeType = mime,
                uri = LocalAttachmentUris.forFile(
                    context,
                    target,
                    displayName,
                    mime
                ).toString(),
                dataB64 = "",
                metadata = block.metadata + mapOf(
                    "size_bytes" to bytes.size.toString(),
                    "sha256" to digest,
                    "storage" to "app_private"
                )
            )
        } finally {
            bytes.fill(0)
        }
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
        "text/html" -> "html"
        else -> when (block.type) {
            AgentRichBlockType.IMAGE, AgentRichBlockType.GALLERY -> "img"
            AgentRichBlockType.AUDIO -> "audio"
            AgentRichBlockType.VIDEO -> "video"
            else -> "bin"
        }
    }
}
