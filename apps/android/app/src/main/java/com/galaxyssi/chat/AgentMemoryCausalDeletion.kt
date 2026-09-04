package com.galaxyssi.chat

import android.content.Context
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
        .takeLast(MAX_TOMBSTONES)

    fun filterRestoredItems(
        items: List<AgentMemoryItem>,
        tombstones: List<AgentMemoryDeletionTombstone>
    ): List<AgentMemoryItem> = items.filterNot { item -> isSuppressed(item, tombstones) }

    fun filterBackupItems(
        input: JSONArray,
        tombstones: List<AgentMemoryDeletionTombstone>
    ): JSONArray = JSONArray().apply {
        for (index in 0 until input.length()) {
            val item = input.optJSONObject(index) ?: continue
            if (!isSuppressed(item, tombstones)) put(item)
        }
    }

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
        val memoryIds = json.optJSONArray("memory_ids").strings(MAX_IDS_PER_TOMBSTONE)
        val semanticFingerprints = json.optJSONArray("semantic_fingerprints")
            .strings(MAX_IDS_PER_TOMBSTONE)
        val retractedEventIds = json.optJSONArray("retracted_event_ids")
            .strings(MAX_RETRACTIONS_PER_TOMBSTONE)
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

    private fun isSuppressed(
        item: AgentMemoryItem,
        tombstones: List<AgentMemoryDeletionTombstone>
    ): Boolean {
        val fingerprint = semanticFingerprint(item)
        return tombstones.any { tombstone ->
            item.id in tombstone.memoryIds ||
                (item.timestampMillis <= tombstone.deletedAtMillis &&
                    fingerprint in tombstone.semanticFingerprints)
        }
    }

    private fun isSuppressed(
        item: JSONObject,
        tombstones: List<AgentMemoryDeletionTombstone>
    ): Boolean {
        val itemId = item.optString("id").trim()
        val timestampMillis = item.optLong("timestamp_millis").coerceAtLeast(0L)
        val fingerprint = semanticFingerprint(
            kind = item.optString("kind"),
            key = item.optString("key"),
            value = item.optString("value"),
            scope = item.optString("scope"),
            scopeId = item.optString("scope_id")
        )
        return tombstones.any { tombstone ->
            itemId in tombstone.memoryIds ||
                (timestampMillis <= tombstone.deletedAtMillis &&
                    fingerprint in tombstone.semanticFingerprints)
        }
    }

    private fun semanticFingerprint(
        kind: String,
        key: String,
        value: String,
        scope: String,
        scopeId: String
    ): String {
        val normalizedKey = normalize(key)
        val semanticIdentity = normalizedKey.ifBlank { digest(normalize(value)) }
        return digest(
            listOf(
                kind.trim().uppercase(Locale.ROOT),
                scope.trim().uppercase(Locale.ROOT),
                normalize(scopeId),
                semanticIdentity
            ).joinToString("\u0000")
        )
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

    private fun JSONArray?.strings(limit: Int): Set<String> {
        if (this == null) return emptySet()
        return buildSet {
            for (index in 0 until length()) {
                optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
                if (size >= limit) break
            }
        }
    }

    private const val MAX_TOMBSTONES = 2_000
    private const val MAX_IDS_PER_TOMBSTONE = 1_000
    private const val MAX_RETRACTIONS_PER_TOMBSTONE = 2_000
    private const val MAX_RETRACTIONS_PER_EVENT = 128
}

class EncryptedAgentMemoryDeletionIndex(context: Context) {
    private val appContext = context.applicationContext
    private val database = AgentEncryptedDatabase(appContext, DATABASE_NAME)

    @Synchronized
    fun record(deletedItems: List<AgentMemoryItem>): AgentMemoryDeletionTombstone? {
        val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(deletedItems) ?: return null
        save(AgentMemoryCausalDeletionPolicy.merge(snapshot(), listOf(tombstone)))
        return tombstone
    }

    @Synchronized
    fun snapshot(): List<AgentMemoryDeletionTombstone> = decode(
        runCatching { JSONArray(database.readString(KEY_TOMBSTONES, "[]")) }.getOrDefault(JSONArray())
    )

    @Synchronized
    fun mergeBackup(input: JSONArray?): List<AgentMemoryDeletionTombstone> {
        val merged = AgentMemoryCausalDeletionPolicy.merge(snapshot(), decode(input ?: JSONArray()))
        save(merged)
        return merged
    }

    @Synchronized
    fun exportJson(): JSONArray = JSONArray().apply {
        snapshot().forEach { put(AgentMemoryCausalDeletionPolicy.encode(it)) }
    }

    fun filterBackupItems(input: JSONArray): JSONArray =
        AgentMemoryCausalDeletionPolicy.filterBackupItems(input, snapshot())

    fun publishRetractions(): Int {
        val events = snapshot().flatMap(AgentMemoryCausalDeletionPolicy::retractionEvents)
        if (events.isEmpty()) return 0
        val accepted = GlobalAgentRepository(appContext).enqueueAll(events)
        if (accepted > 0) GlobalConversationEventBus.requestProcessing(appContext)
        return accepted
    }

    fun publishRetraction(tombstone: AgentMemoryDeletionTombstone): Boolean {
        val accepted = GlobalAgentRepository(appContext).enqueueAll(
            AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone)
        )
        if (accepted > 0) GlobalConversationEventBus.requestProcessing(appContext)
        return accepted > 0
    }

    private fun decode(array: JSONArray): List<AgentMemoryDeletionTombstone> = buildList {
        for (index in 0 until array.length()) {
            AgentMemoryCausalDeletionPolicy.decode(array.optJSONObject(index))?.let(::add)
        }
    }

    private fun save(tombstones: List<AgentMemoryDeletionTombstone>) {
        val array = JSONArray()
        tombstones.forEach { array.put(AgentMemoryCausalDeletionPolicy.encode(it)) }
        database.writeString(KEY_TOMBSTONES, array.toString())
    }

    companion object {
        const val DATABASE_NAME = "galaxyssi_agent_memory_deletions_v1"
        private const val KEY_TOMBSTONES = "tombstones"
    }
}
