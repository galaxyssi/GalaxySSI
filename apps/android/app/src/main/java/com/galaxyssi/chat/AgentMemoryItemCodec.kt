package com.galaxyssi.chat

import org.json.JSONObject
import java.util.Locale
import java.util.UUID

internal object AgentMemoryItemCodec {
    fun encode(item: AgentMemoryItem): JSONObject = JSONObject()
        .put("id", item.id)
        .put("kind", item.kind.name)
        .put("value", item.value)
        .put("key", item.key)
        .put("source", item.source)
        .put("timestamp_millis", item.timestampMillis)
        .put("version", item.version)
        .put("supersedes_id", item.supersedesId)
        .put("important", item.important)
        .put("status", item.status.name)
        .put("conflict_group_id", item.conflictGroupId)
        .put("scope", item.scope.name)
        .put("scope_id", item.scopeId)
        .put("confidence", item.confidence)
        .put("evidence_count", item.evidenceCount)
        .put("auto_learned", item.autoLearned)
        .put("last_confirmed_at_millis", item.lastConfirmedAtMillis)
        .put("last_accessed_at_millis", item.lastAccessedAtMillis)
        .put("expires_at_millis", item.expiresAtMillis)
        .put("why_remembered", item.whyRemembered)
        .put("origin_conversation_id", item.originConversationId)
        .put("origin_event_id", item.originEventId)
        .put("private_memory", item.privateMemory)

    fun decode(json: JSONObject): AgentMemoryItem? {
        val value = json.optString("value").trim()
        if (value.isBlank()) return null
        return AgentMemoryItem(
            kind = enumOrDefault(json.optString("kind"), AgentMemoryKind.TASK),
            value = value,
            timestampMillis = json.optLong("timestamp_millis", System.currentTimeMillis()),
            id = json.optString("id").ifBlank { UUID.randomUUID().toString() },
            source = json.optString("source", "agent"),
            key = normalizeKey(json.optString("key")),
            version = json.optInt("version", 1).coerceAtLeast(1),
            supersedesId = json.optString("supersedes_id"),
            important = json.optBoolean("important", false),
            status = enumOrDefault(json.optString("status"), AgentMemoryStatus.ACTIVE),
            conflictGroupId = json.optString("conflict_group_id"),
            scope = enumOrDefault(json.optString("scope"), AgentMemoryScope.GLOBAL),
            scopeId = json.optString("scope_id"),
            confidence = json.optDouble("confidence", 0.65).coerceIn(0.0, 1.0),
            evidenceCount = json.optInt("evidence_count", 1).coerceIn(1, MAX_EVIDENCE_COUNT),
            autoLearned = json.optBoolean("auto_learned", false),
            lastConfirmedAtMillis = json.optLong("last_confirmed_at_millis", 0L).coerceAtLeast(0L),
            lastAccessedAtMillis = json.optLong("last_accessed_at_millis", 0L).coerceAtLeast(0L),
            expiresAtMillis = json.optLong("expires_at_millis", 0L).coerceAtLeast(0L),
            whyRemembered = json.optString("why_remembered").take(1_000),
            originConversationId = json.optString("origin_conversation_id").take(160),
            originEventId = json.optString("origin_event_id").take(160),
            privateMemory = json.optBoolean("private_memory")
        )
    }

    fun normalizeKey(value: String): String = value
        .trim()
        .lowercase(Locale.US)
        .replace(Regex("[^\\p{L}\\p{N} _:.-]"), "")
        .replace(Regex("\\s+"), " ")
        .take(MAX_KEY_LENGTH)

    private const val MAX_EVIDENCE_COUNT = 10_000
    private const val MAX_KEY_LENGTH = 80
}
