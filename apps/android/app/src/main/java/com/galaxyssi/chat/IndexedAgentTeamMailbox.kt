package com.galaxyssi.chat

import java.security.MessageDigest

internal interface AgentTeamMailboxRows {
    fun read(key: String): String?
    fun page(prefix: String, after: String, limit: Int): List<String>
    fun pageBefore(prefix: String, before: String, limit: Int): List<String>
    /** The whole mutation succeeds or no rows change. */
    fun mutate(values: Map<String, String>, removeKeys: Collection<String> = emptyList())
}

/** Lossless run history and a separate pending index; normal writes never load the whole mailbox. */
internal class IndexedAgentTeamMailbox(private val rows: AgentTeamMailboxRows) : AgentTeamMailbox {
    override fun append(message: AgentTeamMessageEnvelope) = appendAll(listOf(message)).single()

    override fun appendAll(messages: List<AgentTeamMessageEnvelope>): List<AgentTeamMessageEnvelope> = synchronized(LOCK) {
        val validated = messages.map { it.validated() }
        if (validated.isEmpty()) return@synchronized emptyList()
        migrate()
        val writes = linkedMapOf<String, String>()
        val appended = validated.map { message ->
            val existing = writes[idKey(message.messageId)] ?: rows.read(idKey(message.messageId))
            if (existing != null) {
                readMessage(existing, writes).also { check(it.messageId == message.messageId) { "Team mailbox identity mismatch" } }
            } else {
                val counter = runPrefix(message.supervisorRunId) + "sequence"
                val previous = writes[counter] ?: rows.read(counter)
                check(previous != null || rows.page(runPrefix(message.supervisorRunId), "", 1).isEmpty()) {
                    "Team mailbox sequence counter is missing"
                }
                val last = previous?.toLongOrNull() ?: if (previous == null) 0L else error("Invalid team mailbox sequence")
                check(last in 0 until Long.MAX_VALUE) { "Team mailbox sequence is exhausted or invalid" }
                message.copy(sequence = last + 1).also { stored ->
                    check(rows.read(messageKey(stored)) == null) { "Team mailbox sequence already exists" }
                    writeMessage(stored, writes)
                    writes[counter] = stored.sequence.toString()
                }
            }
        }
        rows.mutate(writes)
        appended
    }

    override fun messages(supervisorRunId: String, instanceId: String, afterSequence: Long): List<AgentTeamMessageEnvelope> = synchronized(LOCK) {
        migrate()
        val prefix = runPrefix(supervisorRunId) + "message/"
        val after = if (afterSequence > 0L) prefix + sequenceKey(afterSequence) else ""
        keys(prefix, after).map { key ->
            readMessage(key).also { check(it.supervisorRunId == supervisorRunId) { "Team mailbox run mismatch" } }
        }.filter { instanceId.isBlank() || it.isBroadcast || it.toInstanceId == instanceId }.toList()
    }

    override fun pendingMessages(supervisorRunId: String, instanceId: String): List<AgentTeamMessageEnvelope> = synchronized(LOCK) {
        migrate()
        val run = runPrefix(supervisorRunId)
        val prefixes = if (instanceId.isBlank()) listOf(run + "pending/") else listOf(
            run + "recipient/${digest(instanceId)}/", run + "recipient/${digest("")}/")
        prefixes.asSequence().flatMap { keys(it) }.map { index ->
            val key = requireNotNull(rows.read(index)) { "Team mailbox pending index is unreadable" }
            readMessage(key).also { message ->
                check(message.supervisorRunId == supervisorRunId && message.state == AgentTeamMessageState.PENDING &&
                    (instanceId.isBlank() || message.isBroadcast || message.toInstanceId == instanceId)) { "Team mailbox pending index mismatch" }
                check(index in pendingKeys(message)) { "Team mailbox pending sequence mismatch" }
            }
        }.sortedBy { it.sequence }.toList()
    }

    override fun recentMessages(supervisorRunId: String, limit: Int): List<AgentTeamMessageEnvelope> = synchronized(LOCK) {
        require(limit in 1..PAGE_SIZE)
        migrate()
        val prefix = runPrefix(supervisorRunId) + "message/"
        var before = ""
        val recent = mutableListOf<AgentTeamMessageEnvelope>()
        while (recent.size < limit) {
            val remaining = limit - recent.size
            val page = rows.pageBefore(prefix, before, remaining)
            if (page.isEmpty()) break
            check(page.size <= remaining) { "Team mailbox reverse page exceeds requested size" }
            page.forEach { key ->
                check(key.startsWith(prefix) && (before.isEmpty() || key < before)) {
                    "Team mailbox reverse pagination did not advance"
                }
                recent += readMessage(key).also {
                    check(it.supervisorRunId == supervisorRunId) { "Team mailbox run mismatch" }
                }
                before = key
            }
        }
        recent.asReversed().toList()
    }

    override fun markDelivered(messageId: String, atMillis: Long) = update(messageId) { current ->
        if (current.state == AgentTeamMessageState.ACKNOWLEDGED) current else current.copy(
            state = AgentTeamMessageState.DELIVERED,
            deliveredAtMillis = maxOf(current.deliveredAtMillis, current.createdAtMillis, atMillis))
    }

