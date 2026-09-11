package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

internal object AgentMemoryStorage {
    const val DATABASE = "galaxyssi_agent_memory_v2"
    const val ITEMS = "items"
    val lock = Any()
}

class EncryptedAgentMemoryDeletionIndex(context: Context) {
    private val appContext = context.applicationContext
    private val database = AgentEncryptedDatabase(appContext, AgentMemoryStorage.DATABASE)
    private val legacy = AgentEncryptedDatabase(appContext, DATABASE_NAME)
    private val memoryRows = AgentPersonalMemoryRows(database)
    private val outbox = AgentMemoryRetractionOutbox(database, ::readRecord, ::ensureMigrated)

    fun record(deletedItems: List<AgentMemoryItem>): AgentMemoryDeletionTombstone? =
        synchronized(AgentMemoryStorage.lock) {
            val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(deletedItems) ?: return@synchronized null
            ensureMigrated()
            database.mutateStrings(records(listOf(tombstone)))
            tombstone
        }

    internal fun commitDeletion(deletedItems: List<AgentMemoryItem>, remainingItems: Sequence<JSONObject>): AgentMemoryDeletionTombstone? =
        synchronized(AgentMemoryStorage.lock) {
            val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(deletedItems) ?: return@synchronized null
            ensureMigrated()
            memoryRows.replace(remainingItems, records(listOf(tombstone)))
            tombstone
        }

    fun snapshot(): List<AgentMemoryDeletionTombstone> = synchronized(AgentMemoryStorage.lock) {
        ensureMigrated()
        buildList<AgentMemoryDeletionTombstone> { visitRecords { add(it) } }.sortedBy { it.deletedAtMillis }
    }

    fun mergeBackup(input: JSONArray?): List<AgentMemoryDeletionTombstone> = synchronized(AgentMemoryStorage.lock) {
        val incoming = decodeStrict(input ?: JSONArray())
        ensureMigrated()
        database.mutateStrings(records(incoming))
        snapshot()
    }

    fun exportJson(): JSONArray = synchronized(AgentMemoryStorage.lock) {
        ensureMigrated()
        JSONArray().apply { visitRecords { put(AgentMemoryCausalDeletionPolicy.encode(it)) } }
    }

    internal fun exportState(): JSONObject = synchronized(AgentMemoryStorage.lock) {
        ensureMigrated()
        JSONObject().put("memory", memoryRows.export())
            .put("memory_deletion_index", exportJson())
    }

    internal fun exportRecords(writer: BackupRecordStream.Writer) = synchronized(AgentMemoryStorage.lock) {
        ensureMigrated()
        writer.json("memory", "begin", JSONObject().put("schema", 1))
        val counts = memoryRows.exportRows { key, row -> writer.json("memory-row", key, row) }
        var deletions = 0L
        visitRecords { record ->
            writer.json("memory-deletion", record.id, AgentMemoryCausalDeletionPolicy.encode(record))
            deletions = Math.addExact(deletions, 1)
        }
        writer.json("memory", "end", JSONObject().put("rows", counts.first).put("active", counts.second).put("deletions", deletions))
    }

    internal fun restoreRecords(staging: MemoryBackupStaging) = synchronized(AgentMemoryStorage.lock) {
        ensureMigrated()
        visitRecords(staging::addLocalDeletion)
        staging.prepare()
        memoryRows.replacePrepared(staging.items(), staging.additionalRows())
    }

    internal fun restoreState(payload: JSONObject) {
        fun array(key: String): JSONArray? {
            if (!payload.has(key)) return null
            return payload.opt(key) as? JSONArray ?: error("Memory backup field must be an array: $key")
        }
        restoreState(array("memory"), array("memory_deletion_index"))
    }

    internal fun restoreState(memory: JSONArray?, deletionRecords: JSONArray?) = synchronized(AgentMemoryStorage.lock) {
        val incoming = decodeStrict(deletionRecords ?: JSONArray())
        ensureMigrated()
        val index = suppressionIndex().apply { incoming.forEach(::add) }
        val filtered = index.filter(memory ?: memoryRows.export())
        memoryRows.replace((0 until filtered.length()).asSequence().map { filtered.getJSONObject(it) }, records(incoming))
    }

