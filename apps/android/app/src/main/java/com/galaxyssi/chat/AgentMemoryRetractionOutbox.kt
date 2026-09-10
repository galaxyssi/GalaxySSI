package com.galaxyssi.chat

/** Pending references commit with the deletion record; they never contain memory text. */
internal class AgentMemoryRetractionOutbox(
    private val database: AgentEncryptedDatabase,
    private val readRecord: (String) -> AgentMemoryDeletionTombstone,
    private val migrateLedger: () -> Unit
) {
    fun pending(limit: Int): List<GlobalConversationEvent> = synchronized(AgentMemoryStorage.lock) {
        require(limit in 1..250)
        bootstrap()
        val records = mutableMapOf<String, Map<String, GlobalConversationEvent>>()
        database.keysAfter(PREFIX, "", limit).map { key ->
            val eventId = key.removePrefix(PREFIX)
            val recordId = database.readString(key, "")
            check(recordId.matches(Regex("[a-f0-9]{64}"))) { "Memory retraction reference is unreadable" }
            val events = records.getOrPut(recordId) {
                AgentMemoryCausalDeletionPolicy.retractionEvents(readRecord(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX + recordId)).associateBy { it.id }
            }
            events[eventId] ?: error("Memory retraction identity mismatch")
        }
    }

    fun acknowledge(eventIds: Set<String>) = synchronized(AgentMemoryStorage.lock) {
        database.removeAll(eventIds.filter(::isRetraction).map { PREFIX + it })
    }

    fun count(): Int = synchronized(AgentMemoryStorage.lock) { database.countKeys(PREFIX) }

    fun requeueAll(): Int = synchronized(AgentMemoryStorage.lock) {
        migrateLedger()
        val updates = linkedMapOf<String, String>()
        var cursor = ""
        while (true) {
            val page = database.keysAfter(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX, cursor, 128)
            if (page.isEmpty()) break
            page.forEach { updates.putAll(references(readRecord(it))) }
            cursor = page.last()
        }
        database.mutateStrings(updates)
        updates.size
    }

    private fun bootstrap() {
        migrateLedger()
        if (database.contains(READY)) {
            check(database.readString(READY, "") == "1") { "Memory retraction migration marker is unreadable" }
            return
        }
        var cursor = if (database.contains(CURSOR)) database.readString(CURSOR, "") else ""
        check(!database.contains(CURSOR) || cursor.isNotEmpty()) { "Memory retraction migration cursor is unreadable" }
        check(cursor.isEmpty() || cursor.startsWith(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX)) {
            "Memory retraction migration cursor is unreadable"
        }
        while (true) {
            val page = database.keysAfter(EncryptedAgentMemoryDeletionIndex.RECORD_PREFIX, cursor, 128)
            val updates = linkedMapOf<String, String>()
            page.forEach { updates.putAll(references(readRecord(it))) }
            if (page.isEmpty()) {
                updates[READY] = "1"
                database.mutateStrings(updates, listOf(CURSOR))
                return
            }
            cursor = page.last()
            updates[CURSOR] = cursor
            database.mutateStrings(updates)
        }
    }

    companion object {
        internal const val PREFIX = "memory-retraction:v1:pending:"
        internal const val READY = "memory-retraction:v1:ready"
        internal const val CURSOR = "memory-retraction:v1:cursor"
        fun references(record: AgentMemoryDeletionTombstone): Map<String, String> =
            AgentMemoryCausalDeletionPolicy.retractionEvents(record).associate { PREFIX + it.id to record.id }
        fun isRetraction(eventId: String): Boolean = eventId.startsWith("memory-causal-deletion:")
    }
}
