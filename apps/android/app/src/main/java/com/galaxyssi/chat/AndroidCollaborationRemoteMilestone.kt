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

internal object AndroidCollaborationRemoteMilestone {
    const val CONTRACT = "galaxyssi.collaboration-publish/1"
    const val REQUEST = "collaboration_publish_request"
    const val RESPONSE = "collaboration_publish_result"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val slots = Semaphore(4)
    private val active = ConcurrentHashMap.newKeySet<String>()

    internal fun valid(request: JSONObject, now: Long): Boolean =
        CollaborationRemoteEvidenceProtocol.validScope(request) && request.opt("type") == REQUEST &&
            request.opt("contract") == CONTRACT && (request.opt("request_id") as? String)?.length in 1..128 &&
            CollaborationRemoteEvidenceProtocol.integer(request, "expires_at")?.let { it > now && it - now <= 60_000 } == true &&
            request.optJSONObject("arguments")?.let { input ->
                request.opt("phase") == input.opt("mode") && runCatching { CollaborationMilestoneTool.validate(input) }.isSuccess
            } == true && !request.has("delivery")

    fun receive(context: Context, payload: JSONObject, desktop: String) {
        if (!valid(payload, System.currentTimeMillis()) || !AndroidCollaborationRemoteRecall.paired(context, payload, desktop) ||
            !AgentTaskIdentityStore.matchesRegistered(context, payload)) return
        val key = "$desktop:${payload.getString("request_id")}"
        if (!active.add(key)) return
        if (!slots.tryAcquire()) { active.remove(key); return }
        val app = context.applicationContext
        val request = JSONObject(payload.toString())
        scope.launch {
            try {
                val binding = AndroidCollaborationRemoteRecall.access(app, request, desktop)
                val result = if (binding == null) CollaborationRemoteRecallProtocol.unavailable() else
                    CollaborationMilestoneTool.execute(CollaborationResearchWorkspace(app), binding, request.getJSONObject("arguments")) {
                        require(AndroidCollaborationRemoteRecall.access(app, request, desktop) == binding) { "Assignment is no longer active" }
                    }
                val safe = if (binding != null && AndroidCollaborationRemoteRecall.access(app, request, desktop) != binding)
                    CollaborationRemoteRecallProtocol.unavailable() else result
                reply(app, request, desktop, safe)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                Log.w("GalaxySSIMilestone", "Publication deferred: ${error.javaClass.simpleName}")
                runCatching { reply(app, request, desktop, JSONObject().put("success", false).put("status", "unavailable")
                    .put("error", "Publication outcome is uncertain; retry the same milestone_id and artifact, or list saved milestones. Do not repeat completed effects.")) }
            } finally { slots.release(); active.remove(key) }
        }
    }

    private fun reply(context: Context, request: JSONObject, desktop: String, result: JSONObject) {
        if (!valid(request, System.currentTimeMillis()) || !AndroidCollaborationRemoteRecall.paired(context, request, desktop)) return
        val response = CollaborationRemoteEvidenceProtocol.scope(request).put("type", RESPONSE).put("contract", CONTRACT)
            .put("request_id", request.getString("request_id")).put("phase", request.getString("phase")).put("result", result)
        GalaxySSIMqttClient.publishJsonForTransport(response,
            GalaxySSIMqttClient.outgoingTopicFor(request.getString("contact_id")), request.getString("contact_id"))
    }
}
