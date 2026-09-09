package com.galaxyssi.chat

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.metrics.AgentRecoveryTiming
import kotlinx.coroutines.CancellationException

internal class AgentRemoteRecoveryClient(private val diagnostic: (String, String) -> Unit = { _, _ -> }) {
    private data class Pending(
        val desktopId: String,
        val routeId: String,
        val identities: List<List<String>>,
        val includeResultPage: Boolean,
        val result: CompletableDeferred<List<JSONObject>> = CompletableDeferred()
    )

    private val pending = ConcurrentHashMap<String, Pending>()

    suspend fun query(
        desktopId: String,
        routeId: String,
        items: List<JSONObject>,
        timeoutMillis: Long = 8_000L,
        report: (String) -> Unit = {},
        timing: AgentRecoveryTiming? = null,
        includeResultPage: Boolean = false,
        publish: (JSONObject) -> Boolean
    ): List<JSONObject> {
        require(desktopId.isNotBlank() && routeId.isNotBlank())
        require(items.size in 1..32)
        if (items.any { GalaxySSITransportPrivacyPolicy.isLocalOnly(it) }) return emptyList()
        val identities = items.map(::identity)
        require(identities.all { values -> values.all { it.isNotBlank() && it.length <= 200 } })
        require(identities.all { it.first() == routeId } && identities.distinct().size == items.size)
        val requestId = UUID.randomUUID().toString()
        val request = Pending(desktopId, routeId, identities, includeResultPage)
        pending[requestId] = request
        notice(requestId, "started")
        // A batch is one round trip, not one duplicate sample for each item.
        val span = timing?.begin(items.first().optString("task_id"), "query")
        try {
            val payload = JSONObject().put("type", "agent_task_recovery_request")
                .put("request_id", requestId).put("client_route_id", routeId)
                .put("desktop_id", desktopId).put("items", JSONArray(items))
            if (includeResultPage) payload.put("include_result_page", true)
            if (!publish(payload)) {
                notice(requestId, "publish_rejected")
                report("publish_rejected")
                return emptyList()
            }
            notice(requestId, "transport_accepted")
            val response = withTimeoutOrNull(timeoutMillis) { request.result.await() }
            span?.outcome = if (response == null) "timed_out" else if (response.any {
                it.optString("status") == "unavailable"
            }) "failed" else "completed"
            val outcome = if (response == null) "response_timeout" else if (response.any {
                    it.optString("status") == "unavailable"
                }) "remote_unavailable" else "authenticated_response"
            notice(requestId, outcome)
            report(outcome)
            return response ?: emptyList()
        } catch (cancelled: CancellationException) {
            notice(requestId, "cancelled")
            span?.outcome = "cancelled"
            throw cancelled
        } finally {
            pending.remove(requestId, request)
            request.result.cancel()
            span?.close()
        }
    }

    fun receive(payload: JSONObject, authenticatedDesktopId: String): Boolean {
        val requestId = payload.optString("request_id")
        fun reject(reason: String): Boolean { notice(requestId, reason); return false }
        val request = pending[requestId] ?: return reject("late_or_unknown")
        if (authenticatedDesktopId != request.desktopId) return reject("wrong_desktop")
        if (payload.optString("client_route_id") != request.routeId) return reject("wrong_route")
        val array = payload.optJSONArray("items") ?: return reject("invalid_batch")
        if (array.length() != request.identities.size) return reject("invalid_batch")
        val items = (0 until array.length()).map { array.optJSONObject(it) ?: return reject("invalid_batch") }
        val identities = items.map(::identity)
        if (identities.distinct().size != items.size || identities.toSet() != request.identities.toSet()) {
            return reject("identity_mismatch")
        }
        return request.result.complete(request.identities.map { key ->
            val item = items[identities.indexOf(key)]
            val page = if (request.includeResultPage) AgentResultRecoveryPageCodec.bindInline(
                item, authenticatedDesktopId, payload.getString("request_id")) else null
            // Never retain unsolicited page content in metadata-only observations.
            JSONObject().also { clean ->
                item.keys().forEach { name -> if (name != "result_page") clean.put(name, item.get(name)) }
                if (page != null) clean.put("result_page", page)
            }
        }).also { notice(requestId, if (it) "accepted" else "duplicate") }
    }

    private fun notice(requestId: String, outcome: String) {
        if (requestId.isBlank() || requestId.length > 128) return
        runCatching { diagnostic(com.galaxyssi.chat.metrics.AgentLatencyContract.opaqueId(requestId), outcome) }
    }

    internal val pendingCount: Int get() = pending.size

    companion object {
        private val FIELDS = listOf("client_route_id", "conversation_id", "task_id", "turn_id",
            "contact_id", "source_message_id", "agent_id")
        private fun identity(json: JSONObject): List<String> = FIELDS.map { json.optString(it) }
    }
}