    override fun acknowledge(messageId: String, atMillis: Long) = update(messageId) { current ->
        val at = maxOf(current.acknowledgedAtMillis, current.deliveredAtMillis, current.createdAtMillis, atMillis)
        current.copy(state = AgentTeamMessageState.ACKNOWLEDGED,
            deliveredAtMillis = current.deliveredAtMillis.takeIf { it > 0L } ?: at, acknowledgedAtMillis = at)
    }

    override fun clear(supervisorRunId: String) = synchronized(LOCK) {
        migrate()
        val prefix = if (supervisorRunId.isBlank()) PREFIX else runPrefix(supervisorRunId)
        val removals = keys(prefix).toMutableSet()
        if (supervisorRunId.isNotBlank()) {
            keys(prefix + "message/").forEach { key ->
                val message = readMessage(key)
                check(message.supervisorRunId == supervisorRunId) { "Team mailbox clear run mismatch" }
                val id = idKey(message.messageId)
                check(rows.read(id) == key) { "Team mailbox identity index mismatch" }
                removals += id
            }
        }
        rows.mutate(mapOf(META to SCHEMA), removals)
    }

    private fun update(id: String, change: (AgentTeamMessageEnvelope) -> AgentTeamMessageEnvelope): AgentTeamMessageEnvelope? = synchronized(LOCK) {
        migrate()
        val key = rows.read(idKey(id)) ?: return@synchronized null
        val current = readMessage(key)
        check(current.messageId == id) { "Team mailbox identity mismatch" }
        val updated = change(current)
        if (updated != current) rows.mutate(mapOf(key to encode(updated)), pendingKeys(current))
        updated
    }

    private fun readMessage(key: String, writes: Map<String, String> = emptyMap()): AgentTeamMessageEnvelope {
        check(key.startsWith(PREFIX)) { "Invalid team mailbox row reference" }
        val raw = requireNotNull(writes[key] ?: rows.read(key)) { "Team mailbox record is missing" }
        val message = AgentTeamMessageCodec.decodeStrict(raw).single()
        check(message.sequence > 0L && messageKey(message) == key) { "Team mailbox row identity mismatch" }
        return message
    }

    private fun writeMessage(message: AgentTeamMessageEnvelope, writes: MutableMap<String, String>) {
        val key = messageKey(message)
        writes[key] = encode(message)
        writes[idKey(message.messageId)] = key
        if (message.state == AgentTeamMessageState.PENDING) pendingKeys(message).forEach { writes[it] = key }
    }

    private fun migrate() {
        val schema = rows.read(META)
        if (schema == SCHEMA) return
        check(schema == null && rows.page(PREFIX, "", 1).isEmpty()) { "Unknown or incomplete team mailbox schema" }
        val legacy = rows.read(LEGACY)
        val messages = legacy?.let(AgentTeamMessageCodec::decodeStrict).orEmpty()
        val writes = linkedMapOf<String, String>()
        val sequences = mutableMapOf<String, Long>()
        val identities = hashSetOf<String>()
        messages.forEach { message ->
            check(identities.add(message.messageId)) { "Duplicate identity in legacy team mailbox" }
            val previous = sequences[message.supervisorRunId] ?: 0L
            check(previous < Long.MAX_VALUE) { "Legacy team mailbox sequence is exhausted" }
            val sequence = message.sequence.takeIf { it > previous } ?: previous + 1L
            writeMessage(message.copy(sequence = sequence), writes)
            sequences[message.supervisorRunId] = sequence
        }
        sequences.forEach { (run, sequence) -> writes[runPrefix(run) + "sequence"] = sequence.toString() }
        writes[META] = SCHEMA
        // Removing the legacy snapshot is atomic with all rows, indexes and the schema marker.
        rows.mutate(writes, if (legacy == null) emptyList() else listOf(LEGACY))
    }

    private fun keys(prefix: String, after: String = ""): Sequence<String> = sequence {
        var cursor = after
        while (true) {
            val page = rows.page(prefix, cursor, PAGE_SIZE)
            if (page.isEmpty()) break
            page.forEach { key ->
                check(key.startsWith(prefix) && key > cursor) { "Team mailbox pagination did not advance" }
                yield(key)
                cursor = key
            }
        }
    }

    private fun pendingKeys(message: AgentTeamMessageEnvelope): List<String> {
        val run = runPrefix(message.supervisorRunId)
        val sequence = sequenceKey(message.sequence)
        return listOf(run + "pending/$sequence", run + "recipient/${digest(message.toInstanceId)}/$sequence")
    }

    private fun messageKey(message: AgentTeamMessageEnvelope) = runPrefix(message.supervisorRunId) + "message/" + sequenceKey(message.sequence)
    private fun encode(message: AgentTeamMessageEnvelope) = AgentTeamMessageCodec.encode(listOf(message)).toString()

    private companion object {
        // All live runtimes and result finalizers share this lock, including migration and receipts.
        val LOCK = Any()
        const val PREFIX = "mailbox.v2/"
        const val META = PREFIX + "schema"
        const val SCHEMA = "2"
        const val LEGACY = "messages"
        const val PAGE_SIZE = 256
        fun digest(value: String): String = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
        fun runPrefix(run: String) = PREFIX + "run/${digest(run)}/"
        fun idKey(id: String) = PREFIX + "id/${digest(id)}"
        fun sequenceKey(sequence: Long) = sequence.toString().padStart(19, '0')
    }
}
