package com.galaxyssi.chat

internal class KnowledgeSourceReplacementChanged : IllegalStateException(
    "Knowledge source changed during replacement preparation; retry with the current source")

/** The staging owner must remain open until publication and post-commit observation finish. */
internal class KnowledgePreparedSourceReplacement(private val storage: AgentKnowledgeDatabase,
    private val staging: KnowledgeBackupStaging, private val selection: KnowledgeSourceSelection,
    private val revision: String, private val policy: KnowledgeSourcePolicy?) {
    private var used = false

    fun commit(): KnowledgeSourceMutation {
        check(!used) { "Prepared knowledge replacement has already been consumed" }
        used = true
        return storage.transaction { db ->
            if (selection.revision(db) != revision) throw KnowledgeSourceReplacementChanged()
            val change = KnowledgeSourceMutation(storage, staging, policy)
            // Other sources can claim incoming IDs after preparation; check inside the writer.
            for (item in staging.incoming()) {
                check(!Thread.currentThread().isInterrupted)
                storage.readSourceMetadata(db, storage.key("id", item.id))?.let {
                    require(it.source == selection.reference.source) { "Knowledge ID belongs to another source" }
                }
            }
            for ((before, incoming) in staging.changes(includeUnchanged = true)) {
                check(!Thread.currentThread().isInterrupted)
                val next = incoming?.let(change::normalize)
                if (before == next) continue
                if (next == null) db.delete("knowledge_items", "item_key=?", arrayOf(storage.key("id", requireNotNull(before).id)))
                else storage.write(db, next)
            }
            change
        }
    }
}
