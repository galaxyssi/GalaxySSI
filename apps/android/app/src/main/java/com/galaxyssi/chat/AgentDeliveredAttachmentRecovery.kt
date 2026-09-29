package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import java.security.MessageDigest

/** Restore only verified Desktop outputs referenced in this conversation. */
internal object AgentDeliveredAttachmentRecovery {
    fun restore(context: Context, conversationId: String, attachmentIds: Collection<String>): List<AgentInputAttachment> {
        if (conversationId.isBlank()) return emptyList()
        val missing = attachmentIds.filter { it.isNotBlank() && it.length <= 120 }.distinct().take(10).toMutableSet()
        if (missing.isEmpty()) return emptyList()
        val store = AgentTranscriptStore(context)
        val restored = mutableListOf<AgentInputAttachment>()
        var before: Long? = null
        var totalBytes = 0L
        repeat(32) {
            val page = store.page(conversationId, beforeSequenceExclusive = before, pageSize = 100)
            for (entry in page.entries) {
                if (entry.role != AgentTranscriptRole.ASSISTANT || entry.conversationId != conversationId) continue
                for (block in AgentRichContentCodec.decode(entry.richOutputJson)) {
                    if (block.id !in missing || block.type !in TYPES) continue
                    val source = block.metadata["artifact_source_uri"].orEmpty().ifBlank { block.uri }
                    if (Uri.parse(source).scheme != "galaxyssi-artifact") continue
                    val attachment = runCatching {
                        if (AgentDesktopArtifactStore.localFile(context, block) == null) return@runCatching null
                        val resolved = AgentDesktopArtifactStore.resolveBlock(context, block)
                        val uri = Uri.parse(resolved.uri)
                        if (uri.scheme != "content") return@runCatching null
                        val expectedSize = resolved.metadata["size_bytes"]?.toLongOrNull() ?: return@runCatching null
                        if (expectedSize !in 1..64L * 1024 * 1024 || totalBytes + expectedSize > 128L * 1024 * 1024) {
                            return@runCatching null
                        }
                        totalBytes += expectedSize
                        val digest = MessageDigest.getInstance("SHA-256")
                        var size = 0L
                        context.contentResolver.openInputStream(uri)?.use { input ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                size += count
                                check(size <= expectedSize)
                                digest.update(buffer, 0, count)
                            }
                        } ?: return@runCatching null
                        val sha = digest.digest().joinToString("") { "%02x".format(it) }
                        if (size != expectedSize || sha != resolved.metadata["sha256"]) return@runCatching null
                        AgentInputAttachment(id = block.id, uri = uri,
                            displayName = uri.getQueryParameter("name").orEmpty().ifBlank { block.title },
                            mimeType = resolved.mimeType, sizeBytes = size)
                    }.getOrNull() ?: continue
                    restored += attachment
                    missing.remove(block.id)
                    if (missing.isEmpty()) return restored
                }
            }
            val next = page.nextBeforeSequence
            if (!page.hasMore || next == null || next == before) return restored
            before = next
        }
        return restored
    }

    private val TYPES = setOf(AgentRichBlockType.FILE, AgentRichBlockType.IMAGE,
        AgentRichBlockType.AUDIO, AgentRichBlockType.VIDEO)
}
