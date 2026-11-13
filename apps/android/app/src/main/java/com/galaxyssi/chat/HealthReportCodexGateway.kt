package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject

internal data class HealthReportVisionTarget(
    val id: String, val authority: String, val configuration: AgentTargetConfiguration,
    val desktopId: String, val routeId: String, val pairing: String
) {
    val destination get() = "$authority / Auto ${'\u00b7'} Codex" +
        configuration.modelId.takeIf(String::isNotBlank)?.let { " / $it" }.orEmpty()
}

internal class HealthReportCodexUnavailable : IllegalStateException()

internal data class HealthReportCodexRequest(val target: HealthReportVisionTarget, val id: UUID = UUID.randomUUID()) {
    val conversation = PREFIX + id
    val source = (id.mostSignificantBits and 0x1FFFFFFFFFFFFFL).coerceAtLeast(1L)
    val identity = AgentTaskIdentity(target.routeId, conversation, id.toString(), id.toString())

    fun matches(payload: JSONObject, desktop: String): Boolean =
        desktop == target.desktopId && payload.optString("client_route_id") == identity.clientRouteId &&
            payload.optString("conversation_id") == conversation && payload.optString("task_id") == identity.taskId &&
            payload.optString("turn_id") == identity.turnId && payload.optString("contact_id") == target.id &&
            payload.optString("source_message_id") == source.toString()

    fun payload(jpeg: ByteArray): JSONObject {
        require(jpeg.size in 1..HealthReportCodexGateway.MAX_IMAGE_BYTES)
        return JSONObject().put("type", "text").put("content", HealthReportVisionProvider.instructions)
            .put("request_kind", PhoneAssistantTaskControl.SCREEN_ANALYSIS_REQUEST_KIND)
            .put("execution_mode", AgentTaskExecutionMode.AUTO_COMPLETE.wireValue)
            .put("response_language", "auto").put("contact_id", target.id).put("agent_id", "codex")
            .put("client_route_id", target.routeId).put("conversation_id", conversation)
            .put("task_id", identity.taskId).put("turn_id", identity.turnId).put("client_message_id", source)
            .put("attachments", JSONArray().put(JSONObject().put("id", id.toString()).put("name", "report.jpg")
                .put("mime_type", "image/jpeg").put("size", jpeg.size).put("transport_size", jpeg.size)
                .put("data_b64", Base64.getEncoder().encodeToString(jpeg))))
            .apply { AgentInvocationRequestJsonCodec.encode(target.configuration.modelId, target.configuration.reasoningEffort)
                ?.let { put("agent_invocation", it) } }
    }

    companion object { const val PREFIX = "health-report-vision:" }
}

/** Private foreground transcription: no chat, recovery queue, tool handoff or cross-provider fallback. */
internal object HealthReportCodexGateway : HealthReportVisionGateway {
    const val MAX_IMAGE_BYTES = 224 * 1024
    private data class Pending(val request: HealthReportCodexRequest, val reply: CompletableDeferred<AgentConnectorResponse>)
    private val active = ConcurrentHashMap<String, Pending>()

    override fun target(context: Context): HealthReportVisionTarget? {
        val registry = AppStoreAgentConnectorRegistry(context)
        val contacts = AgentConnectorContactSnapshot.from(AppStore.contacts(context))
        val candidates = registry.availableTargets().filter {
            it.kind == AgentConnectorKind.AGENT && (it.id == "codex" || it.id.endsWith(":codex"))
        }
        return candidates.firstNotNullOfOrNull { candidate ->
            val contact = contacts.preferredMatchingContactId(candidate.id) { id ->
                AppStore.usesPcConnectorTunnel(context, id) && AppStore.agentIdForContact(context, id) == "codex" &&
                    contacts.contactById(id)?.optBoolean("private_health_report_vision_v1") == true &&
                    registry.contactReady(id, contacts)
            } ?: return@firstNotNullOfOrNull null
            val desktop = AppStore.desktopIdForContact(context, contact)
            val link = GalaxySSILinkProtocol.serverLink(context, desktop)?.takeIf { it.paired }
                ?: return@firstNotNullOfOrNull null
            val config = AgentModelSelectionSettings.configurationForTarget(context, "health-report-vision", candidate.id)
                ?: AgentModelSelectionSettings.configurationForTarget(context, "health-report-vision", "codex")
                ?: AgentTargetConfiguration(modelId = candidate.invocationProfile.defaultModelId)
            HealthReportVisionTarget(contact, link.desktopName.filterNot(Char::isISOControl).take(100).ifBlank { "Desktop" },
                config, desktop, link.routes.clientRouteId, HealthCareDiscussion.desktopDestination(context, contact))
        }
    }

