package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

enum class AgentDisclosedDataKind(val wireValue: String) {
    MESSAGE_TEXT("message_text"),
    CONVERSATION_HISTORY("conversation_history"),
    SYSTEM_INSTRUCTIONS("system_instructions"),
    TOOL_OUTPUT("tool_output"),
    SCREEN_CONTEXT("screen_context"),
    MEMORY_CONTEXT("memory_context"),
    KNOWLEDGE_CONTEXT("knowledge_context"),
    DEVICE_CONTEXT("device_context"),
    IMAGE("image"),
    AUDIO("audio"),
    VIDEO("video"),
    DOCUMENT("document"),
    OTHER_FILE("other_file")
}

enum class AgentDisclosureProtection(val wireValue: String) {
    ON_DEVICE("on_device"),
    SIGNAL_E2EE("signal_e2ee"),
    TLS("tls")
}

enum class AgentDisclosureStatus(val wireValue: String) {
    PREPARING("preparing"),
    QUEUED("queued"),
    SENT("sent"),
    BLOCKED("blocked"),
    FAILED("failed")
}

data class AgentDataDisclosureRecord(
    val eventId: String = UUID.randomUUID().toString(),
    val destinationId: String,
    val destinationTitle: String,
    val providerId: String = "",
    val modelId: String = "",
    val location: AgentResourceLocation,
    val trust: AgentResourceTrust,
    val protection: AgentDisclosureProtection,
    val purpose: String,
    val dataKinds: Set<AgentDisclosedDataKind>,
    val textCharacters: Int = 0,
    val attachmentCount: Int = 0,
    val attachmentBytes: Long = 0L,
    val conversationIdHash: String = "",
    val taskIdHash: String = "",
    val turnIdHash: String = "",
    val createdAtMillis: Long = System.currentTimeMillis(),
    val updatedAtMillis: Long = createdAtMillis,
    val status: AgentDisclosureStatus = AgentDisclosureStatus.PREPARING,
    val failureReason: String = ""
) {
    init {
        require(destinationId.isNotBlank()) { "Disclosure destination is required" }
        require(destinationTitle.isNotBlank()) { "Disclosure destination title is required" }
        require(textCharacters >= 0) { "Disclosure text size must be non-negative" }
        require(attachmentCount >= 0) { "Disclosure attachment count must be non-negative" }
        require(attachmentBytes >= 0L) { "Disclosure attachment size must be non-negative" }
    }
}

data class AgentDisclosureTicket(
    val eventId: String,
    val allowed: Boolean
)

data class AgentDataDisclosureSummary(
    val total: Int,
    val cloud: Int,
    val trustedDesktop: Int,
    val blocked: Int,
    val destinations: Int
)

interface AgentDataDisclosureStore {
    fun append(record: AgentDataDisclosureRecord)
    fun update(eventId: String, status: AgentDisclosureStatus, failureReason: String = "")
    fun list(limit: Int = 100): List<AgentDataDisclosureRecord>
    fun find(eventId: String): AgentDataDisclosureRecord?
    fun clearHistory()
    fun blockedDestinationIds(): Set<String>
    fun setDestinationBlocked(destinationId: String, blocked: Boolean)
}

class InMemoryAgentDataDisclosureStore : AgentDataDisclosureStore {
    private val records = mutableListOf<AgentDataDisclosureRecord>()
    private val blocked = linkedSetOf<String>()

    @Synchronized
    override fun append(record: AgentDataDisclosureRecord) {
        records += record
        if (records.size > MAX_RECORDS) records.subList(0, records.size - MAX_RECORDS).clear()
    }

    @Synchronized
    override fun update(eventId: String, status: AgentDisclosureStatus, failureReason: String) {
        val index = records.indexOfLast { it.eventId == eventId }
        if (index < 0) return
        records[index] = records[index].copy(
            status = status,
            failureReason = failureReason.take(MAX_FAILURE_REASON),
            updatedAtMillis = System.currentTimeMillis()
        )
    }

    @Synchronized
    override fun list(limit: Int): List<AgentDataDisclosureRecord> =
        records.asReversed().take(limit.coerceIn(1, MAX_LIST_LIMIT))

    @Synchronized
    override fun find(eventId: String): AgentDataDisclosureRecord? =
        records.lastOrNull { it.eventId == eventId }

    @Synchronized
    override fun clearHistory() = records.clear()

    @Synchronized
    override fun blockedDestinationIds(): Set<String> = blocked.toSet()

    @Synchronized
    override fun setDestinationBlocked(destinationId: String, blocked: Boolean) {
        val normalized = destinationId.trim()
        if (normalized.isBlank()) return
        if (blocked) this.blocked += normalized else this.blocked -= normalized
    }

