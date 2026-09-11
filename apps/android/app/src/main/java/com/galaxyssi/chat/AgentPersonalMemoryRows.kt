package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/** Row payloads, ordering, counts and revisions are encrypted in the existing memory database. */
internal class AgentPersonalMemoryRows(private val database: AgentEncryptedDatabase) {
    private val browseIndex = AgentMemoryBrowseIndex(database)
    fun browse(request: AgentMemoryBrowseRequest): AgentMemoryBrowsePage = synchronized(AgentMemoryStorage.lock) {
        metadata()
        AgentMemoryBrowseQuery(database).page(request)
    }
    fun browseCounts(kinds: Set<AgentMemoryKind>): AgentMemoryBrowseCounts = synchronized(AgentMemoryStorage.lock) {
        metadata()
        AgentMemoryBrowseQuery(database).counts(kinds)
    }
    fun browseKindCounts(): Map<AgentMemoryKind, Long> = synchronized(AgentMemoryStorage.lock) {
        metadata()
        AgentMemoryBrowseQuery(database).kindCounts()
    }
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

    fun candidates(next: AgentMemoryItem): List<AgentMemoryItem> = synchronized(AgentMemoryStorage.lock) {
        val meta = lookupMetadata()
        val prefix = lookupPrefix(meta.getString("lookup_generation"), next)
        val found = mutableListOf<Pair<Long, AgentMemoryItem>>()
        var cursor = ""
        while (true) {
            val page = database.keysAfter(prefix, cursor, 128)
            if (page.isEmpty()) break
            page.forEach { lookupKey ->
                val id = database.readString(lookupKey, "")
                val row = readRow(id) ?: error("Personal memory lookup references a missing row")
                val item = AgentMemoryItemCodec.decode(row.getJSONObject("item")) ?: error("Invalid memory lookup row")
                check(lookupKey == prefix + key(id).removePrefix(PREFIX) &&
                    item.status != AgentMemoryStatus.SUPERSEDED && AgentMemoryIdentity.sameKey(item, next) &&
                    (next.key.isNotBlank() || AgentMemoryLookupIdentity.foldValue(item.value) == AgentMemoryLookupIdentity.foldValue(next.value))) {
                    "Personal memory lookup identity mismatch"
                }
                found.add(row.getLong("position") to item)
            }
            cursor = page.last()
        }
        found.sortedBy { it.first }.map { it.second }
    }

    fun applyRemember(change: AgentMemoryRememberMutation) = synchronized(AgentMemoryStorage.lock) {
        val meta = lookupMetadata()
        val before = change.before.associateBy { it.id }
        require(before.size == change.before.size && change.after.map { it.id }.toSet().size == change.after.size)
        require(change.after.map { it.id }.containsAll(before.keys))
        require(change.after.all { it.id.isNotBlank() && it.value.isNotBlank() })
        val oldRows = change.after.associate { item ->
            val row = readRow(item.id)
            check(if (item.id in before) row != null && AgentMemoryItemCodec.decode(row.getJSONObject("item")) == before[item.id] else row == null) {
                "Personal memory changed or a new memory ID already exists"
            }
            before[item.id]?.let { previous ->
                require(previous.status != AgentMemoryStatus.SUPERSEDED &&
                    AgentMemoryLookupIdentity.material(previous) == AgentMemoryLookupIdentity.material(item))
            }
            item.id to row
        }
        var position = meta.getLong("next_position")
        val generation = meta.getString("lookup_generation")
        val writes = sequence {
            change.after.forEach { item ->
                val row = oldRows[item.id] ?: JSONObject().put("position", position).also { position = Math.addExact(position, 1) }
                val canonical = AgentMemoryItemCodec.decode(AgentMemoryItemCodec.encode(item)) ?: error("Invalid memory mutation payload")
                check(AgentMemoryLookupIdentity.material(canonical) == AgentMemoryLookupIdentity.material(item))
                row.put("item", AgentMemoryItemCodec.encode(canonical))
                yield(key(item.id) to row.toString())
                check(item.status != AgentMemoryStatus.SUPERSEDED)
                if (oldRows[item.id] == null) yield(lookupPrefix(generation, item) + key(item.id).removePrefix(PREFIX) to item.id)
            }
            meta.put("count", Math.addExact(meta.getInt("count"), change.after.size - before.size))
                .put("active_count", Math.addExact(meta.getInt("active_count"),
                    change.after.count { it.status == AgentMemoryStatus.ACTIVE } - before.values.count { it.status == AgentMemoryStatus.ACTIVE }))
                .put("next_position", position).put("revision", UUID.randomUUID().toString())
            yield(META to meta.toString())
        }
        database.mutateStreaming(writes, browseIndex.observer()) { emptySequence() }
    }

