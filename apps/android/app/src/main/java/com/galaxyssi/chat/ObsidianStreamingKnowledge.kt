package com.galaxyssi.chat

import java.security.DigestOutputStream
import java.security.MessageDigest

internal object ObsidianStreamingKnowledge {
    fun prepare(export: KnowledgeSourceExport, key: String, type: String, source: String): ObsidianPreparedContent {
        val scratch = export.scratch()
        try {
            val body = scratch.create()
            val digest = MessageDigest.getInstance("SHA-256")
            var count = 0L
            var title = ""
            var updated = Long.MIN_VALUE
            val tags = LinkedHashSet<String>()
            var previousTail = ""
            var redacted = false
            DigestOutputStream(scratch.output(body), digest).writer(Charsets.UTF_8).buffered(8192).use { writer ->
                export.forEachOrdered(scratch) { item ->
                    if (ObsidianProjectionPrivacyPolicy.safeKnowledge(item.content)) {
                        val part = item.content.trim()
                        if (count == 0L) title = item.title.replace(Regex("\\s+\\[\\d+/\\d+]$"), "").trim().ifBlank { "Knowledge" }
                        else {
                            // Trimmed parts have a fixed separator. A cross-part sensitive match
                            // can only span a trailing keyword and the next non-space character.
                            redacted = redacted || !ObsidianProjectionPrivacyPolicy.safeKnowledge(previousTail + "\n\n" + part.take(64))
                            writer.write("\n\n")
                        }
                        writer.write(part)
                        previousTail = part.takeLast(64)
                        count = Math.addExact(count, 1)
                        updated = maxOf(updated, item.updatedAtMillis)
                        for (tag in item.tags) { if (tags.size == 16) break; tags.add(tag) }
                    }
                }
            }
            if (count == 0L || redacted) {
                val text = if (count == 0L) "" else ObsidianAndroidBridge.note(key, type, title, source, updated,
                    tags.toList(), "[Sensitive content omitted by GalaxySSI]")
                scratch.close()
                return ObsidianStringContent(text)
            }
            val header = ObsidianAndroidBridge.noteHeader(key, type, title, source, updated, tags.toList(),
                ObsidianContentHash.hex(digest.digest()))
            return ObsidianStagedContent(scratch, body, header)
        } catch (failure: Throwable) {
            try { scratch.close() } catch (cleanup: Throwable) { failure.addSuppressed(cleanup) }
            throw failure
        }
    }
}