    companion object {
        const val MAX_RECORDS = 1_000
        const val MAX_LIST_LIMIT = 250
        const val MAX_FAILURE_REASON = 240
    }
}

class EncryptedAgentDataDisclosureStore(context: Context) : AgentDataDisclosureStore {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE_NAME)

    override fun append(record: AgentDataDisclosureRecord) = synchronized(STORAGE_LOCK) {
        saveRecords(loadRecords().plus(record).takeLast(InMemoryAgentDataDisclosureStore.MAX_RECORDS))
    }

    override fun update(
        eventId: String,
        status: AgentDisclosureStatus,
        failureReason: String
    ) = synchronized(STORAGE_LOCK) {
        val records = loadRecords().toMutableList()
        val index = records.indexOfLast { it.eventId == eventId }
        if (index < 0) return@synchronized
        records[index] = records[index].copy(
            status = status,
            failureReason = failureReason.take(InMemoryAgentDataDisclosureStore.MAX_FAILURE_REASON),
            updatedAtMillis = System.currentTimeMillis()
        )
        saveRecords(records)
    }

    override fun list(limit: Int): List<AgentDataDisclosureRecord> =
        synchronized(STORAGE_LOCK) {
            loadRecords().asReversed()
                .take(limit.coerceIn(1, InMemoryAgentDataDisclosureStore.MAX_LIST_LIMIT))
        }

    override fun find(eventId: String): AgentDataDisclosureRecord? =
        synchronized(STORAGE_LOCK) {
            loadRecords().lastOrNull { it.eventId == eventId }
        }

    override fun clearHistory() = synchronized(STORAGE_LOCK) {
        database.remove(KEY_RECORDS)
    }

    override fun blockedDestinationIds(): Set<String> = synchronized(STORAGE_LOCK) {
        runCatching {
            val source = JSONArray(database.readString(KEY_BLOCKED_DESTINATIONS, "[]"))
            buildSet {
                for (index in 0 until source.length()) {
                    source.optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
                }
            }
        }.getOrDefault(emptySet())
    }

    override fun setDestinationBlocked(destinationId: String, blocked: Boolean) =
        synchronized(STORAGE_LOCK) {
        val normalized = destinationId.trim()
        if (normalized.isBlank()) return@synchronized
        val values = loadBlockedDestinationIds().toMutableSet()
        if (blocked) values += normalized else values -= normalized
        database.writeString(
            KEY_BLOCKED_DESTINATIONS,
            JSONArray(values.sorted()).toString()
        )
    }

    private fun loadRecords(): List<AgentDataDisclosureRecord> = runCatching {
        val source = JSONArray(database.readString(KEY_RECORDS, "[]"))
        buildList {
            for (index in 0 until source.length()) {
                source.optJSONObject(index)?.toDisclosureRecord()?.let(::add)
            }
        }
    }.getOrDefault(emptyList())

    private fun saveRecords(records: List<AgentDataDisclosureRecord>) {
        database.writeString(
            KEY_RECORDS,
            JSONArray().apply { records.forEach { put(it.toJson()) } }.toString()
        )
    }

    companion object {
        const val DATABASE_NAME = "signalasi_data_disclosure_ledger_v1"
        private const val KEY_RECORDS = "records"
        private const val KEY_BLOCKED_DESTINATIONS = "blocked_destinations"
        private val STORAGE_LOCK = Any()
    }

    private fun loadBlockedDestinationIds(): Set<String> = runCatching {
        val source = JSONArray(database.readString(KEY_BLOCKED_DESTINATIONS, "[]"))
        buildSet {
            for (index in 0 until source.length()) {
                source.optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
            }
        }
    }.getOrDefault(emptySet())
}

object AgentDataDisclosureLedger {
    fun beginCloudRequest(
        context: Context,
        contact: JSONObject,
        text: String,
        historyCount: Int = 0,
        systemInstructions: Boolean = false,
        toolOutput: Boolean = false,
        purpose: String,
        conversationId: String = "",
        taskId: String = "",
        turnId: String = ""
    ): AgentDisclosureTicket {
        val contactId = contact.optString("id").ifBlank { contact.optString("signalasi_id") }
        val providerId = contact.optString("cloud_provider").ifBlank { "custom" }
        val modelId = contact.optString("cloud_model")
        val endpoint = contact.optString("cloud_endpoint")
        val localNetwork = endpoint.contains("127.0.0.1") ||
            endpoint.contains("localhost", ignoreCase = true) ||
            endpoint.contains("192.168.") ||
            endpoint.contains("10.") ||
            endpoint.contains("172.16.")
        val destinationId = contactId.ifBlank { "cloud:$providerId:$modelId" }
        val title = contact.optString("display_name")
            .ifBlank { contact.optString("name") }
            .ifBlank { providerId }
            .ifBlank { modelId }
            .ifBlank { "Cloud model" }
        val kinds = AgentDataDisclosureClassifier.classifyText(
            text = text,
            includeHistory = historyCount > 1,
            includeSystemInstructions = systemInstructions,
            includeToolOutput = toolOutput
        )
        return begin(
            context,
            AgentDataDisclosureRecord(
                destinationId = destinationId,
                destinationTitle = title,
                providerId = providerId,
                modelId = modelId,
                location = if (localNetwork) AgentResourceLocation.PRIVATE_NETWORK else AgentResourceLocation.CLOUD,
                trust = if (localNetwork) AgentResourceTrust.PRIVATE_CONFIGURED else AgentResourceTrust.CLOUD_CONFIGURED,
                protection = AgentDisclosureProtection.TLS,
                purpose = purpose.take(160),
                dataKinds = kinds,
                textCharacters = text.length,
                conversationIdHash = disclosureHash(conversationId),
                taskIdHash = disclosureHash(taskId),
                turnIdHash = disclosureHash(turnId)
            )
        )
    }

