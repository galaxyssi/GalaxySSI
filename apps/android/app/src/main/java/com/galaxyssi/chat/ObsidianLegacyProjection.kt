package com.galaxyssi.chat

import android.content.Context
import androidx.documentfile.provider.DocumentFile
import java.security.MessageDigest
import org.json.JSONTokener

internal object ObsidianKnowledgeIdentity {
    fun sourceKey(reference: AgentKnowledgeSourceReference): String {
        require(reference.source.isNotBlank() || reference.localItemId.isNotBlank())
        require(reference.source.isBlank() || reference.localItemId.isBlank())
        val raw = if (reference.source.isBlank()) "item\u0000${reference.localItemId}" else "source\u0000${reference.source}"
        val bytes = raw.toByteArray(Charsets.UTF_8)
        val digest = try { MessageDigest.getInstance("SHA-256").digest(bytes) } finally { bytes.fill(0) }
        return "knowledge:v2:" + digest.joinToString("") { "%02x".format(it) }
    }
    fun legacyKey(reference: AgentKnowledgeSourceReference) =
        "knowledge:${GlobalAgentText.stableKey(reference.source.ifBlank { reference.localItemId })}"
}

/** The legacy semantic key aliases all URLs. Never adopt its file without exact source evidence. */
internal object ObsidianLegacyProjection {
    fun findIndex(context: Context, root: DocumentFile, store: ObsidianAndroidStateStore,
        spec: ObsidianProjectionSpec): ObsidianProjectionIndexEntry? {
        val reference = spec.knowledgeReference ?: return null
        val key = ObsidianKnowledgeIdentity.legacyKey(reference)
        val entry = store.index(key) ?: return null
        val segments = entry.relativePath.split('/')
        if (segments.any { it.isBlank() || it == "." || it == ".." }) return null
        var document = root
        for (segment in segments) document = document.findFile(segment) ?: return null
        val bytes = ByteArray(8192)
        try {
            val header = context.contentResolver.openInputStream(document.uri)?.use { input ->
                var size = 0
                while (size < bytes.size) {
                    val count = input.read(bytes, size, bytes.size - size)
                    if (count <= 0) break
                    size += count
                }
                String(bytes, 0, size, Charsets.UTF_8)
            } ?: return null
            if (!header.startsWith("---\n")) return null
            val end = header.indexOf("\n---\n", 4)
            if (end < 0) return null
            val fields = header.substring(4, end).lineSequence().mapNotNull { line ->
                val colon = line.indexOf(':')
                if (colon < 0) null else line.substring(0, colon) to line.substring(colon + 1).trim()
            }.groupBy({ it.first }, { it.second })
            fun quoted(name: String): String? = fields[name]?.singleOrNull()?.let { value ->
                if (!value.startsWith('"') || !value.endsWith('"')) null
                else runCatching { JSONTokener(value).nextValue() as? String }.getOrNull()
            }
            if (fields["managed_by"] != listOf("galaxyssi") || quoted("galaxyssi_id") != key ||
                quoted("source") != reference.source.ifBlank { reference.localItemId }) return null
            if (entry.userModified) return entry
            // The bounded background edit scan may not have reached this legacy note yet.
            val digest = MessageDigest.getInstance("SHA-256")
            context.contentResolver.openInputStream(document.uri)?.use { input ->
                while (true) {
                    val count = input.read(bytes)
                    if (count < 0) break
                    if (count > 0) digest.update(bytes, 0, count)
                }
            } ?: return null
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            return entry.copy(userModified = actual != entry.generatedHash)
        } finally { bytes.fill(0) }
    }
}
