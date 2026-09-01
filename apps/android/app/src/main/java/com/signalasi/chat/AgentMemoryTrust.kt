package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

data class AgentMemoryUsageRecord(
    val id: String = UUID.randomUUID().toString(),
    val memoryIds: List<String>,
    val conversationId: String,
    val turnId: String,
    val querySha256: String,
    val runId: String = "",
    val answerPreview: String = "",
    val selectedAtMillis: Long = System.currentTimeMillis(),
    val answeredAtMillis: Long = 0L
)

data class AgentMemoryTrustProfile(
    val memoryId: String,
    val whyRemembered: String,
    val source: String,
    val currentState: String,
    val lastVerifiedAtMillis: Long,
    val privateMemory: Boolean,
    val usages: List<AgentMemoryUsageRecord>
)

class AgentMemoryTrustStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun recordSelection(
        memoryIds: List<String>,
        conversationId: String,
        turnId: String,
        query: String,
        nowMillis: Long = System.currentTimeMillis()
    ): AgentMemoryUsageRecord? {
        val ids = memoryIds.map(String::trim).filter(String::isNotBlank).distinct().take(MAX_MEMORY_IDS)
        val cleanConversation = conversationId.trim().take(160)
        if (ids.isEmpty() || cleanConversation.isBlank()) return null
        val digest = sha256(query.trim().take(8_000))
        val duplicate = recent(MAX_RECORDS).firstOrNull { item ->
            item.conversationId == cleanConversation &&
                item.turnId == turnId.trim() &&
                item.querySha256 == digest &&
                item.memoryIds == ids &&
                nowMillis - item.selectedAtMillis in 0..DUPLICATE_WINDOW_MILLIS
        }
        if (duplicate != null) return duplicate
        val record = AgentMemoryUsageRecord(
            memoryIds = ids,
            conversationId = cleanConversation,
            turnId = turnId.trim().take(160),
            querySha256 = digest,
            selectedAtMillis = nowMillis
        )
        database.writeString("$KEY_PREFIX${record.id}", encode(record).toString())
        prune()
        return record
    }

    @Synchronized
    fun attachAnswer(
        conversationId: String,
        runId: String,
        answer: String,
        answeredAtMillis: Long = System.currentTimeMillis()
    ): Int {
        val cleanConversation = conversationId.trim()
        val cleanRun = runId.trim()
        if (cleanConversation.isBlank() || cleanRun.isBlank()) return 0
        val candidates = recent(MAX_RECORDS).filter { record ->
            record.conversationId == cleanConversation &&
                record.runId.isBlank() &&
                answeredAtMillis - record.selectedAtMillis in 0..ANSWER_LINK_WINDOW_MILLIS
        }
        candidates.forEach { record ->
            database.writeString("$KEY_PREFIX${record.id}", encode(record.copy(
                runId = cleanRun.take(160),
                answerPreview = answer.replace(Regex("\\s+"), " ").trim().take(MAX_ANSWER_PREVIEW),
                answeredAtMillis = answeredAtMillis
            )).toString())
        }
        return candidates.size
    }

    @Synchronized
    fun usagesFor(memoryId: String, limit: Int = 20): List<AgentMemoryUsageRecord> {
        val cleanId = memoryId.trim()
        if (cleanId.isBlank()) return emptyList()
        return recent(MAX_RECORDS).filter { cleanId in it.memoryIds }.take(limit.coerceIn(1, 100))
    }

    @Synchronized
    fun recent(limit: Int = 100): List<AgentMemoryUsageRecord> = database.entries(KEY_PREFIX)
        .mapNotNull { decode(it.second) }
        .sortedByDescending(AgentMemoryUsageRecord::selectedAtMillis)
        .take(limit.coerceIn(1, MAX_RECORDS))

    fun profile(item: AgentMemoryItem): AgentMemoryTrustProfile = AgentMemoryTrustProfile(
        memoryId = item.id,
        whyRemembered = item.whyRemembered.ifBlank { whyFromSource(item) },
        source = item.source,
        currentState = when (item.status) {
            AgentMemoryStatus.ACTIVE -> "current"
            AgentMemoryStatus.CONFLICTED -> "conflicted"
            AgentMemoryStatus.SUPERSEDED -> "historical"
        },
        lastVerifiedAtMillis = maxOf(item.lastConfirmedAtMillis, item.timestampMillis),
        privateMemory = item.privateMemory,
        usages = usagesFor(item.id)
    )

    private fun whyFromSource(item: AgentMemoryItem): String = when (item.source) {
        "explicit_core_memory" -> "The user explicitly stated this durable fact."
        "automatic_learning" -> "Repeated successful Agent runs supported this memory."
        "automatic_failure_learning" -> "Repeated failures established a condition that should not be retried unchanged."
        "memory_edit" -> "The user corrected an earlier memory."
        "memory_conflict_selection", "memory_conflict_merge" -> "The user resolved conflicting memory candidates."
        else -> if (item.autoLearned) "SignalASI inferred this from repeated evidence." else "Saved from an Agent interaction."
    }

    private fun prune() {
        val retained = recent(MAX_RECORDS).mapTo(hashSetOf()) { "$KEY_PREFIX${it.id}" }
        database.removeAll(database.keys(KEY_PREFIX).filterNot(retained::contains))
    }

    private fun encode(value: AgentMemoryUsageRecord) = JSONObject()
        .put("id", value.id)
        .put("memory_ids", JSONArray(value.memoryIds))
        .put("conversation_id", value.conversationId)
        .put("turn_id", value.turnId)
        .put("query_sha256", value.querySha256)
        .put("run_id", value.runId)
        .put("answer_preview", value.answerPreview)
        .put("selected_at_millis", value.selectedAtMillis)
        .put("answered_at_millis", value.answeredAtMillis)

    private fun decode(raw: String): AgentMemoryUsageRecord? = runCatching {
        val json = JSONObject(raw)
        val ids = json.getJSONArray("memory_ids")
        AgentMemoryUsageRecord(
            id = json.getString("id"),
            memoryIds = buildList {
                for (index in 0 until ids.length()) ids.optString(index).takeIf(String::isNotBlank)?.let(::add)
            },
            conversationId = json.getString("conversation_id"),
            turnId = json.optString("turn_id"),
            querySha256 = json.getString("query_sha256"),
            runId = json.optString("run_id"),
            answerPreview = json.optString("answer_preview"),
            selectedAtMillis = json.optLong("selected_at_millis"),
            answeredAtMillis = json.optLong("answered_at_millis")
        )
    }.getOrNull()

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }

    private companion object {
        const val DATABASE = "signalasi_memory_trust_v1"
        const val KEY_PREFIX = "usage:"
        const val MAX_RECORDS = 2_000
        const val MAX_MEMORY_IDS = 32
        const val MAX_ANSWER_PREVIEW = 320
        const val DUPLICATE_WINDOW_MILLIS = 60_000L
        const val ANSWER_LINK_WINDOW_MILLIS = 30L * 60_000L
    }
}
