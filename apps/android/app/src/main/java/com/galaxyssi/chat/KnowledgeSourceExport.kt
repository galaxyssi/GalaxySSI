package com.galaxyssi.chat

import java.security.MessageDigest

/** Lazy, revision-checked source read for an explicitly configured local projection. */
internal class KnowledgeSourceExport(private val storage: AgentKnowledgeDatabase,
    private val reference: AgentKnowledgeSourceReference) {
    val revision: String = storage.access(::digest)

    fun items(): List<AgentKnowledgeItem> = storage.access { db ->
        check(digest(db) == revision) { "Knowledge source changed before projection; retry synchronization" }
        val (where, value) = predicate()
        db.rawQuery("SELECT item_key FROM knowledge_items WHERE $where ORDER BY item_key", arrayOf(value)).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val item = requireNotNull(storage.read(db, cursor.getString(0)))
                    check(item.source == reference.source) { "Knowledge source membership mismatch" }
                    add(item)
                }
            }.sortedWith(compareBy(AgentKnowledgeItem::chunkIndex, AgentKnowledgeItem::id))
        }
    }

    private fun digest(db: KnowledgeSqlite): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val (where, value) = predicate()
        // Ciphertext binds the complete authenticated body hash, identity and policies.
        // Length framing avoids ambiguous concatenation; replay does not rewrite headers.
        db.rawQuery("SELECT item_key,header FROM knowledge_items WHERE $where ORDER BY item_key", arrayOf(value)).use { cursor ->
            while (cursor.moveToNext()) repeat(2) { index ->
                val bytes = cursor.getString(index).toByteArray(Charsets.UTF_8)
                try {
                    digest.update(java.nio.ByteBuffer.allocate(4).putInt(bytes.size).array())
                    digest.update(bytes)
                } finally { bytes.fill(0) }
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun predicate(): Pair<String, String> {
        require(reference.source.isNotBlank() || reference.localItemId.isNotBlank()) { "Missing knowledge source identity" }
        require(reference.source.isBlank() || reference.localItemId.isBlank()) { "Ambiguous knowledge source identity" }
        return if (reference.source.isBlank()) "source_key='' AND item_key=?" to storage.key("id", reference.localItemId)
        else "source_key=?" to storage.key("source", reference.source)
    }
}
