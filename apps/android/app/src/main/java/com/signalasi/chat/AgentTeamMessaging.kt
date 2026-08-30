package com.signalasi.chat

import android.content.Context
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

enum class AgentTeamMessageKind {
    USER_DIRECTIVE,
    DELEGATION,
    PROGRESS,
    EVIDENCE,
    REVIEW,
    BLOCKED,
    RESULT,
    CONTROL
}

enum class AgentTeamMessageState { PENDING, DELIVERED, ACKNOWLEDGED }

data class AgentTeamMessageEnvelope(
    val messageId: String = UUID.randomUUID().toString(),
    val teamId: String,
    val conversationId: String,
    val supervisorRunId: String,
    val fromInstanceId: String,
    val toInstanceId: String = "",
    val kind: AgentTeamMessageKind,
    val text: String,
    val inReplyTo: String = "",
    val sequence: Long = 0L,
    val state: AgentTeamMessageState = AgentTeamMessageState.PENDING,
    val metadata: Map<String, String> = emptyMap(),
    val createdAtMillis: Long = System.currentTimeMillis(),
    val deliveredAtMillis: Long = 0L,
    val acknowledgedAtMillis: Long = 0L,
    val protocol: String = PROTOCOL
) {
    val isBroadcast: Boolean get() = toInstanceId.isBlank()

    fun validated(): AgentTeamMessageEnvelope = copy(
        messageId = requireId(messageId, "message"),
        teamId = requireId(teamId, "team"),
        conversationId = conversationId.trim().take(MAX_ID_CHARS),
        supervisorRunId = requireId(supervisorRunId, "Run"),
        fromInstanceId = requireId(fromInstanceId, "sender"),
        toInstanceId = toInstanceId.trim().take(MAX_ID_CHARS),
        text = text.trim().take(MAX_TEXT_CHARS),
        inReplyTo = inReplyTo.trim().take(MAX_ID_CHARS),
        metadata = metadata.entries.take(MAX_METADATA_ENTRIES).associate { (key, value) ->
            key.trim().take(MAX_METADATA_KEY_CHARS) to value.take(MAX_METADATA_VALUE_CHARS)
        }.filterKeys(String::isNotBlank),
        protocol = PROTOCOL
    ).also {
        require(it.conversationId.isNotBlank()) { "Conversation id must not be blank" }
        require(it.text.isNotBlank()) { "Team message must not be blank" }
        require(it.fromInstanceId != it.toInstanceId || it.toInstanceId.isBlank()) {
            "A direct team message must target another instance"
        }
    }

    companion object {
        const val PROTOCOL = "team.v1"
        const val MAX_ID_CHARS = 160
        const val MAX_TEXT_CHARS = 16_000
        private const val MAX_METADATA_ENTRIES = 24
        private const val MAX_METADATA_KEY_CHARS = 64
        private const val MAX_METADATA_VALUE_CHARS = 1_000

        private fun requireId(value: String, label: String): String = value.trim().take(MAX_ID_CHARS)
            .also { require(it.isNotBlank()) { "$label id must not be blank" } }
    }
}

interface AgentTeamMailbox {
    fun append(message: AgentTeamMessageEnvelope): AgentTeamMessageEnvelope
    fun messages(supervisorRunId: String, instanceId: String = "", afterSequence: Long = 0L): List<AgentTeamMessageEnvelope>
    fun markDelivered(messageId: String, atMillis: Long = System.currentTimeMillis()): AgentTeamMessageEnvelope?
    fun acknowledge(messageId: String, atMillis: Long = System.currentTimeMillis()): AgentTeamMessageEnvelope?
    fun clear(supervisorRunId: String = "")
}

