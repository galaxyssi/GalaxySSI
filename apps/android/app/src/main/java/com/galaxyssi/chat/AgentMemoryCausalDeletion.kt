package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

data class AgentMemoryDeletionTombstone(
    val id: String,
    val memoryIds: Set<String>,
    val semanticFingerprints: Set<String>,
    val retractedEventIds: Set<String>,
    val deletedAtMillis: Long
)

object AgentMemoryCausalDeletionPolicy {
    fun tombstone(
        deletedItems: List<AgentMemoryItem>,
        deletedAtMillis: Long = System.currentTimeMillis()
    ): AgentMemoryDeletionTombstone? {
        if (deletedItems.isEmpty()) return null
        val memoryIds = deletedItems.mapTo(linkedSetOf(), AgentMemoryItem::id)
        val fingerprints = deletedItems.mapTo(linkedSetOf(), ::semanticFingerprint)
        val retractions = GlobalPersistentContextObservationExtractor
            .memoryMutations(deletedItems, emptyList(), deletedAtMillis)
            .flatMapTo(linkedSetOf()) { it.effectiveRetractions() }
        val id = tombstoneId(memoryIds, fingerprints, retractions, deletedAtMillis)
        return AgentMemoryDeletionTombstone(
            id = id,
            memoryIds = memoryIds,
            semanticFingerprints = fingerprints,
            retractedEventIds = retractions,
            deletedAtMillis = deletedAtMillis
        )
    }

    fun merge(
        current: List<AgentMemoryDeletionTombstone>,
        incoming: List<AgentMemoryDeletionTombstone>
    ): List<AgentMemoryDeletionTombstone> = (current + incoming)
        .filter { it.id.isNotBlank() && it.deletedAtMillis > 0L }
        .associateBy(AgentMemoryDeletionTombstone::id)
        .values
        .sortedBy(AgentMemoryDeletionTombstone::deletedAtMillis)

    fun filterRestoredItems(
        items: List<AgentMemoryItem>,
        tombstones: List<AgentMemoryDeletionTombstone>
    ): List<AgentMemoryItem> {
        val index = SuppressionIndex().apply { tombstones.forEach(::add) }
        return items.filterNot(index::isSuppressed)
    }

    fun filterBackupItems(
        input: JSONArray,
        tombstones: List<AgentMemoryDeletionTombstone>
    ): JSONArray = SuppressionIndex().apply { tombstones.forEach(::add) }.filter(input)

    fun retractionEvents(tombstone: AgentMemoryDeletionTombstone): List<GlobalConversationEvent> =
        tombstone.retractedEventIds.sorted().chunked(MAX_RETRACTIONS_PER_EVENT).mapIndexed { index, ids ->
            GlobalConversationEvent(
                id = "memory-causal-deletion:${tombstone.id}:$index",
                type = GlobalConversationEventType.MEMORY_DELETED,
                conversationId = "global-memory",
                messageId = tombstone.id,
                actor = GlobalConversationActor.SYSTEM,
                timestampMillis = tombstone.deletedAtMillis,
                contentRef = "encrypted://agent-memory-deletion/${tombstone.id}",
                conversationTitle = "Personal memory",
                metadata = mapOf(
                    "origin" to "agent_memory_causal_deletion",
                    "deletion_id" to tombstone.id,
                    "deletion_chunk" to index.toString(),
                    "projection" to "retract_only"
                ),
                retractedEventIds = ids.toSet()
            )
        }

    fun encode(tombstone: AgentMemoryDeletionTombstone): JSONObject = JSONObject()
        .put("id", tombstone.id)
        .put("memory_ids", JSONArray(tombstone.memoryIds.sorted()))
        .put("semantic_fingerprints", JSONArray(tombstone.semanticFingerprints.sorted()))
        .put("retracted_event_ids", JSONArray(tombstone.retractedEventIds.sorted()))
        .put("deleted_at_millis", tombstone.deletedAtMillis)

    fun decode(json: JSONObject?): AgentMemoryDeletionTombstone? {
        if (json == null) return null
        val id = json.optString("id").trim()
        val deletedAtMillis = json.optLong("deleted_at_millis").coerceAtLeast(0L)
        if (id.isBlank() || deletedAtMillis <= 0L) return null
        val memoryIds = json.optJSONArray("memory_ids").strings() ?: return null
        val semanticFingerprints = json.optJSONArray("semantic_fingerprints").strings() ?: return null
        val retractedEventIds = json.optJSONArray("retracted_event_ids").strings() ?: return null
        if (id != tombstoneId(memoryIds, semanticFingerprints, retractedEventIds, deletedAtMillis)) return null
        return AgentMemoryDeletionTombstone(
            id = id,
            memoryIds = memoryIds,
            semanticFingerprints = semanticFingerprints,
            retractedEventIds = retractedEventIds,
            deletedAtMillis = deletedAtMillis
        )
    }

