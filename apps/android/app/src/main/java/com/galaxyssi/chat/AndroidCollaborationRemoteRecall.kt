package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject

/** No UI, perception, model invocation or side-effect tool is reachable through this handler. */
internal object AndroidCollaborationRemoteRecall {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val replies = CollaborationExchangeReplay()
    private val deliveries = CollaborationRecallDelivery()

    fun receive(context: Context, payload: JSONObject, desktop: String) {
        if (!CollaborationRemoteRecallProtocol.valid(payload, System.currentTimeMillis())) return
        val app = context.applicationContext
        if (!paired(app, payload, desktop) || !AgentTaskIdentityStore.matchesRegistered(app, payload)) return
        val request = JSONObject(payload.toString())
        val admitted = replies.acquire(desktop, request, System.currentTimeMillis())
        Log.i("GalaxySSIExchange", CollaborationExchangeTrace.line(desktop, request,
            CollaborationExchangeTrace.Stage.ADMISSION, admission = admitted.outcome))
        val lease = admitted.lease ?: return
        val started = android.os.SystemClock.elapsedRealtime()
        fun trace(stage: CollaborationExchangeTrace.Stage) = Log.i("GalaxySSIExchange",
            CollaborationExchangeTrace.line(desktop, request, stage, android.os.SystemClock.elapsedRealtime() - started))
        scope.launch {
            try {
                val binding = access(app, request, desktop)
                trace(CollaborationExchangeTrace.Stage.RESOLVED)
                val result = if (binding == null) CollaborationRemoteRecallProtocol.unavailable()
                else if (lease.replay) replies.read(lease, binding) ?: CollaborationRemoteRecallProtocol.unavailable().also {
                    trace(CollaborationExchangeTrace.Stage.REPLAY_SCOPE_CHANGED)
                }
                else if (request.getString("phase") == "confirm") deliveries.confirm(request, binding) { arguments, hash ->
                    if (access(app, request, desktop) != binding) null
                    else CollaborationEvidenceLedger(app).confirmPage(CollaborationCoordinatorUpdates.readAccess(app, binding), arguments.getString("evidence_id"),
                        arguments.getString("sha256"), arguments.optInt("offset", 0), hash)
                } else {
                    val sync = AndroidCollaborationRemoteEvidence.refresh(app, request, desktop, binding)
                    val value = JSONObject(CollaborationCloudRecall.execute(app, binding, request.getJSONObject("arguments"),
                        recordCoverage = false))
                    sync?.let { value.put("host_evidence_sync", it) }
                    value.put("success", value.optString("status") == "returned")
                    deliveries.prepare(request, binding, value)
                }
                // Recheck authorization after disk reads; do not send data from a revoked assignment.
                val safe = if (binding != null && access(app, request, desktop) != binding)
                    CollaborationRemoteRecallProtocol.unavailable().also { trace(CollaborationExchangeTrace.Stage.AUTHORIZATION_CHANGED) } else result
                if (binding != null) replies.remember(lease, binding, safe)
                trace(CollaborationExchangeTrace.Stage.RESPONSE_READY)
                if (paired(app, request, desktop) && CollaborationRemoteRecallProtocol.valid(request, System.currentTimeMillis())) {
                    trace(if (reply(request, safe)) CollaborationExchangeTrace.Stage.PUBLISH_ACCEPTED else CollaborationExchangeTrace.Stage.PUBLISH_REJECTED)
                } else trace(CollaborationExchangeTrace.Stage.RESPONSE_EXPIRED_OR_UNPAIRED)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                // A failed read must not crash the process or restart the model/effect.
                Log.w("GalaxySSIRecall", "Scoped recall deferred: ${error.javaClass.simpleName}")
                trace(CollaborationExchangeTrace.Stage.FAILED)
                runCatching {
                    if (paired(app, request, desktop) && CollaborationRemoteRecallProtocol.valid(request, System.currentTimeMillis()))
                        trace(if (reply(request, CollaborationRemoteRecallProtocol.unavailable()))
                            CollaborationExchangeTrace.Stage.PUBLISH_ACCEPTED else CollaborationExchangeTrace.Stage.PUBLISH_REJECTED)
                }
            } finally { replies.release(lease) }
        }
    }

    private fun reply(request: JSONObject, result: JSONObject): Boolean =
        GalaxySSIMqttClient.publishJsonForTransport(CollaborationRemoteRecallProtocol.response(request, result),
            GalaxySSIMqttClient.outgoingTopicFor(request.getString("contact_id")), request.getString("contact_id"))

    internal fun access(context: Context, request: JSONObject, desktop: String): CollaborationWorkspaceAccess? {
        if (!paired(context, request, desktop) || !AgentTaskIdentityStore.matchesRegistered(context, request)) return null
        val observation = AgentRemoteOutcomeCodec.observation(request) ?: return null
        if (!AgentConnectorResponseStore.isCurrentExecution(context, observation)) return null
        val access = CollaborationEvidenceLedger(context).binding(observation.sourceMessageId,
            observation.conversationId, observation.turnId) ?: return null
        if (AgentTeamDurableControl(context).get(access.runId) != AgentTeamUserControl.RUN ||
            CollaborationGroupStore(context).load(access.groupId)?.members?.none { it.id == access.personId } != false) return null
        if (EncryptedAgentManagedResponseLedger(context).pendingRecoveryDelivery(observation.sourceMessageId,
                observation.contactId, observation.conversationId, observation.turnId, observation.taskId) == null) return null
        return access
    }

    internal fun paired(context: Context, request: JSONObject, desktop: String): Boolean {
        val link = GalaxySSILinkProtocol.serverLink(context, desktop) ?: return false
        return link.paired && link.routes.clientRouteId == request.optString("client_route_id") &&
            AppStore.contactById(context, request.optString("contact_id"))?.optString("desktop_id") == desktop
    }
}