    private fun lookupMetadata(): JSONObject {
        val meta = metadata()
        if (!meta.has("lookup_generation")) {
            val generation = UUID.randomUUID().toString()
            var count = 0
            var active = 0
            var nextPosition = 0L
            val writes = sequence {
                var cursor = ""
                while (true) {
                    val page = database.keysAfter(PREFIX, cursor, 128)
                    if (page.isEmpty()) break
                    val values = database.readStrings(page)
                    page.forEach { rowKey ->
                        val row = JSONObject(values[rowKey] ?: error("Memory lookup migration cannot decrypt row"))
                        val item = AgentMemoryItemCodec.decode(row.getJSONObject("item")) ?: error("Invalid migration row")
                        check(rowKey == key(item.id) && item.value.isNotBlank() && row.getLong("position") >= 0)
                        count = Math.addExact(count, 1)
                        if (item.status == AgentMemoryStatus.ACTIVE) active++
                        nextPosition = maxOf(nextPosition, Math.addExact(row.getLong("position"), 1))
                        if (item.status != AgentMemoryStatus.SUPERSEDED) {
                            yield(lookupPrefix(generation, item) + rowKey.removePrefix(PREFIX) to item.id)
                        }
                    }
                    cursor = page.last()
                }
                check(count == meta.getInt("count") && active == meta.getInt("active_count")) { "Memory lookup migration count mismatch" }
                addLookupMetadata(meta, generation, nextPosition)
                yield(META to meta.toString())
            }
            database.mutateStreaming(writes) { obsoleteLookups(generation) }
        }
        validateLookupMetadata(meta)
        return meta
    }

    fun find(id: String): AgentMemoryItem? = synchronized(AgentMemoryStorage.lock) {
        if (id.isBlank()) return@synchronized null
        metadata()
        readRow(id)?.getJSONObject("item")?.let {
            AgentMemoryItemCodec.decode(it) ?: error("Personal memory row cannot be decoded")
        }
    }

    fun updateFlags(id: String, important: Boolean? = null, privateMemory: Boolean? = null):
        Pair<AgentMemoryItem, AgentMemoryItem>? = synchronized(AgentMemoryStorage.lock) {
        if (id.isBlank()) return@synchronized null
        require(important != null || privateMemory != null)
        val meta = metadata()
        val row = readRow(id) ?: return@synchronized null
        val before = AgentMemoryItemCodec.decode(row.getJSONObject("item"))
            ?: error("Personal memory row cannot be decoded")
        if (important != null && before.status != AgentMemoryStatus.ACTIVE) return@synchronized null
        val after = before.copy(important = important ?: before.important,
            privateMemory = privateMemory ?: before.privateMemory)
        if (before != after) {
            row.put("item", AgentMemoryItemCodec.encode(after))
            meta.put("revision", UUID.randomUUID().toString())
            // The flag diff is known; do not decrypt both old rows again to detect unchanged writes.
            database.mutateStrings(mapOf(key(id) to row.toString(), META to meta.toString()), onMutation = browseIndex.observer())
        }
        before to after
    }