    internal fun semanticFingerprint(item: AgentMemoryItem): String = semanticFingerprint(
        kind = item.kind.name,
        key = item.key,
        value = item.value,
        scope = item.scope.name,
        scopeId = item.scopeId
    )

    internal class SuppressionIndex {
        private val memoryIds = hashSetOf<String>()
        private val deletedThrough = hashMapOf<String, Long>()

        fun add(tombstone: AgentMemoryDeletionTombstone) {
            memoryIds.addAll(tombstone.memoryIds)
            tombstone.semanticFingerprints.forEach { fingerprint ->
                deletedThrough[fingerprint] = maxOf(deletedThrough[fingerprint] ?: 0L, tombstone.deletedAtMillis)
            }
        }

        fun isSuppressed(item: AgentMemoryItem): Boolean = matches(item.id, item.timestampMillis,
            item.kind.name, item.key, item.value, item.scope.name, item.scopeId)

        fun filter(input: JSONArray): JSONArray = JSONArray().apply {
            val seenIds = hashSetOf<String>()
            for (index in 0 until input.length()) {
                val item = input.optJSONObject(index) ?: error("Memory backup contains an invalid record")
                val id = item.opt("id") as? String
                val value = item.opt("value") as? String
                check(!id.isNullOrBlank() && !value.isNullOrBlank()) { "Memory backup record identity or value is missing" }
                check(seenIds.add(id)) { "Memory backup contains duplicate identities" }
                val kind = AgentMemoryKind.entries.firstOrNull { it.name == item.optString("kind") } ?: AgentMemoryKind.TASK
                val scope = AgentMemoryScope.entries.firstOrNull { it.name == item.optString("scope") } ?: AgentMemoryScope.GLOBAL
                if (!matches(id, item.optLong("timestamp_millis").coerceAtLeast(0L),
                        kind.name, item.optString("key"), value, scope.name, item.optString("scope_id"))) put(item)
            }
        }

        private fun matches(id: String, timestamp: Long, kind: String, key: String, value: String,
            scope: String, scopeId: String): Boolean {
            if (id in memoryIds) return true
            val exact = semanticFingerprint(kind, key, value, scope, scopeId)
            val legacy = semanticFingerprint(kind, key, value, scope, scopeId, legacyScope = true)
            return deletedThrough[exact]?.let { timestamp <= it } == true ||
                deletedThrough[legacy]?.let { timestamp <= it } == true
        }
    }

    private fun semanticFingerprint(
        kind: String,
        key: String,
        value: String,
        scope: String,
        scopeId: String,
        legacyScope: Boolean = false
    ): String {
        val normalizedKey = normalize(key)
        val semanticIdentity = normalizedKey.ifBlank { digest(normalize(value)) }
        val fields = listOf(
            kind.trim().uppercase(Locale.ROOT),
            scope.trim().uppercase(Locale.ROOT),
            if (legacyScope) normalize(scopeId) else scopeId,
            semanticIdentity
        )
        // Legacy hashes cannot recover the original case-sensitive scope ID. Keep
        // recognizing existing deletions, but never emit another lossy scope hash.
        return if (legacyScope) digest(fields.joinToString("\u0000"))
        else "scope-v2:" + digest(fields.joinToString("") { "${it.length}:$it" })
    }

    private fun tombstoneId(
        memoryIds: Set<String>,
        semanticFingerprints: Set<String>,
        retractedEventIds: Set<String>,
        deletedAtMillis: Long
    ): String = digest(
        listOf(
            "memory-causal-deletion",
            deletedAtMillis.toString(),
            memoryIds.sorted().joinToString("|"),
            semanticFingerprints.sorted().joinToString("|"),
            retractedEventIds.sorted().joinToString("|")
        ).joinToString("\u0000")
    )

    private fun normalize(value: String): String = value
        .lowercase(Locale.ROOT)
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }

    private fun JSONArray?.strings(): Set<String>? {
        if (this == null) return null
        val result = linkedSetOf<String>()
        for (index in 0 until length()) {
            val value = opt(index) as? String ?: return null
            if (value.isBlank() || !result.add(value)) return null
        }
        return result
    }

    private const val MAX_RETRACTIONS_PER_EVENT = 128
}
