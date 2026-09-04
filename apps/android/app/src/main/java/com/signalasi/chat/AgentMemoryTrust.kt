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
    val oldestMemoryTimestampMillis: Long = 0L,
    val newestMemoryTimestampMillis: Long = 0L,
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

internal object AgentMemoryHorizonPolicy {
    fun qualifies(
        oldestMemoryTimestampMillis: Long,
        answeredAtMillis: Long,
        requiredHorizonDays: Int
    ): Boolean {
        val horizon = requiredHorizonDays.coerceIn(0, MAX_HORIZON_DAYS)
        if (horizon == 0) return true
        if (oldestMemoryTimestampMillis <= 0L || answeredAtMillis <= 0L) return false
        val minimumAgeMillis = horizon.toLong() * DAY_MILLIS
        return answeredAtMillis - oldestMemoryTimestampMillis >= minimumAgeMillis
    }

    private const val MAX_HORIZON_DAYS = 3_650
    private const val DAY_MILLIS = 86_400_000L
}

class AgentMemoryTrustStore internal constructor(private val database: AgentEncryptedDatabase) {
    constructor(context: Context) : this(AgentEncryptedDatabase(context.applicationContext, DATABASE))

    @Synchronized
    fun recordSelection(
        memoryIds: List<String>,
        conversationId: String,
        turnId: String,
        query: String,
        memoryTimestampsMillis: List<Long> = emptyList(),
        nowMillis: Long = System.currentTimeMillis()
    ): AgentMemoryUsageRecord? {
        val ids = memoryIds.map(String::trim).filter(String::isNotBlank).distinct().take(MAX_MEMORY_IDS)
        val cleanConversation = conversationId.trim().take(160)
        val cleanTurn = turnId.trim().take(160)
        if (ids.isEmpty() || cleanConversation.isBlank()) return null
        val digest = queryDigest(query)
        val pendingKey = pendingIndexKey(cleanConversation, cleanTurn, digest)
        val pending = indexedRecords(pendingKey)
        val duplicate = pending.firstOrNull { item ->
            item.conversationId == cleanConversation &&
                item.turnId == cleanTurn &&
                item.querySha256 == digest &&
                item.memoryIds == ids &&
                nowMillis - item.selectedAtMillis in 0..DUPLICATE_WINDOW_MILLIS
        }
        if (duplicate != null) return duplicate
        val record = AgentMemoryUsageRecord(
            memoryIds = ids,
            conversationId = cleanConversation,
            turnId = cleanTurn,
            querySha256 = digest,
            oldestMemoryTimestampMillis = memoryTimestampsMillis.filter { it > 0L }.minOrNull() ?: 0L,
            newestMemoryTimestampMillis = memoryTimestampsMillis.filter { it > 0L }.maxOrNull() ?: 0L,
            selectedAtMillis = nowMillis
        )
        database.mutateStrings(mapOf(
            "$KEY_PREFIX${record.id}" to encode(record).toString(),
            pendingKey to encodeIds((pending.map(AgentMemoryUsageRecord::id) + record.id).distinct())
        ))
        prune()
        return record
    }

    fun hasPendingSelection(conversationId: String, turnId: String, query: String): Boolean {
        val cleanConversation = conversationId.trim().take(160)
        if (cleanConversation.isBlank()) return false
        return database.contains(pendingIndexKey(
            cleanConversation,
            turnId.trim().take(160),
            queryDigest(query)
        ))
    }

    @Synchronized
    fun attachAnswer(
        conversationId: String,
        runId: String,
        answer: String,
        query: String = "",
        turnId: String = "",
        answeredAtMillis: Long = System.currentTimeMillis()
    ): Int {
        val cleanConversation = conversationId.trim()
        val cleanRun = runId.trim()
        if (cleanConversation.isBlank() || cleanRun.isBlank()) return 0
        val queryDigest = query.trim().takeIf(String::isNotBlank)?.let(::queryDigest)
        val cleanTurn = turnId.trim().take(160)
        val pendingKey = queryDigest?.let { pendingIndexKey(cleanConversation, cleanTurn, it) }
        val indexed = pendingKey?.let(::indexedRecords).orEmpty()
        val candidates = indexed.filter { record ->
            record.conversationId == cleanConversation &&
                record.runId.isBlank() &&
                (cleanTurn.isBlank() || record.turnId == cleanTurn) &&
                (queryDigest == null || record.querySha256 == queryDigest) &&
                answeredAtMillis - record.selectedAtMillis in 0..ANSWER_LINK_WINDOW_MILLIS
        }
        if (candidates.isEmpty()) return 0
        val linked = candidates.map { record ->
            record.copy(
                runId = cleanRun.take(160),
                answerPreview = answer.replace(Regex("\\s+"), " ").trim().take(MAX_ANSWER_PREVIEW),
                answeredAtMillis = answeredAtMillis
            )
        }
        val existingRunIds = indexedIds(runIndexKey(cleanRun))
        database.mutateStrings(
            upserts = buildMap {
                linked.forEach { record -> put("$KEY_PREFIX${record.id}", encode(record).toString()) }
                put(runIndexKey(cleanRun), encodeIds((existingRunIds + linked.map(AgentMemoryUsageRecord::id)).distinct()))
            },
            removeKeys = listOfNotNull(pendingKey)
        )
        return linked.size
    }

