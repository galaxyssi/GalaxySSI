package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class AgentNativeToolReplayKey(
    val toolId: String,
    val toolVersion: String,
    val idempotencyKey: String,
    val scope: AgentNativeEffectScope = AgentNativeEffectScope()
)

interface AgentNativeToolReplayStore {
    fun get(key: AgentNativeToolReplayKey): AgentNativeToolResult?
    fun put(key: AgentNativeToolReplayKey, result: AgentNativeToolResult)
    fun claim(key: AgentNativeToolReplayKey, inputSha256: String, invocationId: String): AgentNativeEffectClaim
    fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult)
    fun clear()
}

class InMemoryAgentNativeToolReplayStore : AgentNativeToolReplayStore {
    private val entries = LinkedHashMap<AgentNativeToolReplayKey, AgentNativeToolResult>()
    private val claims = LinkedHashMap<AgentNativeToolReplayKey, AgentNativeEffectClaim>()

    @Synchronized
    override fun get(key: AgentNativeToolReplayKey): AgentNativeToolResult? = entries[key]

    @Synchronized
    override fun put(key: AgentNativeToolReplayKey, result: AgentNativeToolResult) {
        entries[key] = result
    }

    @Synchronized
    override fun claim(key: AgentNativeToolReplayKey, inputSha256: String, invocationId: String): AgentNativeEffectClaim {
        claims[key]?.let { return it.copy(acquired = false) }
        entries[key]?.let { return AgentNativeEffectClaim(false, it.receipt.invocationId, it.receipt.inputSha256, it) }
        return AgentNativeEffectClaim(true, invocationId, inputSha256).also { claims[key] = it }
    }

    @Synchronized
    override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
        val claim = requireNotNull(claims[key])
        require(claim.invocationId == invocationId && result.receipt.invocationId == invocationId &&
            claim.inputSha256 == result.receipt.inputSha256) { "Native effect owner or input changed" }
        require(claim.result == null || claim.result == result) { "Native effect outcome changed" }
        claims[key] = claim.copy(acquired = false, result = result)
        entries[key] = result
    }

    @Synchronized
    override fun clear() { entries.clear(); claims.clear() }
}

internal class LegacyAgentNativeToolReplayReader(context: Context, databaseName: String = DATABASE) {
    private val database = AgentEncryptedDatabase(context.applicationContext, databaseName)

    fun entries(): List<Pair<AgentNativeToolReplayKey, AgentNativeToolResult>> {
        if (!database.contains(KEY_ENTRIES)) return emptyList()
        return decode(database.readString(KEY_ENTRIES, "")).map { it.key to it.result }
    }

    fun clear() = database.clear()

    private fun decode(raw: String): List<StoredReplay> {
        val array = JSONArray(raw)
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                val result = requireNotNull(item.getJSONObject("result").toNativeToolResult()) { "Invalid legacy native receipt" }
                val key = AgentNativeToolReplayKey(
                    toolId = item.optString("tool_id"),
                    toolVersion = item.optString("tool_version"),
                    idempotencyKey = item.optString("idempotency_key")
                )
                require(key.toolId.isNotBlank() && key.toolVersion.isNotBlank() && key.idempotencyKey.isNotBlank()) {
                    "Invalid legacy native effect identity"
                }
                add(StoredReplay(key, result, item.optLong("saved_at_millis")))
            }
        }
    }

    private data class StoredReplay(
        val key: AgentNativeToolReplayKey,
        val result: AgentNativeToolResult,
        val savedAtMillis: Long
    )

    companion object {
        private const val DATABASE = "galaxyssi_native_tool_replay_v1"
        private const val KEY_ENTRIES = "entries"
    }
}

internal fun JSONObject.toNativeToolResult(): AgentNativeToolResult? = runCatching {
    val receiptJson = getJSONObject("receipt")
    val provenanceJson = getJSONObject("provenance")
    val errorJson = optJSONObject("error")
    val verificationJson = optJSONObject("verification")
    AgentNativeToolResult(
        status = resultStatus(optString("status")),
        output = optJSONObject("output").toNativeObject(),
        message = optString("message"),
        metadata = optJSONObject("metadata").toNativeObject(),
        error = errorJson?.let { error ->
            AgentNativeToolError(
                code = error.optString("code"),
                message = error.optString("message"),
                retryable = error.optBoolean("retryable"),
                details = error.optJSONObject("details").toNativeObject()
            )
        },
        verification = verificationJson?.let { verification ->
            AgentNativeToolVerification(
                status = verificationStatus(verification.optString("status")),
                message = verification.optString("message"),
                evidence = verification.optJSONObject("evidence").toNativeObject()
            )
        },
        receipt = AgentNativeToolReceipt(
            invocationId = receiptJson.getString("invocation_id"),
            idempotencyKey = receiptJson.nullableString("idempotency_key"),
            startedAtEpochMillis = receiptJson.optLong("started_at_epoch_ms"),
            finishedAtEpochMillis = receiptJson.optLong("finished_at_epoch_ms"),
            durationMillis = receiptJson.optLong("duration_ms"),
            status = resultStatus(receiptJson.optString("status")),
            inputSha256 = receiptJson.optString("input_sha256"),
            outputSha256 = receiptJson.optString("output_sha256"),
            replayed = receiptJson.optBoolean("replayed"),
            originalInvocationId = receiptJson.nullableString("original_invocation_id")
        ),
        provenance = AgentNativeToolProvenance(
            toolId = provenanceJson.getString("tool_id"),
            toolVersion = provenanceJson.getString("tool_version"),
            location = nativeLocation(provenanceJson.optString("location")),
            executorId = provenanceJson.optString("executor_id"),
            contractVersion = provenanceJson.optString("contract_version"),
            legacyAgentActionId = provenanceJson.nullableString("legacy_agent_action_id"),
            metadata = provenanceJson.optJSONObject("metadata").toNativeObject()
                .mapValues { it.value?.toString().orEmpty() }
        )
    )
}.getOrNull()

private fun JSONObject.nullableString(key: String): String? =
    if (!has(key) || isNull(key)) null else getString(key).takeIf(String::isNotBlank)

private fun JSONObject?.toNativeObject(): AgentNativeJsonObject {
    val source = this ?: return emptyMap()
    return source.keys().asSequence().associateWith { key -> source.opt(key).toNativeValue() }
}

private fun Any?.toNativeValue(): Any? = when (this) {
    null, JSONObject.NULL -> null
    is JSONObject -> toNativeObject()
    is JSONArray -> buildList {
        for (index in 0 until length()) add(opt(index).toNativeValue())
    }
    else -> this
}

private fun resultStatus(value: String): AgentNativeToolResultStatus =
    AgentNativeToolResultStatus.entries.firstOrNull { it.wireValue == value }
        ?: AgentNativeToolResultStatus.FAILED

private fun verificationStatus(value: String): AgentNativeVerificationStatus =
    AgentNativeVerificationStatus.entries.firstOrNull { it.wireValue == value }
        ?: AgentNativeVerificationStatus.SKIPPED

private fun nativeLocation(value: String): AgentNativeToolLocation =
    AgentNativeToolLocation.entries.firstOrNull { it.wireValue == value }
        ?: AgentNativeToolLocation.UNKNOWN
