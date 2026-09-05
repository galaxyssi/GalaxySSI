package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject

internal object AndroidAgentResultRecovery {
    private val client = AgentResultRecoveryClient()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val active = ConcurrentHashMap.newKeySet<List<String>>()
    private val transfers = Semaphore(2)

    fun receive(context: Context, payload: JSONObject, desktopId: String) {
        if (paired(context, desktopId, payload)) client.receive(payload, desktopId)
    }

    fun request(context: Context, desktopId: String, fields: JSONObject) {
        val app = context.applicationContext
        val key = listOf(desktopId) + AgentResultRecoveryClient.identity(fields)
        if (!active.add(key)) return
        scope.launch {
            try {
                transfers.withPermit {
                    val payload = client.fetch(desktopId, fields,
                        stillPending = { eligible(app, desktopId, fields) },
                        publish = { publish(app, desktopId, it) }) ?: return@withPermit
                    if (!eligible(app, desktopId, fields)) return@withPermit
                    val response = response(payload)
                    // The bus commits to the encrypted inbox before notifying the UI.
                    AgentConnectorResponseBus.publish(app, response)
                    acknowledge(app, payload, response)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.w("GalaxySSIRecovery", "Final reply recovery deferred: ${error.javaClass.simpleName}")
            } finally { active.remove(key) }
        }
    }

    fun acknowledge(context: Context, payload: JSONObject, response: AgentConnectorResponse) {
        val receipt = payload.optJSONObject("result_recovery") ?: return
        if (!AgentConnectorResponseStore.wasRecorded(context, response)) return
        val digest = receipt.optString("sha256")
        if (!Regex("[a-f0-9]{64}").matches(digest)) return
        val contact = AppStore.contactById(context, payload.optString("contact_id")) ?: return
        val desktop = contact.optString("desktop_id")
        if (desktop.isBlank() || !paired(context, desktop, payload)) return
        val ack = JSONObject().put("type", "agent_task_result_received").put("sha256", digest)
        AgentResultRecoveryClient.FIELDS.forEach { ack.put(it, payload.optString(it)) }
        runCatching { publish(context, desktop, ack) }
            .onFailure { Log.w("GalaxySSIRecovery", "Durable result receipt deferred") }
    }

    internal fun eligible(context: Context, desktop: String, fields: JSONObject): Boolean {
        if (!paired(context, desktop, fields) || GalaxySSITransportPrivacyPolicy.isLocalOnly(fields)) return false
        val source = fields.optString("source_message_id").toLongOrNull() ?: return false
        if (AgentTerminalDeliveryStore.isTerminal(context, source)) return false
        val pending = AgentPendingDeliveryStore.find(context, source, fields.optString("contact_id")) ?: return false
        if (!AgentTaskIdentityStore.matchesRegistered(context, fields)) return false
        if (pending.sourceMessageId != source || pending.contactId != fields.optString("contact_id") ||
            pending.conversationId != fields.optString("conversation_id") || pending.turnId != fields.optString("turn_id") ||
            (pending.taskId != fields.optString("task_id") && pending.taskId != pending.turnId) ||
            pending.recoverySuccessorSourceMessageId > 0) return false
        return !AgentPendingDeliveryStore.isSuperseded(context, source, pending.conversationId, pending.turnId) &&
            !AgentConnectorResponseStore.containsTurn(context, pending.conversationId, pending.turnId)
    }

    private fun paired(context: Context, desktop: String, payload: JSONObject): Boolean {
        val link = GalaxySSILinkProtocol.serverLink(context, desktop) ?: return false
        return link.paired && link.routes.clientRouteId == payload.optString("client_route_id")
    }

    private fun publish(context: Context, desktop: String, payload: JSONObject): Boolean {
        if (!paired(context, desktop, payload)) return false
        val contact = payload.optString("contact_id")
        return GalaxySSIMqttClient.publishJsonForTransport(payload,
            GalaxySSIMqttClient.outgoingTopicFor(contact), contact)
    }

    private fun response(payload: JSONObject): AgentConnectorResponse {
        val encoded = payload.optString("exact_content_b64")
        val exact = if (payload.optString("exact_content_encoding") == "base64-utf8" && encoded.length in 1..256 * 1024) {
            runCatching {
                val bytes = Base64.getDecoder().decode(encoded)
                try { if (bytes.size <= 128 * 1024) String(bytes, Charsets.UTF_8) else null }
                finally { bytes.fill(0) }
            }.getOrNull()
        } else null
        return AgentConnectorResponse(sourceMessageId = payload.optString("source_message_id").toLong(),
            contactId = payload.getString("contact_id"), content = exact ?: payload.optString("content"),
            conversationId = payload.getString("conversation_id"), turnId = payload.getString("turn_id"),
            taskId = payload.getString("task_id"), richOutputJson = CodexStyleResponsePolicy.filterAssistantRichOutput(
                AgentRichContentCodec.fromEnvelope(payload)))
    }
}
