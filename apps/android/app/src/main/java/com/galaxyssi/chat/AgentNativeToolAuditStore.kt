package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.UUID

data class AgentNativeToolAuditRecord(
    val auditId: String = UUID.randomUUID().toString(),
    val invocationId: String,
    val toolId: String,
    val toolVersion: String,
    val location: AgentNativeToolLocation,
    val risk: AgentNativeToolRisk,
    val callerId: String,
    val identityHashes: Map<String, String>,
    val startedAtEpochMillis: Long,
    val finishedAtEpochMillis: Long,
    val durationMillis: Long,
    val status: AgentNativeToolResultStatus,
    val errorCode: String,
    val inputSha256: String,
    val outputSha256: String,
    val replayed: Boolean,
    val originalInvocationId: String?,
    val recordSha256: String
) {
    companion object {
        fun from(
            result: AgentNativeToolResult,
            context: AgentNativeToolInvocationContext,
            risk: AgentNativeToolRisk
        ): AgentNativeToolAuditRecord {
            val values = linkedMapOf<String, Any?>(
                "invocation_id" to result.receipt.invocationId,
                "tool_id" to result.provenance.toolId,
                "tool_version" to result.provenance.toolVersion,
                "location" to result.provenance.location.wireValue,
                "risk" to risk.wireValue,
                "caller_id" to context.callerId.take(160),
                "identity_hashes" to identityHashes(context),
                "started_at_epoch_ms" to result.receipt.startedAtEpochMillis,
                "finished_at_epoch_ms" to result.receipt.finishedAtEpochMillis,
                "duration_ms" to result.receipt.durationMillis,
                "status" to result.status.wireValue,
                "error_code" to result.error?.code.orEmpty().take(160),
                "input_sha256" to result.receipt.inputSha256,
                "output_sha256" to result.receipt.outputSha256,
                "replayed" to result.receipt.replayed,
                "original_invocation_id" to result.receipt.originalInvocationId
            )
            return AgentNativeToolAuditRecord(
                invocationId = result.receipt.invocationId,
                toolId = result.provenance.toolId,
                toolVersion = result.provenance.toolVersion,
                location = result.provenance.location,
                risk = risk,
                callerId = context.callerId.take(160),
                identityHashes = identityHashes(context),
                startedAtEpochMillis = result.receipt.startedAtEpochMillis,
                finishedAtEpochMillis = result.receipt.finishedAtEpochMillis,
                durationMillis = result.receipt.durationMillis,
                status = result.status,
                errorCode = result.error?.code.orEmpty().take(160),
                inputSha256 = result.receipt.inputSha256,
                outputSha256 = result.receipt.outputSha256,
                replayed = result.receipt.replayed,
                originalInvocationId = result.receipt.originalInvocationId,
                recordSha256 = AgentNativeJsonCodec.sha256(values)
            )
        }

        private fun identityHashes(context: AgentNativeToolInvocationContext): Map<String, String> =
            linkedMapOf<String, String>().apply {
                hash("session_id", context.sessionId)
                hash("conversation_id", context.conversationId)
                hash("turn_id", context.turnId)
                context.attributes["task_id"]?.let { hash("task_id", it) }
            }

        private fun MutableMap<String, String>.hash(key: String, value: String) {
            if (value.isNotBlank()) put("${key}_sha256", AgentNativeJsonCodec.sha256(value))
        }
    }
}

interface AgentNativeToolAuditStore {
    fun append(record: AgentNativeToolAuditRecord)
    fun list(
        limit: Int = 100,
        toolId: String = "",
        status: AgentNativeToolResultStatus? = null
    ): List<AgentNativeToolAuditRecord>
    fun clear()
}

class InMemoryAgentNativeToolAuditStore : AgentNativeToolAuditStore {
    private val records = mutableListOf<AgentNativeToolAuditRecord>()

    @Synchronized
    override fun append(record: AgentNativeToolAuditRecord) {
        records += record
        if (records.size > MAX_RECORDS) records.subList(0, records.size - MAX_RECORDS).clear()
    }

    @Synchronized
    override fun list(
        limit: Int,
        toolId: String,
        status: AgentNativeToolResultStatus?
    ): List<AgentNativeToolAuditRecord> = records.asReversed()
        .asSequence()
        .filter { toolId.isBlank() || it.toolId == toolId }
        .filter { status == null || it.status == status }
        .take(limit.coerceIn(1, MAX_LIST_LIMIT))
        .toList()

    @Synchronized
    override fun clear() = records.clear()