    private fun readRow(id: String): JSONObject? {
        val rowKey = key(id)
        if (!database.contains(rowKey)) return null
        val row = JSONObject(database.readString(rowKey, ""))
        val item = row.getJSONObject("item")
        check(item.getString("id") == id && item.getString("value").isNotBlank() && row.getLong("position") >= 0) {
            "Personal memory row identity or payload is invalid"
        }
        return row
    }

    fun export(): JSONArray = JSONArray().apply { read().forEach { put(it) } }

    internal fun exportRows(visitRow: (String, JSONObject) -> Unit): Pair<Long, Long> = synchronized(AgentMemoryStorage.lock) {
        val meta = metadata()
        var count = 0L
        var active = 0L
        visit { rowKey, value ->
            val row = JSONObject(value)
            val item = row.getJSONObject("item")
            check(rowKey == key(item.getString("id")) && row.getLong("position") >= 0 && item.getString("value").isNotBlank()) {
                "Invalid personal memory backup source"
            }
            if (item.optString("status", "ACTIVE") == "ACTIVE") active = Math.addExact(active, 1)
            visitRow(rowKey, row)
            count = Math.addExact(count, 1)
        }
        check(count == meta.getLong("count") && active == meta.getLong("active_count")) { "Memory backup source count mismatch" }
        count to active
    }

    fun replace(items: Sequence<JSONObject>, additional: Map<String, String> = emptyMap()) =
        synchronized(AgentMemoryStorage.lock) {
            metadata()
            commit(normalize(items), additional)
        }