class InMemoryAgentTeamMailbox(
    initialMessages: List<AgentTeamMessageEnvelope> = emptyList()
) : AgentTeamMailbox {
    private val records = mutableListOf<AgentTeamMessageEnvelope>()

    init {
        initialMessages.forEach { message ->
            val normalized = message.validated()
            if (records.none { it.messageId == normalized.messageId }) {
                val lastSequence = records.asSequence()
                    .filter { it.supervisorRunId == normalized.supervisorRunId }
                    .maxOfOrNull(AgentTeamMessageEnvelope::sequence) ?: 0L
                records += normalized.copy(
                    sequence = normalized.sequence.takeIf { it > lastSequence } ?: lastSequence + 1L
                )
            }
        }
    }

    @Synchronized
    override fun append(message: AgentTeamMessageEnvelope): AgentTeamMessageEnvelope {
        val normalized = message.validated()
        records.firstOrNull { it.messageId == normalized.messageId }?.let { return it }
        val nextSequence = (records.asSequence()
            .filter { it.supervisorRunId == normalized.supervisorRunId }
            .maxOfOrNull(AgentTeamMessageEnvelope::sequence) ?: 0L) + 1L
        return normalized.copy(sequence = nextSequence).also(records::add)
    }

    @Synchronized
    override fun messages(
        supervisorRunId: String,
        instanceId: String,
        afterSequence: Long
    ): List<AgentTeamMessageEnvelope> = records.filter { message ->
        message.supervisorRunId == supervisorRunId &&
            message.sequence > afterSequence &&
            (instanceId.isBlank() || message.isBroadcast || message.toInstanceId == instanceId)
    }.sortedBy(AgentTeamMessageEnvelope::sequence)

    @Synchronized
    override fun markDelivered(messageId: String, atMillis: Long): AgentTeamMessageEnvelope? =
        mutate(messageId) { current ->
            if (current.state == AgentTeamMessageState.ACKNOWLEDGED) current else current.copy(
                state = AgentTeamMessageState.DELIVERED,
                deliveredAtMillis = maxOf(
                    current.deliveredAtMillis,
                    current.createdAtMillis,
                    atMillis
                )
            )
        }

    @Synchronized
    override fun acknowledge(messageId: String, atMillis: Long): AgentTeamMessageEnvelope? =
        mutate(messageId) { current ->
            val acknowledgedAt = maxOf(
                current.acknowledgedAtMillis,
                current.deliveredAtMillis,
                current.createdAtMillis,
                atMillis
            )
            current.copy(
                state = AgentTeamMessageState.ACKNOWLEDGED,
                deliveredAtMillis = current.deliveredAtMillis.takeIf { it > 0L } ?: acknowledgedAt,
                acknowledgedAtMillis = acknowledgedAt
            )
        }

    @Synchronized
    override fun clear(supervisorRunId: String) {
        if (supervisorRunId.isBlank()) records.clear() else records.removeAll {
            it.supervisorRunId == supervisorRunId
        }
    }

    @Synchronized
    fun snapshot(): List<AgentTeamMessageEnvelope> = records.toList()

    private fun mutate(
        messageId: String,
        mutation: (AgentTeamMessageEnvelope) -> AgentTeamMessageEnvelope
    ): AgentTeamMessageEnvelope? {
        val index = records.indexOfFirst { it.messageId == messageId }
        if (index < 0) return null
        return mutation(records[index]).also { records[index] = it }
    }
}

class EncryptedAgentTeamMailbox(context: Context) : AgentTeamMailbox {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    override fun append(message: AgentTeamMessageEnvelope): AgentTeamMessageEnvelope {
        val delegate = delegate()
        val appended = delegate.append(message)
        save(delegate.snapshot())
        return appended
    }

    @Synchronized
    override fun messages(
        supervisorRunId: String,
        instanceId: String,
        afterSequence: Long
    ): List<AgentTeamMessageEnvelope> = delegate().messages(supervisorRunId, instanceId, afterSequence)

    @Synchronized
    override fun markDelivered(messageId: String, atMillis: Long): AgentTeamMessageEnvelope? {
        val delegate = delegate()
        val updated = delegate.markDelivered(messageId, atMillis)
        if (updated != null) save(delegate.snapshot())
        return updated
    }

