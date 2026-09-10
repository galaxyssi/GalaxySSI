package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/** Row payloads, ordering, counts and revisions are encrypted in the existing memory database. */
internal class AgentPersonalMemoryRows(private val database: AgentEncryptedDatabase) {
    fun read(): List<JSONObject> = synchronized(AgentMemoryStorage.lock) {
        val metadata = metadata()
        val rows = mutableListOf<Pair<Long, JSONObject>>()
        visit { rowKey, raw ->
            val row = JSONObject(raw)
            val item = row.getJSONObject("item")
            check(rowKey == key(item.getString("id"))) { "Personal memory row identity mismatch" }
            check(item.getString("value").isNotBlank()) { "Personal memory row is empty" }
            rows.add(row.getLong("position") to item)
        }
        check(rows.size == metadata.getInt("count")) { "Personal memory row count mismatch" }
        rows.sortBy { it.first }
        var previous = -1L
        rows.forEach { row ->
            check(row.first > previous) { "Personal memory ordering is invalid" }
            previous = row.first
        }
        rows.map { it.second }
    }

    fun activeCount(): Int = synchronized(AgentMemoryStorage.lock) { metadata().getInt("active_count") }

    fun export(): JSONArray = JSONArray().apply { read().forEach { put(it) } }

    fun replace(items: Sequence<JSONObject>, additional: Map<String, String> = emptyMap()) =
        synchronized(AgentMemoryStorage.lock) {
            metadata()
            commit(normalize(items), additional)
        }

    private fun metadata(): JSONObject {
        if (!database.contains(META)) {
            // Keep the legacy value until rows and metadata have committed together.
            val legacy = if (database.contains(AgentMemoryStorage.ITEMS)) {
                JSONArray(database.readString(AgentMemoryStorage.ITEMS, ""))
            } else JSONArray()
            check(database.countKeys(PREFIX) == 0) { "Personal memory migration metadata is missing" }
            commit(normalize((0 until legacy.length()).asSequence().map(legacy::getJSONObject)), emptyMap())
        }
        val result = JSONObject(database.readString(META, ""))
        check(result.getInt("schema") == 3 && result.getInt("count") >= 0 &&
            result.getInt("active_count") in 0..result.getInt("count") &&
            result.getString("revision").isNotBlank()) { "Personal memory metadata is invalid" }
        return result
    }

    private fun normalize(items: Sequence<JSONObject>): Sequence<JSONObject> {
        val decoded = items.map { AgentMemoryItemCodec.decode(it) ?: error("Personal memory item is invalid") }.toList()
        return AgentMemoryIdentity.normalizeConflicts(decoded).asSequence().map(AgentMemoryItemCodec::encode)
    }

    private fun commit(items: Sequence<JSONObject>, additional: Map<String, String>) {
        require(additional.keys.none { it == META || it == AgentMemoryStorage.ITEMS || it.startsWith(PREFIX) })
        val seen = hashSetOf<String>()
        var active = 0
        var previousPosition = -1L
        val writes = sequence {
            items.forEach { item ->
                val id = item.getString("id")
                require(id.isNotBlank() && item.getString("value").isNotBlank()) { "Personal memory identity or value is empty" }
                val rowKey = key(id)
                require(seen.add(rowKey)) { "Duplicate personal memory identity" }
                if (item.optString("status", "ACTIVE") == "ACTIVE") active++
                val old = if (database.contains(rowKey)) JSONObject(database.readString(rowKey, "")) else null
                val oldPosition = old?.getLong("position") ?: -1L
                check(previousPosition < Long.MAX_VALUE) { "Personal memory order needs compaction" }
                val position = if (oldPosition > previousPosition) oldPosition else previousPosition + 1
                previousPosition = position
                yield(rowKey to JSONObject().put("position", position).put("item", item).toString())
            }
            additional.forEach { (key, value) -> yield(key to value) }
            yield(META to JSONObject().put("schema", 3).put("count", seen.size).put("active_count", active)
                .put("revision", UUID.randomUUID().toString()).toString())
        }
        database.mutateStreaming(writes) {
            sequence {
                var cursor = ""
                while (true) {
                    val page = database.keysAfter(PREFIX, cursor, 128)
                    if (page.isEmpty()) break
                    page.filterNot { it in seen }.forEach { yield(it) }
                    cursor = page.last()
                }
                yield(AgentMemoryStorage.ITEMS)
            }
        }
    }

    private fun visit(block: (String, String) -> Unit) {
        var cursor = ""
        while (true) {
            val page = database.keysAfter(PREFIX, cursor, 128)
            if (page.isEmpty()) return
            val values = database.readStrings(page)
            page.forEach { block(it, values[it] ?: error("Personal memory row cannot be decrypted")) }
            cursor = page.last()
        }
    }

    companion object {
        internal const val PREFIX = "personal-memory:v3:row:"
        internal const val META = "personal-memory:v3:metadata"
        internal fun key(id: String): String = PREFIX + MessageDigest.getInstance("SHA-256")
            .digest(id.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
