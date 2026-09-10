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

    fun record(deletedItems: List<AgentMemoryItem>): AgentMemoryDeletionTombstone? =
        synchronized(AgentMemoryStorage.lock) {
            val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(deletedItems) ?: return@synchronized null
            ensureMigrated()
            database.mutateStrings(records(listOf(tombstone)))
            tombstone
        }

    internal fun commitDeletion(deletedItems: List<AgentMemoryItem>, remainingItems: String): AgentMemoryDeletionTombstone? =
        synchronized(AgentMemoryStorage.lock) {
            val tombstone = AgentMemoryCausalDeletionPolicy.tombstone(deletedItems) ?: return@synchronized null
            ensureMigrated()
            val updates = linkedMapOf(AgentMemoryStorage.ITEMS to remainingItems)
            updates.putAll(records(listOf(tombstone)))
            database.mutateStrings(updates)
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
        JSONObject().put("memory", readArray(database, AgentMemoryStorage.ITEMS))
            .put("memory_deletion_index", exportJson())
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
        val filtered = index.filter(memory ?: readArray(database, AgentMemoryStorage.ITEMS))
        val updates = linkedMapOf(AgentMemoryStorage.ITEMS to filtered.toString())
        updates.putAll(records(incoming))
        database.mutateStrings(updates)
    }

    fun filterBackupItems(input: JSONArray): JSONArray = synchronized(AgentMemoryStorage.lock) {
        ensureMigrated()
        suppressionIndex().filter(input)
    }

    fun publishRetractions(): Int {
        val repository = GlobalAgentRepository(appContext)
        var accepted = 0
        var cursor = ""
        while (true) {
            val page = synchronized(AgentMemoryStorage.lock) {
                ensureMigrated()
                database.keysAfter(RECORD_PREFIX, cursor, PAGE_SIZE).map { it to readRecord(it) }
            }
            if (page.isEmpty()) break
            page.forEach { (_, tombstone) ->
                AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone).forEach { event ->
                    accepted += repository.enqueueAll(listOf(event))
                }
            }
            cursor = page.last().first
        }
        if (accepted > 0) GlobalConversationEventBus.requestProcessing(appContext)
        return accepted
    }

    fun publishRetraction(tombstone: AgentMemoryDeletionTombstone): Boolean {
        val accepted = GlobalAgentRepository(appContext).enqueueAll(AgentMemoryCausalDeletionPolicy.retractionEvents(tombstone))
        if (accepted > 0) GlobalConversationEventBus.requestProcessing(appContext)
        return accepted > 0
    }

    private fun suppressionIndex() = AgentMemoryCausalDeletionPolicy.SuppressionIndex().apply { visitRecords(::add) }

    private fun records(items: List<AgentMemoryDeletionTombstone>): Map<String, String> = items.associate {
        "$RECORD_PREFIX${it.id}" to AgentMemoryCausalDeletionPolicy.encode(it).toString()
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
