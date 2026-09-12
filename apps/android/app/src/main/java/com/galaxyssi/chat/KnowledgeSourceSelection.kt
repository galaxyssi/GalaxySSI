package com.galaxyssi.chat

/** Opaque indexed predicate; caller text is never interpolated into SQL. */
internal class KnowledgeSourceSelection(storage: AgentKnowledgeDatabase, val reference: AgentKnowledgeSourceReference) {
    val where: String
    val value: String
    val group: String
    init {
        require(reference.source.isNotBlank() || reference.localItemId.isNotBlank()) { "Missing knowledge source identity" }
        require(reference.source.isBlank() || reference.localItemId.isBlank()) { "Ambiguous knowledge source identity" }
        if (reference.source.isBlank()) {
            where = "source_key='' AND item_key=?"
            value = storage.key("id", reference.localItemId)
            group = "i:$value"
        } else {
            where = "source_key=?"
            value = storage.key("source", reference.source)
            group = "s:$value"
        }
    }

    // This is a freshness token, not content authentication. Every returned body still passes AEAD and identity checks.
    fun revision(db: KnowledgeSqlite): String {
        val (epoch, head) = db.rawQuery("SELECT epoch,sequence FROM knowledge_source_revision_state WHERE id=1", null).use {
            check(it.moveToFirst()) { "Source revision state is missing" }
            it.getString(0) to it.getLong(1)
        }
        require(java.util.UUID.fromString(epoch).toString() == epoch && head >= 0) { "Invalid source revision state" }
        val sequence = db.rawQuery("SELECT sequence FROM knowledge_source_revisions WHERE group_key=?", arrayOf(group)).use {
            if (it.moveToFirst()) it.getLong(0).also { n -> check(n in 1..head) { "Invalid source revision" } } else 0L
        }
        val present = db.rawQuery("SELECT 1 FROM knowledge_items WHERE $where LIMIT 1", arrayOf(value)).use { it.moveToFirst() }
        check(present || sequence == 0L) { "Removed source still has a revision" }
        return "knowledge-source:v2:$epoch:$group:${if (present) sequence.toString() else "absent"}"
    }

    fun verify(item: AgentKnowledgeItem) {
        check(item.source == reference.source && (reference.localItemId.isBlank() || item.id == reference.localItemId)) {
            "Knowledge source membership mismatch"
        }
    }
}
