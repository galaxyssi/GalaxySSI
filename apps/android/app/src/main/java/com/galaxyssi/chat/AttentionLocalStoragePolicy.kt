package com.galaxyssi.chat

import org.json.JSONObject

/** Only public discovery data opts out of at-rest encryption; other stores keep their existing policy. */
internal object AttentionLocalStoragePolicy {
    const val PREFIX = "galaxyssi:attention-local:v1:"
    private val databases = setOf("attention_feed_v1", "attention_push_v1", "attention_titles_v1",
        "attention_paired_titles_v1", "attention_news_evidence_v1")
    private val keys = setOf("proactive_attention_v1", "proactive_attention_evidence_v1", "attention_reader_position_v1")

    fun allows(database: String, key: String, value: String): Boolean {
        if (database in databases) return true
        if (database != GlobalAgentRepository.DATABASE_NAME) return false
        if (key in keys || key.startsWith("proactive_attention_evidence_row:")) return true
        if (!key.startsWith("proactive_message_row:")) return false
        val record = runCatching { JSONObject(value) }.getOrNull() ?: return false
        return record.optString("source_event_id").startsWith("research:${ProactiveAttentionPolicy.TASK_PREFIX}")
    }
}