    @Synchronized
    override fun acknowledge(messageId: String, atMillis: Long): AgentTeamMessageEnvelope? {
        val delegate = delegate()
        val updated = delegate.acknowledge(messageId, atMillis)
        if (updated != null) save(delegate.snapshot())
        return updated
    }

    @Synchronized
    override fun clear(supervisorRunId: String) {
        val delegate = delegate()
        delegate.clear(supervisorRunId)
        save(delegate.snapshot())
    }

    private fun delegate(): InMemoryAgentTeamMailbox = InMemoryAgentTeamMailbox(
        AgentTeamMessageCodec.decode(database.readString(KEY_MESSAGES, "[]"))
    )

    private fun save(messages: List<AgentTeamMessageEnvelope>) {
        database.writeString(KEY_MESSAGES, AgentTeamMessageCodec.encode(messages.takeLast(MAX_MESSAGES)).toString())
    }

    private companion object {
        const val DATABASE = "signalasi_agent_team_mailbox_v1"
        const val KEY_MESSAGES = "messages"
        const val MAX_MESSAGES = 5_000
    }
}

internal object AgentTeamMessageCodec {
    fun encode(messages: List<AgentTeamMessageEnvelope>): JSONArray = JSONArray().apply {
        messages.forEach { message ->
            put(JSONObject()
                .put("protocol", AgentTeamMessageEnvelope.PROTOCOL)
                .put("message_id", message.messageId)
                .put("team_id", message.teamId)
                .put("conversation_id", message.conversationId)
                .put("supervisor_run_id", message.supervisorRunId)
                .put("from_instance_id", message.fromInstanceId)
                .put("to_instance_id", message.toInstanceId)
                .put("kind", message.kind.name)
                .put("text", message.text)
                .put("in_reply_to", message.inReplyTo)
                .put("sequence", message.sequence)
                .put("state", message.state.name)
                .put("metadata", JSONObject(message.metadata))
                .put("created_at_millis", message.createdAtMillis)
                .put("delivered_at_millis", message.deliveredAtMillis)
                .put("acknowledged_at_millis", message.acknowledgedAtMillis))
        }
    }

    fun decode(raw: String): List<AgentTeamMessageEnvelope> = runCatching {
        val array = JSONArray(raw)
        buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                if (item.optString("protocol") != AgentTeamMessageEnvelope.PROTOCOL) continue
                val metadataJson = item.optJSONObject("metadata") ?: JSONObject()
                val metadata = buildMap {
                    metadataJson.keys().forEach { key -> put(key, metadataJson.optString(key)) }
                }
                val message = AgentTeamMessageEnvelope(
                    messageId = item.optString("message_id"),
                    teamId = item.optString("team_id"),
                    conversationId = item.optString("conversation_id"),
                    supervisorRunId = item.optString("supervisor_run_id"),
                    fromInstanceId = item.optString("from_instance_id"),
                    toInstanceId = item.optString("to_instance_id"),
                    kind = enumOrDefault(item.optString("kind"), AgentTeamMessageKind.USER_DIRECTIVE),
                    text = item.optString("text"),
                    inReplyTo = item.optString("in_reply_to"),
                    sequence = item.optLong("sequence"),
                    state = enumOrDefault(item.optString("state"), AgentTeamMessageState.PENDING),
                    metadata = metadata,
                    createdAtMillis = item.optLong("created_at_millis"),
                    deliveredAtMillis = item.optLong("delivered_at_millis"),
                    acknowledgedAtMillis = item.optLong("acknowledged_at_millis")
                ).validated()
                add(message)
            }
        }
    }.getOrDefault(emptyList())

    private inline fun <reified T : Enum<T>> enumOrDefault(value: String, fallback: T): T =
        enumValues<T>().firstOrNull { it.name == value } ?: fallback
}
