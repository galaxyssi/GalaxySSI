package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray

/** Identity indexes contain only opaque identifiers; record bodies and index values are encrypted. */
internal class AgentManagedResponseRows(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    fun migrate() {
        if (!database.contains(LEGACY_RECORDS)) return
        val raw = database.readString(LEGACY_RECORDS, "")
        val array = JSONArray(raw)
        val decoded = AgentManagedResponseCodec.decode(raw)
        check(array.length() == decoded.size) { "Managed response migration contains unreadable records" }
        check(decoded.distinctBy { it.ownerRunId }.size == decoded.size) { "Managed response migration contains duplicate owners" }
        val writes = linkedMapOf<String, String>()
        decoded.forEach { record ->
            val existing = find(record.ownerRunId)
            check(existing == null || existing == record) { "Managed response migration identity conflict" }
            writes.putAll(encoded(record))
        }
        // Row bodies, lookup indexes and legacy removal commit in one existing SQLite transaction.
        database.mutateStrings(writes, listOf(LEGACY_RECORDS))
    }

    fun find(owner: String): AgentManagedResponseRecord? {
        val raw = database.readString(key(owner), "")
        if (raw.isBlank()) return null
        val result = AgentManagedResponseCodec.decode(raw).singleOrNull()
            ?: error("Managed response row could not be decoded")
        check(result.ownerRunId == owner) { "Managed response row identity mismatch" }
        return result
    }

    fun forSource(source: Long): List<AgentManagedResponseRecord> = indexed("source:$source:")
    fun forSupervisor(run: String): List<AgentManagedResponseRecord> = indexed("supervisor:${hash(run)}:")
    fun forState(state: AgentManagedResponseState): List<AgentManagedResponseRecord> = indexed("state:${state.name}:")

    fun put(record: AgentManagedResponseRecord, previous: AgentManagedResponseRecord? = null) {
        val writes = encoded(record)
        database.mutateStrings(writes, previous?.let(::indexKeys).orEmpty().filterNot(writes::containsKey))
    }

    fun remove(record: AgentManagedResponseRecord) {
        database.mutateStrings(emptyMap(), indexKeys(record) + key(record.ownerRunId))
    }

    fun compact() {
        val applied = forState(AgentManagedResponseState.APPLIED)
        val retained = AgentManagedResponseRetentionPolicy.retain(applied).mapTo(hashSetOf()) { it.ownerRunId }
        val expired = applied.filterNot { it.ownerRunId in retained }
        if (expired.isNotEmpty()) database.mutateStrings(emptyMap(), expired.flatMap {
            indexKeys(it) + key(it.ownerRunId)
        })
    }

    fun clear() = database.clear()

    private fun indexed(prefix: String): List<AgentManagedResponseRecord> {
        val lookupKeys = database.keys(prefix)
        val indexes = database.readStrings(lookupKeys)
        check(indexes.size == lookupKeys.size) { "Managed response index could not be decoded" }
        val references = indexes.values.distinct()
        val bodies = database.readStrings(references)
        check(bodies.size == references.size) { "Managed response index references a missing or unreadable row" }
        return bodies.map { (rowKey, raw) ->
            val record = AgentManagedResponseCodec.decode(raw).singleOrNull()
                ?: error("Indexed managed response row could not be decoded")
            check(rowKey == key(record.ownerRunId)) { "Indexed managed response identity mismatch" }
            check(indexKeys(record).any { it.startsWith(prefix) }) { "Managed response index state mismatch" }
            record
        }
    }

    private fun encoded(record: AgentManagedResponseRecord): Map<String, String> = buildMap {
        val recordKey = key(record.ownerRunId)
        put(recordKey, AgentManagedResponseCodec.encode(listOf(record)).toString())
        indexKeys(record).forEach { put(it, recordKey) }
    }

    private fun indexKeys(record: AgentManagedResponseRecord): List<String> {
        val owner = hash(record.ownerRunId)
        return listOf("source:${record.sourceMessageId}:$owner", "supervisor:${hash(record.supervisorRunId)}:$owner",
            "state:${record.state.name}:$owner")
    }

    private fun key(owner: String) = "record:${hash(owner)}"
    private fun hash(value: String) = AgentNativeJsonCodec.sha256(value)

    companion object {
        const val DATABASE = "galaxyssi_managed_connector_responses_v2"
        const val LEGACY_RECORDS = "records"
    }
}