    fun filterBackupItems(input: JSONArray): JSONArray = synchronized(AgentMemoryStorage.lock) {
        ensureMigrated()
        suppressionIndex().filter(input)
    }

    fun publishRetractions(): Int {
        val pending = outbox.requeueAll()
        if (pending > 0) AgentMemoryRetractionRecovery.enqueue(appContext)
        return pending
    }

    fun publishRetraction(tombstone: AgentMemoryDeletionTombstone): Boolean {
        if (tombstone.retractedEventIds.isEmpty()) return false
        AgentMemoryRetractionRecovery.enqueue(appContext)
        return true
    }

    internal fun pendingRetractions(limit: Int = 100): List<GlobalConversationEvent> = outbox.pending(limit)
    internal fun pendingRetractionCount(): Int = outbox.count()
    internal fun acknowledgeRetractions(eventIds: Set<String>) = outbox.acknowledge(eventIds)
    internal fun commitRetractionProjection(eventIds: Set<String>, persist: () -> Unit) {
        persist()
        outbox.acknowledge(eventIds)
    }

    private fun suppressionIndex() = AgentMemoryCausalDeletionPolicy.SuppressionIndex().apply { visitRecords(::add) }

    private fun records(items: List<AgentMemoryDeletionTombstone>): Map<String, String> = buildMap {
        items.forEach {
            put("$RECORD_PREFIX${it.id}", AgentMemoryCausalDeletionPolicy.encode(it).toString())
            putAll(AgentMemoryRetractionOutbox.references(it))
        }
    }

    private fun ensureMigrated() {
        if (database.contains(MIGRATION_KEY)) {
            check(database.readString(MIGRATION_KEY, "") == "1") { "Memory deletion migration marker is unreadable" }
            return
        }
        val oldRecords = decodeStrict(readArray(legacy, LEGACY_KEY))
        val updates = records(oldRecords).toMutableMap()
        updates[MIGRATION_KEY] = "1"
        // Rows and marker commit together. The original encrypted ledger remains
        // untouched, so interruption cannot destroy the only recoverable copy.
        database.mutateStrings(updates)
    }

    private fun visitRecords(visit: (AgentMemoryDeletionTombstone) -> Unit) {
        var cursor = ""
        while (true) {
            val keys = database.keysAfter(RECORD_PREFIX, cursor, PAGE_SIZE)
            if (keys.isEmpty()) return
            keys.forEach { visit(readRecord(it)) }
            cursor = keys.last()
        }
    }

    private fun readRecord(key: String): AgentMemoryDeletionTombstone {
        val raw = database.readString(key, "")
        val json = try { JSONObject(raw) } catch (_: JSONException) {
            error("Memory deletion record is unreadable")
        }
        val tombstone = AgentMemoryCausalDeletionPolicy.decode(json)
            ?: error("Memory deletion record failed integrity validation")
        check(key == "$RECORD_PREFIX${tombstone.id}") { "Memory deletion record identity mismatch" }
        return tombstone
    }

    private fun readArray(storage: AgentEncryptedDatabase, key: String): JSONArray {
        if (!storage.contains(key)) return JSONArray()
        return try { JSONArray(storage.readString(key, "")) } catch (_: JSONException) {
            error("Memory deletion or backup data is unreadable")
        }
    }

    private fun decodeStrict(array: JSONArray): List<AgentMemoryDeletionTombstone> = buildList {
        for (index in 0 until array.length()) {
            add(AgentMemoryCausalDeletionPolicy.decode(array.optJSONObject(index))
                ?: error("Memory deletion backup failed integrity validation"))
        }
    }

    companion object {
        // Kept only as the source of the one-time legacy migration.
        const val DATABASE_NAME = "galaxyssi_agent_memory_deletions_v1"
        internal const val RECORD_PREFIX = "memory-deletion:v2:record:"
        internal const val MIGRATION_KEY = "memory-deletion:v2:migrated"
        private const val LEGACY_KEY = "tombstones"
        private const val PAGE_SIZE = 128
    }
}
