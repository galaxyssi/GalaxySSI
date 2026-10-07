package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject

internal object AndroidCollaborationRemoteMilestone {
    const val CONTRACT = "galaxyssi.collaboration-publish/1"
    const val REQUEST = "collaboration_publish_request"
    const val RESPONSE = "collaboration_publish_result"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val replies = CollaborationExchangeReplay()

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
        val app = context.applicationContext
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
                val binding = AndroidCollaborationRemoteRecall.access(app, request, desktop)
                trace(CollaborationExchangeTrace.Stage.RESOLVED)
                val result = if (binding == null) CollaborationRemoteRecallProtocol.unavailable()
                else if (lease.replay) replies.read(lease, binding) ?: CollaborationRemoteRecallProtocol.unavailable().also {
                    trace(CollaborationExchangeTrace.Stage.REPLAY_SCOPE_CHANGED)
                } else
                    CollaborationMilestoneTool.execute(CollaborationResearchWorkspace(app), binding, request.getJSONObject("arguments")) {
                        require(AndroidCollaborationRemoteRecall.access(app, request, desktop) == binding) { "Assignment is no longer active" }
                    }
                val safe = if (binding != null && AndroidCollaborationRemoteRecall.access(app, request, desktop) != binding)
                    CollaborationRemoteRecallProtocol.unavailable().also { trace(CollaborationExchangeTrace.Stage.AUTHORIZATION_CHANGED) } else result
                if (binding != null) replies.remember(lease, binding, safe)
                trace(CollaborationExchangeTrace.Stage.RESPONSE_READY)
                trace(reply(app, request, desktop, safe))
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                Log.w("GalaxySSIMilestone", "Milestone operation deferred: ${error.javaClass.simpleName}")
                trace(CollaborationExchangeTrace.Stage.FAILED)
                runCatching { trace(reply(app, request, desktop,
                    CollaborationMilestoneTool.unavailable(request.getString("phase")))) }
            } finally { replies.release(lease) }
        }
    }

    private fun reply(context: Context, request: JSONObject, desktop: String, result: JSONObject): CollaborationExchangeTrace.Stage {
        if (!valid(request, System.currentTimeMillis()) || !AndroidCollaborationRemoteRecall.paired(context, request, desktop))
            return CollaborationExchangeTrace.Stage.RESPONSE_EXPIRED_OR_UNPAIRED
        val response = CollaborationRemoteEvidenceProtocol.scope(request).put("type", RESPONSE).put("contract", CONTRACT)
            .put("request_id", request.getString("request_id")).put("phase", request.getString("phase")).put("result", result)
        return if (GalaxySSIMqttClient.publishJsonForTransport(response,
            GalaxySSIMqttClient.outgoingTopicFor(request.getString("contact_id")), request.getString("contact_id")))
            CollaborationExchangeTrace.Stage.PUBLISH_ACCEPTED else CollaborationExchangeTrace.Stage.PUBLISH_REJECTED
    }
}
