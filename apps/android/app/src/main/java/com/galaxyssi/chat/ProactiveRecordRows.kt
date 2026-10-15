package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Callers hold their store lock. Migration and replacement are atomic, with no count-based eviction. */
internal class ProactiveRecordRows(
    private val database: AgentEncryptedDatabase,
    private val prefix: String,
    private val legacyKey: String,
    private val identity: (JSONObject) -> String,
    private val legacyObject: Boolean = false
) {
    fun migrate() {
        if (!database.contains(legacyKey)) return
        val raw = database.readString(legacyKey, "")
        check(raw.isNotEmpty()) { "Unreadable legacy proactive records" }
        val records = if (legacyObject) {
            val root = JSONObject(raw)
            root.keys().asSequence().map { it to root.getJSONObject(it) }
        } else {
            val array = JSONArray(raw)
            (0 until array.length()).asSequence().map { array.getJSONObject(it) }.map { identity(it) to it }
        }
        database.mutateStreaming(records.map { (id, value) ->
            require(id.isNotBlank()) { "Missing proactive record identity" }
            prefix + id to value.toString()
        }, removals = { sequenceOf(legacyKey) })
    }

    fun get(id: String): JSONObject? {
        migrate()
        val key = prefix + id
        if (!database.contains(key)) return null
        val value = database.readString(key, "")
        check(value.isNotEmpty()) { "Unreadable proactive record" }
        return JSONObject(value)
    }

    fun put(id: String, value: JSONObject) {
        migrate()
        database.writeString(prefix + id, value.toString())
    }

    fun all(): Sequence<JSONObject> = sequence {
        migrate()
        var cursor = ""
        while (true) {
            val keys = database.keysAfter(prefix, cursor, 128)
            if (keys.isEmpty()) break
            val values = database.readStrings(keys)
            keys.forEach { key -> yield(JSONObject(checkNotNull(values[key]) { "Unreadable proactive record" })) }
            cursor = keys.last()
        }
    }

}

internal class GlobalProactiveMessageStore(
    private val database: AgentEncryptedDatabase,
    private val encode: (GlobalProactiveMessage) -> JSONObject,
    private val decode: (JSONObject?) -> GlobalProactiveMessage?
) {
    private val rows = ProactiveRecordRows(database, PREFIX, "proactive_messages", { it.getString("id") })
    private val readIndex = ProactiveMessageReadIndex(database)

    fun previewReady() = readIndex.ready()
    fun preparePreview() { prepare() }
    fun counts(feedback: List<GlobalAgentFeedback>) = readIndex.counts(feedback)
    fun preview(state: AttentionReaderState, saved: Set<String>): List<GlobalProactiveMessage> =
        database.readStrings(readIndex.firstKeys(state, saved)).values.mapNotNull { decode(JSONObject(it)) }

    private fun prepare() {
        rows.migrate()
        readIndex.prepare(rows::all)
        if (database.contains(INDEX_READY)) return
        database.mutateStreaming(sequence {
            rows.all().forEach { record ->
                val message = checkNotNull(decode(record))
                if (message.sourceEventId.isNotBlank()) yield(eventKey(message.sourceEventId) to message.id)
            }
            yield(INDEX_READY to "1")
        }, removals = { emptySequence() })
    }

    fun all(): List<GlobalProactiveMessage> {
        prepare()
        return rows.all().map { checkNotNull(decode(it)) }.sortedBy { it.createdAtMillis }.toList()
    }

    fun get(id: String): GlobalProactiveMessage? { prepare(); return decode(rows.get(id)) }

    fun append(message: GlobalProactiveMessage): Boolean {
        prepare()
        if (database.contains(PREFIX + message.id) || message.sourceEventId.isNotBlank() &&
            database.contains(eventKey(message.sourceEventId))) return false
        put(message)
        return true
    }

    fun put(message: GlobalProactiveMessage) {
        prepare()
        database.mutateStrings(buildMap {
            put(PREFIX + message.id, encode(message).toString())
            if (message.sourceEventId.isNotBlank()) put(eventKey(message.sourceEventId), message.id)
        }, onMutation = readIndex::update)
    }

    fun replace(messages: List<GlobalProactiveMessage>) {
        prepare()
        val retained = buildMap {
            messages.forEach { message ->
                put(PREFIX + message.id, encode(message).toString())
                if (message.sourceEventId.isNotBlank()) put(eventKey(message.sourceEventId), message.id)
            }
        }
        database.mutateStreaming(retained.asSequence().map { it.key to it.value }, onMutation = readIndex::update, removals = {
            (database.keys(PREFIX) + database.keys(EVENT_PREFIX)).asSequence().filter { it !in retained }
        })
    }

    private fun eventKey(id: String) = EVENT_PREFIX + java.security.MessageDigest.getInstance("SHA-256")
        .digest(id.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    companion object {
        private const val PREFIX = "proactive_message_row:"
        private const val EVENT_PREFIX = "proactive_message_event:"
        private const val INDEX_READY = "proactive_message_index_v1"
    }
}