    fun beginDesktopRequest(
        context: Context,
        contactId: String,
        text: String,
        attachments: List<AgentInputAttachment>,
        conversationId: String,
        taskId: String,
        turnId: String
    ): AgentDisclosureTicket {
        val contact = AppStore.contactById(context, contactId)
        val desktopId = contact?.optString("desktop_id").orEmpty()
        val providerId = contact?.optString("provider_id").orEmpty()
            .ifBlank { contact?.optString("agent_id").orEmpty() }
        val destinationId = contactId.ifBlank { desktopId }.ifBlank { providerId }.ifBlank { "desktop-agent" }
        val title = contact?.optString("display_name").orEmpty()
            .ifBlank { contact?.optString("name").orEmpty() }
            .ifBlank { providerId }
            .ifBlank { destinationId }
        val attachmentKinds = attachments.mapTo(linkedSetOf()) {
            AgentDataDisclosureClassifier.attachmentKind(it.mimeType, it.displayName)
        }
        return begin(
            context,
            AgentDataDisclosureRecord(
                destinationId = destinationId,
                destinationTitle = title,
                providerId = providerId,
                location = AgentResourceLocation.TRUSTED_DESKTOP,
                trust = AgentResourceTrust.VERIFIED_PAIRED,
                protection = AgentDisclosureProtection.SIGNAL_E2EE,
                purpose = "Agent task",
                dataKinds = AgentDataDisclosureClassifier.classifyText(text) + attachmentKinds,
                textCharacters = text.length,
                attachmentCount = attachments.size,
                attachmentBytes = attachments.sumOf { it.sizeBytes.coerceAtLeast(0L) },
                conversationIdHash = disclosureHash(conversationId),
                taskIdHash = disclosureHash(taskId),
                turnIdHash = disclosureHash(turnId)
            )
        )
    }

    fun update(
        context: Context,
        ticket: AgentDisclosureTicket,
        status: AgentDisclosureStatus,
        failureReason: String = ""
    ) {
        EncryptedAgentDataDisclosureStore(context).update(ticket.eventId, status, failureReason)
    }

    fun summary(records: List<AgentDataDisclosureRecord>): AgentDataDisclosureSummary =
        AgentDataDisclosureSummary(
            total = records.size,
            cloud = records.count { it.location == AgentResourceLocation.CLOUD },
            trustedDesktop = records.count { it.location == AgentResourceLocation.TRUSTED_DESKTOP },
            blocked = records.count { it.status == AgentDisclosureStatus.BLOCKED },
            destinations = records.map(AgentDataDisclosureRecord::destinationId).distinct().size
        )

    private fun begin(context: Context, record: AgentDataDisclosureRecord): AgentDisclosureTicket {
        val store = EncryptedAgentDataDisclosureStore(context)
        val blocked = record.destinationId in store.blockedDestinationIds()
        val stored = if (blocked) {
            record.copy(
                status = AgentDisclosureStatus.BLOCKED,
                failureReason = "Destination blocked by the privacy dashboard"
            )
        } else {
            record
        }
        store.append(stored)
        return AgentDisclosureTicket(stored.eventId, !blocked)
    }
}

