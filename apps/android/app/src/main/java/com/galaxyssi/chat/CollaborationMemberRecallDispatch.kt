package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** A one-shot offer during synchronous original-request serialization, not a permission to read. */
internal object CollaborationMemberRecallDispatch {
    internal data class Offer(val delivery: AgentPendingDelivery, val team: String, val node: String, val route: String)
    private val encoding = ThreadLocal<Offer>()

    fun original(context: Context, action: AgentAction, delivery: AgentPendingDelivery): Offer? = try {
        resolve(context, action, delivery)
    } catch (cancelled: java.util.concurrent.CancellationException) { throw cancelled }
    catch (_: Exception) { null } // Optional preflight must not prevent the ordinary assignment.

    internal fun originalOwner(action: AgentAction, delivery: AgentPendingDelivery): AgentManagedResponseRecord? {
        if (CollaborationResultContract.forAction(action) != CollaborationResultContract.WORKSPACE ||
            action.parameters["agent_team_message"].toBoolean() || !action.parameters["request_kind"].isNullOrBlank() ||
            !action.parameters["connector_task_mode"].isNullOrBlank()) return null
        return AgentManagedDispatchIntent.record(action, delivery.sourceMessageId, delivery.contactId,
            delivery.conversationId, delivery.turnId, delivery.taskId)
    }

    private fun resolve(context: Context, action: AgentAction, delivery: AgentPendingDelivery): Offer? {
        val owner = originalOwner(action, delivery) ?: return null
        val contact = AppStore.contactById(context, delivery.contactId)
        val desktop = contact?.optString("desktop_id").orEmpty()
        if (!CollaborationMemberRecall.codexContact(contact, desktop)) return null
        val route = GalaxySSILinkProtocol.serverLink(context, desktop)?.takeIf { it.paired }?.routes?.clientRouteId
            ?.takeIf(String::isNotBlank) ?: return null
        val binding = CollaborationMemberRecall.assignment(context, delivery) ?: return null
        val node = action.parameters.getValue("agent_instance_id")
        if (binding.nodeId != node || binding.runId != owner.supervisorRunId) return null
        return Offer(delivery, action.parameters.getValue("team_id"), node, route)
    }

    fun <T> during(offer: Offer?, publish: () -> T): T {
        val previous = encoding.get()
        if (offer == null && previous == null) return publish()
        encoding.set(offer)
        return try { publish() } finally {
            if (previous == null) encoding.remove() else encoding.set(previous)
        }
    }

    fun encode(payload: JSONObject) {
        val offer = encoding.get() ?: return
        val id = offer.delivery
        if (payload.opt("type") != "text" || payload.opt("contact_id") != id.contactId ||
            payload.opt("conversation_id") != id.conversationId || payload.opt("task_id") != id.taskId ||
            payload.opt("turn_id") != id.turnId || payload.opt("team_id") != offer.team ||
            payload.opt("agent_instance_id") != offer.node || payload.opt("result_contract") != CollaborationResultContract.WORKSPACE ||
            payload.optString("request_kind").isNotEmpty() || payload.optString("connector_task_mode").isNotEmpty() ||
            payload.has("agent_team_message") || payload.opt("execution_mode") == "plan_only") return
        encoding.remove()
        // The task transport rejects a changed client route before publication.
        payload.put("client_route_id", offer.route).put(CollaborationMemberRecall.FLAG, true)
    }
}