    companion object {
        const val MAX_RECORDS = 10_000
        const val MAX_LIST_LIMIT = 500
    }
}

class EncryptedAgentNativeToolAuditStore(context: Context) : AgentNativeToolAuditStore {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    override fun append(record: AgentNativeToolAuditRecord) {
        val retained = load().plus(record).takeLast(InMemoryAgentNativeToolAuditStore.MAX_RECORDS)
        save(retained)
    }

    @Synchronized
    override fun list(
        limit: Int,
        toolId: String,
        status: AgentNativeToolResultStatus?
    ): List<AgentNativeToolAuditRecord> = load().asReversed()
        .asSequence()
        .filter { toolId.isBlank() || it.toolId == toolId }
        .filter { status == null || it.status == status }
        .take(limit.coerceIn(1, InMemoryAgentNativeToolAuditStore.MAX_LIST_LIMIT))
        .toList()

    @Synchronized
    override fun clear() = database.clear()

    private fun load(): List<AgentNativeToolAuditRecord> = runCatching {
        val array = JSONArray(database.readString(KEY_RECORDS, "[]"))
        buildList {
            for (index in 0 until array.length()) {
                array.optJSONObject(index)?.toRecord()?.let(::add)
            }
        }
    }.getOrDefault(emptyList())

    private fun save(records: List<AgentNativeToolAuditRecord>) {
        database.writeString(
            KEY_RECORDS,
            JSONArray().apply { records.forEach { put(it.toJson()) } }.toString()
        )
    }

    private fun AgentNativeToolAuditRecord.toJson(): JSONObject = JSONObject()
        .put("audit_id", auditId)
        .put("invocation_id", invocationId)
        .put("tool_id", toolId)
        .put("tool_version", toolVersion)
        .put("location", location.wireValue)
        .put("risk", risk.wireValue)
        .put("caller_id", callerId)
        .put("identity_hashes", JSONObject(identityHashes))
        .put("started_at_epoch_ms", startedAtEpochMillis)
        .put("finished_at_epoch_ms", finishedAtEpochMillis)
        .put("duration_ms", durationMillis)
        .put("status", status.wireValue)
        .put("error_code", errorCode)
        .put("input_sha256", inputSha256)
        .put("output_sha256", outputSha256)
        .put("replayed", replayed)
        .put("original_invocation_id", originalInvocationId)
        .put("record_sha256", recordSha256)

    private fun JSONObject.toRecord(): AgentNativeToolAuditRecord? = runCatching {
        AgentNativeToolAuditRecord(
            auditId = getString("audit_id"),
            invocationId = getString("invocation_id"),
            toolId = getString("tool_id"),
            toolVersion = optString("tool_version"),
            location = AgentNativeToolLocation.entries.firstOrNull {
                it.wireValue == optString("location")
            } ?: AgentNativeToolLocation.UNKNOWN,
            risk = AgentNativeToolRisk.entries.firstOrNull {
                it.wireValue == optString("risk")
            } ?: AgentNativeToolRisk.BLOCKED,
            callerId = optString("caller_id"),
            identityHashes = optJSONObject("identity_hashes").toStringMap(),
            startedAtEpochMillis = optLong("started_at_epoch_ms"),
            finishedAtEpochMillis = optLong("finished_at_epoch_ms"),
            durationMillis = optLong("duration_ms"),
            status = AgentNativeToolResultStatus.entries.firstOrNull {
                it.wireValue == optString("status")
            } ?: AgentNativeToolResultStatus.FAILED,
            errorCode = optString("error_code"),
            inputSha256 = optString("input_sha256"),
            outputSha256 = optString("output_sha256"),
            replayed = optBoolean("replayed"),
            originalInvocationId = optString("original_invocation_id").takeIf(String::isNotBlank),
            recordSha256 = optString("record_sha256")
        )
    }.getOrNull()

    private fun JSONObject?.toStringMap(): Map<String, String> {
        val source = this ?: return emptyMap()
        return source.keys().asSequence().associateWith(source::optString)
    }

    companion object {
        const val DATABASE = "galaxyssi_native_tool_audit_v1"
        private const val KEY_RECORDS = "records"
    }
}

internal object AgentNativeToolAuditDispatcher {
    private val writer = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "galaxyssi-native-tool-audit").apply { isDaemon = true }
    }

    fun append(store: AgentNativeToolAuditStore, record: AgentNativeToolAuditRecord) {
        if (store !is EncryptedAgentNativeToolAuditStore) {
            store.append(record)
            return
        }
        writer.execute {
            runCatching { store.append(record) }
        }
    }
}