object AgentDataDisclosureClassifier {
    fun classifyText(
        text: String,
        includeHistory: Boolean = false,
        includeSystemInstructions: Boolean = false,
        includeToolOutput: Boolean = false
    ): Set<AgentDisclosedDataKind> = buildSet {
        if (text.isNotBlank()) add(AgentDisclosedDataKind.MESSAGE_TEXT)
        if (includeHistory) add(AgentDisclosedDataKind.CONVERSATION_HISTORY)
        if (includeSystemInstructions) add(AgentDisclosedDataKind.SYSTEM_INSTRUCTIONS)
        if (includeToolOutput) add(AgentDisclosedDataKind.TOOL_OUTPUT)
        val normalized = text.lowercase(Locale.ROOT)
        if ("screen_context" in normalized || "current screen" in normalized || "screen tree" in normalized) {
            add(AgentDisclosedDataKind.SCREEN_CONTEXT)
        }
        if ("memory context" in normalized || "durable memory" in normalized || "recalled memory" in normalized) {
            add(AgentDisclosedDataKind.MEMORY_CONTEXT)
        }
        if ("knowledge context" in normalized || "knowledge source" in normalized || "retrieved evidence" in normalized) {
            add(AgentDisclosedDataKind.KNOWLEDGE_CONTEXT)
        }
        if ("device context" in normalized || "device status" in normalized || "battery_percent" in normalized) {
            add(AgentDisclosedDataKind.DEVICE_CONTEXT)
        }
    }

    fun attachmentKind(mimeType: String, displayName: String): AgentDisclosedDataKind {
        val mime = mimeType.lowercase(Locale.ROOT)
        val extension = displayName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return when {
            mime.startsWith("image/") -> AgentDisclosedDataKind.IMAGE
            mime.startsWith("audio/") -> AgentDisclosedDataKind.AUDIO
            mime.startsWith("video/") -> AgentDisclosedDataKind.VIDEO
            mime.startsWith("text/") ||
                extension in setOf("pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "txt", "md") ->
                AgentDisclosedDataKind.DOCUMENT
            else -> AgentDisclosedDataKind.OTHER_FILE
        }
    }
}

class AgentDataDisclosureBlockedException(destination: String) :
    IllegalStateException("Data sharing with $destination is blocked in Privacy Dashboard")

private fun AgentDataDisclosureRecord.toJson(): JSONObject = JSONObject()
    .put("event_id", eventId)
    .put("destination_id", destinationId)
    .put("destination_title", destinationTitle)
    .put("provider_id", providerId)
    .put("model_id", modelId)
    .put("location", location.name)
    .put("trust", trust.name)
    .put("protection", protection.wireValue)
    .put("purpose", purpose)
    .put("data_kinds", JSONArray(dataKinds.map(AgentDisclosedDataKind::wireValue).sorted()))
    .put("text_characters", textCharacters)
    .put("attachment_count", attachmentCount)
    .put("attachment_bytes", attachmentBytes)
    .put("conversation_id_hash", conversationIdHash)
    .put("task_id_hash", taskIdHash)
    .put("turn_id_hash", turnIdHash)
    .put("created_at_ms", createdAtMillis)
    .put("updated_at_ms", updatedAtMillis)
    .put("status", status.wireValue)
    .put("failure_reason", failureReason)

private fun JSONObject.toDisclosureRecord(): AgentDataDisclosureRecord? = runCatching {
    AgentDataDisclosureRecord(
        eventId = getString("event_id"),
        destinationId = getString("destination_id"),
        destinationTitle = getString("destination_title"),
        providerId = optString("provider_id"),
        modelId = optString("model_id"),
        location = enumValues<AgentResourceLocation>().firstOrNull { it.name == optString("location") }
            ?: AgentResourceLocation.CLOUD,
        trust = enumValues<AgentResourceTrust>().firstOrNull { it.name == optString("trust") }
            ?: AgentResourceTrust.UNKNOWN,
        protection = enumValues<AgentDisclosureProtection>().firstOrNull {
            it.wireValue == optString("protection")
        } ?: AgentDisclosureProtection.TLS,
        purpose = optString("purpose"),
        dataKinds = optJSONArray("data_kinds").toDisclosureKinds(),
        textCharacters = optInt("text_characters").coerceAtLeast(0),
        attachmentCount = optInt("attachment_count").coerceAtLeast(0),
        attachmentBytes = optLong("attachment_bytes").coerceAtLeast(0L),
        conversationIdHash = optString("conversation_id_hash"),
        taskIdHash = optString("task_id_hash"),
        turnIdHash = optString("turn_id_hash"),
        createdAtMillis = optLong("created_at_ms"),
        updatedAtMillis = optLong("updated_at_ms"),
        status = enumValues<AgentDisclosureStatus>().firstOrNull {
            it.wireValue == optString("status")
        } ?: AgentDisclosureStatus.FAILED,
        failureReason = optString("failure_reason")
    )
}.getOrNull()

private fun JSONArray?.toDisclosureKinds(): Set<AgentDisclosedDataKind> = buildSet {
    val source = this@toDisclosureKinds ?: return@buildSet
    for (index in 0 until source.length()) {
        val value = source.optString(index)
        enumValues<AgentDisclosedDataKind>().firstOrNull { it.wireValue == value }?.let(::add)
    }
}

private fun disclosureHash(value: String): String {
    if (value.isBlank()) return ""
    return MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
