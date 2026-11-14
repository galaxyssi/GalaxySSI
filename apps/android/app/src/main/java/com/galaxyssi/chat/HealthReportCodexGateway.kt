package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.selects.select
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

internal enum class HealthReportDeliveryProblem { NOT_SENT, NOT_ACCEPTED, REPLY_TIMEOUT, REMOTE_FAILURE }
internal class HealthReportCodexUnavailable(val problem: HealthReportDeliveryProblem = HealthReportDeliveryProblem.REMOTE_FAILURE) :
    IllegalStateException()

internal enum class HealthReportAdmission { MISSING, ACTIVE, COMPLETED, TERMINAL_FAILURE, UNKNOWN }
internal object HealthReportDelivery {
    suspend fun <T> receive(reply: CompletableDeferred<T>, publish: suspend () -> Boolean,
        probe: suspend () -> HealthReportAdmission, earlyWait: Long = 20_000, responseWait: Long = 160_000,
        retryDelay: Long = 500, activeGrace: Long = 90_000, completedGrace: Long = 30_000): T {
        suspend fun observe(): HealthReportAdmission? = coroutineScope {
            val observed = async { probe() }
            try { select { reply.onAwait { null }; observed.onAwait { it } } }
            finally { observed.cancel() }
        }
        suspend fun awaitFor(wait: Long): T? = withTimeoutOrNull(wait) { reply.await() }
        fun failure(problem: HealthReportDeliveryProblem): Nothing = throw HealthReportCodexUnavailable(problem)
        suspend fun awaitAdmitted(): T {
            awaitFor(responseWait)?.let { return it }
            val admission = observe()
            if (reply.isCompleted) return reply.await()
            val grace = when (admission) {
                HealthReportAdmission.ACTIVE -> activeGrace
                HealthReportAdmission.COMPLETED -> completedGrace
                HealthReportAdmission.TERMINAL_FAILURE -> failure(HealthReportDeliveryProblem.REMOTE_FAILURE)
                else -> 0L
            }
            return awaitFor(grace) ?: failure(HealthReportDeliveryProblem.REPLY_TIMEOUT)
        }
        var published = false
        repeat(2) { attempt ->
            if (reply.isCompleted) return reply.await()
            if (publish()) {
                published = true
                awaitFor(earlyWait)?.let { return it }
                val admission = observe()
                if (reply.isCompleted) return reply.await()
                when (admission) {
                    HealthReportAdmission.MISSING -> if (attempt == 1)
                        failure(HealthReportDeliveryProblem.NOT_ACCEPTED)
                    HealthReportAdmission.TERMINAL_FAILURE -> failure(HealthReportDeliveryProblem.REMOTE_FAILURE)
                    null -> return reply.await()
                    else -> return awaitAdmitted()
                }
            } else if (attempt == 1) throw HealthReportCodexUnavailable(
                if (published) HealthReportDeliveryProblem.NOT_ACCEPTED else HealthReportDeliveryProblem.NOT_SENT)
            delay(retryDelay)
        }
        throw HealthReportCodexUnavailable(HealthReportDeliveryProblem.NOT_SENT)
    }
}

internal data class HealthReportCodexRequest(val target: HealthReportVisionTarget, val id: UUID = UUID.randomUUID()) {
    val conversation = PREFIX + id
    val source = (id.mostSignificantBits and 0x1FFFFFFFFFFFFFL).coerceAtLeast(1L)
    val identity = AgentTaskIdentity(target.routeId, conversation, id.toString(), id.toString())
    fun recoveryIdentity() = JSONObject().put("client_route_id", target.routeId).put("conversation_id", conversation)
        .put("task_id", identity.taskId).put("turn_id", identity.turnId).put("contact_id", target.id)
        .put("source_message_id", source.toString()).put("agent_id", "codex")

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
    const val MAX_IMAGE_BYTES = 100_000
    private data class Pending(val request: HealthReportCodexRequest, val reply: CompletableDeferred<AgentConnectorResponse>)
    private val active = ConcurrentHashMap<String, Pending>()
    private val recovery = AgentRemoteRecoveryClient()

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
            if (target(context) != target) throw HealthReportCodexUnavailable(HealthReportDeliveryProblem.NOT_SENT)
            if (target.id in EncryptedAgentDataDisclosureStore(context).blockedDestinationIds()) throw HealthAccessBlocked()
        }
        validate()
        val ticket = AgentDataDisclosureLedger.beginDesktopRequest(context, target.id, HealthReportVisionProvider.instructions,
            listOf(AgentInputAttachment(request.id.toString(), Uri.EMPTY, "report.jpg", "image/jpeg", jpeg.size.toLong())),
            request.conversation, request.identity.taskId, request.identity.turnId)
        if (!ticket.allowed) throw HealthAccessBlocked()
        val pending = Pending(request, CompletableDeferred())
        check(active.putIfAbsent(request.conversation, pending) == null)
        var sent = false
        var finished = false
        try {
            val reply = HealthReportDelivery.receive(pending.reply, publish = {
                validate()
                GalaxySSIMqttClient.connect(context)
                if (withTimeoutOrNull(12_000L) {
                        while (GalaxySSIMqttClient.transportQueryReadiness(target.id) != "ready") { validate(); delay(200L) }
                        true
                    } != true) false
                else {
                    checkRoute()
                    GalaxySSIMqttClient.publishDesktopControlPayload(target.desktopId, request.payload(jpeg), durable = false,
                        clientRouteId = target.routeId, transient = true).also {
                        if (it && !sent) { sent = true; AgentDataDisclosureLedger.update(context, ticket, AgentDisclosureStatus.SENT) }
                    }
                }
            }, probe = {
                validate()
                val observation = recovery.query(target.desktopId, target.routeId, listOf(request.recoveryIdentity()),
                    timeoutMillis = 8_000) { query ->
                    GalaxySSIMqttClient.publishDesktopControlPayload(target.desktopId, query, durable = false,
                        clientRouteId = target.routeId, transient = true)
                }.singleOrNull()
                when (observation?.optString("status")) {
                    "unavailable" -> HealthReportAdmission.MISSING
                    "failed", "cancelled", "timed_out" -> HealthReportAdmission.TERMINAL_FAILURE
                    "completed" -> HealthReportAdmission.COMPLETED
                    "accepted", "queued", "starting", "running", "recovering" -> HealthReportAdmission.ACTIVE
                    else -> HealthReportAdmission.UNKNOWN
                }
            })
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
        if (payload.optString("type") == "agent_task_recovery_result" && !payload.optBoolean("peer_chat")) {
            val items = payload.optJSONArray("items")
            if (items != null && items.length() == 1 &&
                items.optJSONObject(0)?.optString("conversation_id")?.startsWith(HealthReportCodexRequest.PREFIX) == true) {
                recovery.receive(payload, desktop)
                return true
            }
        }
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
