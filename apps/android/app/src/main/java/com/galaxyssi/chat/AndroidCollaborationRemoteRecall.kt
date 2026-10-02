package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore

/** No UI, perception, model invocation or side-effect tool is reachable through this handler. */
internal object AndroidCollaborationRemoteRecall {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val slots = Semaphore(4)
    private val active = ConcurrentHashMap.newKeySet<String>()

    fun receive(context: Context, payload: JSONObject, desktop: String) {
        if (!CollaborationRemoteRecallProtocol.valid(payload, System.currentTimeMillis())) return
        val app = context.applicationContext
        if (!paired(app, payload, desktop) || !AgentTaskIdentityStore.matchesRegistered(app, payload)) return
        val key = "$desktop:${payload.getString("request_id")}"
        if (!active.add(key)) return
        if (!slots.tryAcquire()) { active.remove(key); return }
        val request = JSONObject(payload.toString())
        scope.launch {
            try {
                val binding = access(app, request, desktop)
                val result = if (binding == null) CollaborationRemoteRecallProtocol.unavailable() else {
                    val value = JSONObject(CollaborationCloudRecall.execute(app, binding, request.getJSONObject("arguments")))
                    value.put("success", value.optString("status") == "returned")
                }
                // Recheck authorization after disk reads; do not send data from a revoked assignment.
                val safe = if (binding != null && access(app, request, desktop) != binding)
                    CollaborationRemoteRecallProtocol.unavailable() else result
                if (paired(app, request, desktop) && CollaborationRemoteRecallProtocol.valid(request, System.currentTimeMillis())) {
                    val response = CollaborationRemoteRecallProtocol.response(request, safe)
                    GalaxySSIMqttClient.publishJsonForTransport(response,
                        GalaxySSIMqttClient.outgoingTopicFor(request.getString("contact_id")), request.getString("contact_id"))
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                // A failed read must not crash the process or restart the model/effect.
                Log.w("GalaxySSIRecall", "Scoped recall deferred: ${error.javaClass.simpleName}")
            } finally { slots.release(); active.remove(key) }
        }
    }

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

    private fun paired(context: Context, request: JSONObject, desktop: String): Boolean {
        val link = GalaxySSILinkProtocol.serverLink(context, desktop) ?: return false
        return link.paired && link.routes.clientRouteId == request.optString("client_route_id") &&
            AppStore.contactById(context, request.optString("contact_id"))?.optString("desktop_id") == desktop
    }
}