    @Synchronized
    fun usagesFor(memoryId: String, limit: Int = 20): List<AgentMemoryUsageRecord> {
        val cleanId = memoryId.trim()
        if (cleanId.isBlank()) return emptyList()
        return recent(MAX_RECORDS).filter { cleanId in it.memoryIds }.take(limit.coerceIn(1, 100))
    }

    @Synchronized
    fun verifiedUsageForRun(
        runId: String,
        requiredHorizonDays: Int,
        answeredAtMillis: Long
    ): AgentMemoryUsageRecord? {
        val cleanRunId = runId.trim()
        if (cleanRunId.isBlank()) return null
        return indexedRecords(runIndexKey(cleanRunId)).firstOrNull { record ->
            record.runId == cleanRunId &&
                record.memoryIds.isNotEmpty() &&
                record.answeredAtMillis > 0L &&
                AgentMemoryHorizonPolicy.qualifies(
                    record.oldestMemoryTimestampMillis,
                    answeredAtMillis,
                    requiredHorizonDays
                )
        }
    }

    @Synchronized
    fun recent(limit: Int = 100): List<AgentMemoryUsageRecord> {
        val keys = database.recentKeys(KEY_PREFIX, limit.coerceIn(1, MAX_RECORDS))
        val values = database.readStrings(keys)
        return keys.mapNotNull { key -> values[key]?.let(::decode) }
            .sortedByDescending(AgentMemoryUsageRecord::selectedAtMillis)
    }

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
        val retained = database.recentKeys(KEY_PREFIX, MAX_RECORDS).toHashSet()
        database.removeAll(database.keys(KEY_PREFIX).filterNot(retained::contains))
    }

    private fun indexedRecords(indexKey: String): List<AgentMemoryUsageRecord> {
        val ids = indexedIds(indexKey)
        if (ids.isEmpty()) return emptyList()
        val keys = ids.map { "$KEY_PREFIX$it" }
        val values = database.readStrings(keys)
        return keys.mapNotNull { key -> values[key]?.let(::decode) }
    }

    private fun indexedIds(indexKey: String): List<String> = runCatching {
        val array = JSONArray(database.readString(indexKey, "[]"))
        buildList {
            for (index in 0 until array.length()) {
                array.optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
            }
        }.distinct().take(MAX_INDEXED_RECORDS)
    }.getOrDefault(emptyList())

    private fun encodeIds(ids: List<String>) = JSONArray(ids.distinct().takeLast(MAX_INDEXED_RECORDS)).toString()

    private fun pendingIndexKey(conversationId: String, turnId: String, queryDigest: String): String =
        "$PENDING_INDEX_PREFIX${sha256("$conversationId\u001f${turnId.trim()}\u001f$queryDigest")}"

    private fun runIndexKey(runId: String) = "$RUN_INDEX_PREFIX${runId.trim()}"

    private fun queryDigest(query: String) = sha256(query.trim().take(MAX_QUERY_CHARS))

    private fun encode(value: AgentMemoryUsageRecord) = JSONObject()
        .put("id", value.id)
        .put("memory_ids", JSONArray(value.memoryIds))
        .put("conversation_id", value.conversationId)
        .put("turn_id", value.turnId)
        .put("query_sha256", value.querySha256)
        .put("run_id", value.runId)
        .put("answer_preview", value.answerPreview)
        .put("oldest_memory_timestamp_millis", value.oldestMemoryTimestampMillis)
        .put("newest_memory_timestamp_millis", value.newestMemoryTimestampMillis)
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
            oldestMemoryTimestampMillis = json.optLong("oldest_memory_timestamp_millis"),
            newestMemoryTimestampMillis = json.optLong("newest_memory_timestamp_millis"),
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
        const val PENDING_INDEX_PREFIX = "pending-index:"
        const val RUN_INDEX_PREFIX = "run-index:"
        const val MAX_RECORDS = 2_000
        const val MAX_INDEXED_RECORDS = 32
        const val MAX_QUERY_CHARS = 8_000
        const val MAX_MEMORY_IDS = 32
        const val MAX_ANSWER_PREVIEW = 320
        const val DUPLICATE_WINDOW_MILLIS = 60_000L
        const val ANSWER_LINK_WINDOW_MILLIS = 30L * 60_000L
    }
}