    override suspend fun read(context: Context, target: HealthReportVisionTarget, jpeg: ByteArray, validate: () -> Unit): String {
        val request = HealthReportCodexRequest(target)
        fun checkRoute() {
            validate()
            if (target(context) != target) throw HealthReportCodexUnavailable()
            if (target.id in EncryptedAgentDataDisclosureStore(context).blockedDestinationIds()) throw HealthAccessBlocked()
        }
        checkRoute()
        GalaxySSIMqttClient.connect(context)
        if (withTimeoutOrNull(12_000L) {
                while (GalaxySSIMqttClient.transportQueryReadiness(target.id) != "ready") delay(200L)
                true
            } != true) throw HealthReportCodexUnavailable()

        val ticket = AgentDataDisclosureLedger.beginDesktopRequest(context, target.id, HealthReportVisionProvider.instructions,
            listOf(AgentInputAttachment(request.id.toString(), Uri.EMPTY, "report.jpg", "image/jpeg", jpeg.size.toLong())),
            request.conversation, request.identity.taskId, request.identity.turnId)
        if (!ticket.allowed) throw HealthAccessBlocked()
        val pending = Pending(request, CompletableDeferred())
        check(active.putIfAbsent(request.conversation, pending) == null)
        var sent = false
        var finished = false
        try {
            val payload = request.payload(jpeg)
            checkRoute()
            sent = GalaxySSIMqttClient.publishDesktopControlPayload(target.desktopId, payload, durable = false,
                clientRouteId = target.routeId, transient = true)
            if (!sent) throw HealthReportCodexUnavailable()
            AgentDataDisclosureLedger.update(context, ticket, AgentDisclosureStatus.SENT)
            val reply = withTimeoutOrNull(180_000L) { pending.reply.await() } ?: throw HealthReportCodexUnavailable()
            finished = true
            checkRoute()
            if (!reply.success || reply.remoteFailure) throw HealthReportCodexUnavailable()
            return reply.content
        } finally {
            active.remove(request.conversation, pending)
            pending.reply.cancel()
            if (!sent) runCatching { AgentDataDisclosureLedger.update(context, ticket,
                AgentDisclosureStatus.FAILED, "health_report_not_sent") }
            if (sent && !finished) runCatching {
                val cancel = JSONObject().put("type", "agent_task_cancel").put("agent_id", "codex")
                    .put("contact_id", target.id).put("client_route_id", target.routeId)
                    .put("task_id", request.identity.taskId).put("turn_id", request.identity.turnId)
                    .put("conversation_id", request.conversation).put("source_message_id", request.source)
                GalaxySSIMqttClient.publishDesktopControlPayload(target.desktopId, cancel, durable = false,
                    clientRouteId = target.routeId, transient = true)
            }
        }
    }

    fun receive(context: Context, payload: JSONObject, desktop: String): Boolean {
        val conversation = payload.optString("conversation_id")
        if (!conversation.startsWith(HealthReportCodexRequest.PREFIX) || payload.optBoolean("peer_chat")) return false
        if (payload.optString("type") == "agent_task_result_receipt_confirmed") return false
        val pending = active[conversation] ?: return true
        if (!pending.request.matches(payload, desktop)) return true
        val type = payload.optString("type")
        val reply = when (type) {
            "text" -> AgentRemoteOutcomeCodec.decode(payload, AgentRemoteOutcomeCodec.content(context, payload))
            "agent_task_event" -> AgentRemoteOutcomeCodec.terminalFailureEvent(payload, "")
            else -> null
        } ?: return true
        pending.reply.complete(reply)
        if (type == "text") {
            // Acknowledge Desktop's result archive without persisting the report in the normal reply inbox.
            AgentResultReceipt.from(payload, desktop)?.takeIf { it.matches(reply) }?.let {
                AgentConnectorResponseStore.recordManagedReceipt(context, reply.copy(content = "Private report result handled"), it)
                AndroidAgentResultReceipts.request(context)
            }
        }
        return true
    }
}