    internal fun replacePrepared(items: Sequence<JSONObject>, additional: Sequence<Pair<String, String>>) =
        synchronized(AgentMemoryStorage.lock) { metadata(); commitStream(items, additional) }

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
        commitStream(items, additional.asSequence().map { it.key to it.value })
    }

    private fun commitStream(items: Sequence<JSONObject>, additional: Sequence<Pair<String, String>>) = MemoryReplacementKeys.transaction(database) { seen ->
        val previousMeta = if (database.contains(META)) JSONObject(database.readString(META, "")) else null
        val keepLookup = previousMeta?.has("lookup_generation") == true
        if (keepLookup) validateLookupMetadata(previousMeta!!)
        val generation = if (keepLookup) previousMeta!!.getString("lookup_generation") else UUID.randomUUID().toString()
        var active = 0L
        var previousPosition = -1L
        val writes = sequence {
            items.forEach { item ->
                val id = item.getString("id")
                require(id.isNotBlank() && item.getString("value").isNotBlank()) { "Personal memory identity or value is empty" }
                val rowKey = key(id)
                seen.add(rowKey)
                if (item.optString("status", "ACTIVE") == "ACTIVE") active = Math.addExact(active, 1)
                val old = if (database.contains(rowKey)) JSONObject(database.readString(rowKey, "")) else null
                val oldPosition = old?.getLong("position") ?: -1L
                check(previousPosition < Long.MAX_VALUE) { "Personal memory order needs compaction" }
                val position = if (oldPosition > previousPosition) oldPosition else previousPosition + 1
                previousPosition = position
                yield(rowKey to JSONObject().put("position", position).put("item", item).toString())
                val decoded = AgentMemoryItemCodec.decode(item) ?: error("Invalid memory lookup source")
                val oldItem = old?.getJSONObject("item")?.let(AgentMemoryItemCodec::decode)
                check(old == null || (oldItem != null && oldItem.id == id)) { "Cannot replace invalid memory lookup source" }
                val oldLive = oldItem != null && oldItem.status != AgentMemoryStatus.SUPERSEDED
                val newLive = decoded.status != AgentMemoryStatus.SUPERSEDED
                val sameLookup = keepLookup && oldLive && newLive &&
                    AgentMemoryLookupIdentity.material(oldItem!!) == AgentMemoryLookupIdentity.material(decoded)
                if (newLive && !sameLookup) {
                    yield(lookupPrefix(generation, decoded) + rowKey.removePrefix(PREFIX) to id)
                }
                if (keepLookup && oldLive && !sameLookup) {
                    seen.removeLookup(lookupPrefix(generation, oldItem!!) + rowKey.removePrefix(PREFIX))
                }
            }
            additional.forEach { (key, value) ->
                require(key != META && key != AgentMemoryStorage.ITEMS && key != AgentMemoryBrowseIndex.MARKER &&
                    !key.startsWith(PREFIX) && !key.startsWith(LOOKUP_PREFIX)) { "Invalid additional memory mutation key" }
                yield(key to value)
            }
            val meta = JSONObject().put("schema", 3).put("count", seen.size).put("active_count", active)
                .put("revision", UUID.randomUUID().toString())
            addLookupMetadata(meta, generation, Math.addExact(previousPosition, 1))
            yield(META to meta.toString())
        }
        database.mutateStreaming(writes, browseIndex.observer()) {
            sequence {
                var cursor = ""
                while (true) {
                    val page = database.keysAfter(PREFIX, cursor, 128)
                    if (page.isEmpty()) break
                    page.filterNot(seen::contains).forEach { rowKey ->
                        if (keepLookup) {
                            val old = JSONObject(database.readString(rowKey, "")).getJSONObject("item")
                            val item = AgentMemoryItemCodec.decode(old) ?: error("Cannot remove invalid memory lookup")
                            check(key(item.id) == rowKey)
                            if (item.status != AgentMemoryStatus.SUPERSEDED) yield(lookupPrefix(generation, item) + rowKey.removePrefix(PREFIX))
                        }
                        yield(rowKey)
                    }
                    cursor = page.last()
                }
                yield(AgentMemoryStorage.ITEMS)
                if (keepLookup) yieldAll(seen.removedLookups()) else yieldAll(obsoleteLookups(generation))
            }
        }
    }

    private fun lookupPrefix(generation: String, item: AgentMemoryItem): String =
        "$LOOKUP_PREFIX$generation:${AgentMemoryIndexKey.token(AgentMemoryLookupIdentity.material(item))}:"

    private fun addLookupMetadata(meta: JSONObject, generation: String, nextPosition: Long) {
        meta.put("lookup_version", 1).put("lookup_generation", generation)
            .put("lookup_key_stamp", AgentMemoryIndexKey.stamp()).put("next_position", nextPosition)
    }

    private fun validateLookupMetadata(meta: JSONObject) {
        check(meta.getInt("lookup_version") == 1 && meta.getString("lookup_generation").isNotBlank() &&
            meta.getLong("next_position") >= 0 && meta.getString("lookup_key_stamp") == AgentMemoryIndexKey.stamp()) {
            "Personal memory lookup metadata or key is invalid"
        }
    }

    private fun obsoleteLookups(generation: String): Sequence<String> = sequence {
        var cursor = ""
        while (true) {
            val page = database.keysAfter(LOOKUP_PREFIX, cursor, 128)
            if (page.isEmpty()) break
            page.filterNot { it.startsWith("$LOOKUP_PREFIX$generation:") }.forEach { yield(it) }
            cursor = page.last()
        }
    }

    private fun visit(block: (String, String) -> Unit) {
        var cursor = ""
        while (true) {
            val page = database.keysAfter(PREFIX, cursor, 128)
            if (page.isEmpty()) return
            page.forEach { block(it, database.readString(it, "").ifEmpty { error("Personal memory row cannot be decrypted") }) }
            cursor = page.last()
        }
    }

    companion object {
        internal const val PREFIX = "personal-memory:v3:row:"
        internal const val META = "personal-memory:v3:metadata"
        internal const val LOOKUP_PREFIX = "personal-memory:lookup:v1:"
        internal fun key(id: String): String = PREFIX + MessageDigest.getInstance("SHA-256")
            .digest(id.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
