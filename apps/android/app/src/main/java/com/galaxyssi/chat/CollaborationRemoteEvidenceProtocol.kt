package com.galaxyssi.chat

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

/** Read-only, nonce-bound queries. No model dispatch, resume or effect operation is exposed here. */
internal class CollaborationRemoteEvidenceClient {
    private data class Pending(val desktop: String, val request: JSONObject,
        val result: CompletableDeferred<JSONObject> = CompletableDeferred())
    private val pending = ConcurrentHashMap<String, Pending>()

    suspend fun query(desktop: String, fields: JSONObject, selection: JSONObject, timeoutMillis: Long = 8_000,
        publish: (JSONObject) -> Boolean): JSONObject? {
        require(CollaborationRemoteEvidenceProtocol.validScope(fields) && desktop.isNotBlank())
        val nonce = UUID.randomUUID().toString()
        val request = CollaborationRemoteEvidenceProtocol.scope(fields)
            .put("type", "agent_task_evidence_request").put("desktop_id", desktop).put("request_id", nonce)
        listOf("mode", "after_sequence", "evidence_id", "sha256", "page_index", "inline_page_bytes").forEach {
            if (selection.has(it)) request.put(it, selection.get(it))
        }
        val waiter = Pending(desktop, request)
        pending[nonce] = waiter
        try {
            if (!publish(request)) return null
            return withTimeoutOrNull(timeoutMillis) { waiter.result.await() }
        } finally { pending.remove(nonce, waiter); waiter.result.cancel() }
    }

    fun receive(payload: JSONObject, authenticatedDesktop: String, diagnostic: (String) -> Unit = {}): Boolean {
        fun rejected(reason: String): Boolean { diagnostic(reason); return false }
        val waiter = pending[payload.optString("request_id")] ?: return rejected("no_pending_request")
        val request = waiter.request
        if (authenticatedDesktop != waiter.desktop) return rejected("desktop_mismatch")
        if (payload.opt("type") != "agent_task_evidence" || payload.opt("contract") != CollaborationRemoteEvidenceProtocol.CONTRACT)
            return rejected("contract_mismatch")
        if (!CollaborationRemoteEvidenceProtocol.sameScope(request, payload)) return rejected("scope_mismatch")
        if (payload.opt("mode") != request.opt("mode")) return rejected("mode_mismatch")
        if (payload.opt("status") !in setOf("ready", "unavailable")) return rejected("invalid_status")
        if (payload.opt("status") == "ready" && request.opt("mode") == "page" &&
            listOf("page_index", "sha256", "evidence_id").any { payload.opt(it) != request.opt(it) }) return rejected("page_mismatch")
        return waiter.result.complete(JSONObject(payload.toString())).also { diagnostic(if (it) "accepted" else "already_completed") }
    }

    internal val pendingCount get() = pending.size
}

internal object CollaborationRemoteEvidenceProtocol {
    const val CONTRACT = "galaxyssi.desktop-tool-evidence/1"
    const val CAPABILITY = "desktop_codex_tool_evidence_v1"
    const val TRUST = "execution_observed_not_claim_verified"
    // A per-object phone parsing guard, not a source-count or research-step limit. Larger originals stay remote.
    const val MAX_BODY_BYTES = 8L * 1024 * 1024
    const val INLINE_PAGE_BYTES = 16_384L
    val TYPES = setOf("commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch")
    private val HASH = Regex("[a-f0-9]{64}")
    fun integer(value: JSONObject, key: String): Long? = when (val number = value.opt(key)) {
        is Int -> number.toLong()
        is Long -> number
        else -> null
    }
    fun validScope(value: JSONObject) = AgentResultRecoveryClient.FIELDS.all {
        (value.opt(it) as? String)?.length in 1..200
    } && (integer(value, "execution_generation") ?: 0) in 1..9_007_199_254_740_991L && value.opt("agent_id") == "codex"
    fun scope(value: JSONObject) = JSONObject().apply {
        AgentResultRecoveryClient.FIELDS.forEach { put(it, value.getString(it)) }
        put("execution_generation", requireNotNull(integer(value, "execution_generation")))
    }
    fun sameScope(a: JSONObject, b: JSONObject) = validScope(a) && validScope(b) &&
        AgentResultRecoveryClient.FIELDS.all { a.opt(it) == b.opt(it) } &&
        integer(a, "execution_generation") == integer(b, "execution_generation")

    fun descriptor(value: JSONObject, after: Long): Boolean {
        val bytes = integer(value, "total_bytes") ?: return false
        val pages = integer(value, "page_count") ?: return false
        return HASH.matches(value.optString("evidence_id")) && HASH.matches(value.optString("sha256")) &&
            (integer(value, "sequence") ?: 0) in (after + 1)..9_007_199_254_740_991L &&
            bytes in 1..(Int.MAX_VALUE - 8L) && pages == (bytes + 16383) / 16384 &&
            value.opt("item_type") in TYPES && value.opt("outcome") in setOf("failed", "returned") &&
            value.opt("trust") == TRUST && value.opt("coverage") == "provider_payload_as_received" &&
            (integer(value, "recorded_at") ?: -1) >= 0
    }

    fun original(bytes: ByteArray, fields: JSONObject, descriptor: JSONObject): JSONObject {
        require(bytes.size.toLong() == integer(descriptor, "total_bytes") &&
            AgentResultRecoveryClient.sha256(bytes) == descriptor.getString("sha256")) { "Remote evidence digest mismatch" }
        val raw = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        val value = JSONObject(raw)
        require(sameScope(fields, value) && value.opt("contract") == CONTRACT && value.opt("trust") == TRUST &&
            value.opt("coverage") == "provider_payload_as_received") { "Remote evidence scope changed" }
        val observation = value.getJSONObject("observation")
        val item = observation.getJSONObject("item")
        require(observation.opt("provider") == "codex" && listOf("thread_id", "turn_id").all {
            (observation.opt(it) as? String)?.length in 1..200
        } && (item.opt("id") as? String)?.length in 1..200 && item.opt("type") == descriptor.opt("item_type") &&
            item.opt("type") in TYPES && outcome(item) == descriptor.opt("outcome")) { "Remote observation classification changed" }
        // Store the byte-exact original, not a reserialized JSON object whose hash can differ.
        return JSONObject().put("status", outcome(item)).put("original_json", raw)
            .put("remote_sha256", descriptor.getString("sha256"))
            .put("remote_evidence_id", descriptor.getString("evidence_id"))
            .put("trust", TRUST).put("coverage", "provider_payload_as_received")
    }

    private fun truthy(value: Any?): Boolean = when (value) {
        null, JSONObject.NULL, false -> false
        is Number -> value.toDouble() != 0.0
        is String -> value.isNotEmpty()
        is JSONObject -> value.length() > 0
        is org.json.JSONArray -> value.length() > 0
        else -> true
    }
    private fun outcome(item: JSONObject): String = if (
        item.optString("status").lowercase(java.util.Locale.ROOT) in setOf("failed", "error", "cancelled", "canceled", "declined") ||
        truthy(item.opt("error")) || item.opt("isError") == true || item.optJSONObject("result")?.opt("isError") == true ||
        integer(item, "exitCode")?.let { it != 0L } == true) "failed" else "returned"
}
