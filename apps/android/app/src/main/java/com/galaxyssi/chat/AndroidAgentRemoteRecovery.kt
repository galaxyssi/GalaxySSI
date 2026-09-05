package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal object AndroidAgentRemoteRecovery {
    private val client = AgentRemoteRecoveryClient()

    fun receive(context: Context, payload: JSONObject, desktopId: String) {
        val link = GalaxySSILinkProtocol.serverLink(context, desktopId) ?: return
        if (link.paired && link.routes.clientRouteId == payload.optString("client_route_id")) {
            client.receive(payload, desktopId)
        }
    }

    suspend fun recover(context: Context, handoffs: List<AgentHandoffRecord>): List<AgentRecoverableRun> =
        withContext(Dispatchers.IO) {
            val queries = handoffs.mapNotNull { handoff ->
                if (GalaxySSITransportPrivacyPolicy.isLocalOnly(JSONObject(handoff.request.context)
                        .put("conversation_id", handoff.request.conversationId))) return@mapNotNull null
                val contactId = handoff.request.toAgentId
                val contact = AppStore.contactById(context, contactId) ?: return@mapNotNull null
                val desktopId = contact.optString("desktop_id").takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val identity = AgentTaskIdentityStore.find(context, contactId, handoff.sourceMessageId)
                    ?: return@mapNotNull null
                if (identity.conversationId != handoff.request.conversationId ||
                    identity.turnId != handoff.request.context["turn_id"]?.toString().orEmpty()
                        .ifBlank { handoff.request.taskId }) return@mapNotNull null
                val link = GalaxySSILinkProtocol.serverLink(context, desktopId) ?: return@mapNotNull null
                if (!link.paired || link.routes.clientRouteId != identity.clientRouteId) return@mapNotNull null
                val agentId = contact.optString("agent_id").ifBlank { AppStore.agentIdForContact(context, contactId) }
                if (agentId.isBlank()) return@mapNotNull null
                Query(handoff, desktopId, identity.clientRouteId, JSONObject()
                    .put("client_route_id", identity.clientRouteId).put("conversation_id", identity.conversationId)
                    .put("task_id", identity.taskId).put("turn_id", identity.turnId)
                    .put("contact_id", contactId).put("source_message_id", handoff.sourceMessageId.toString())
                    .put("agent_id", agentId))
            }.distinctBy { listOf(it.desktopId, it.payload.toString()) }
            buildList {
                queries.groupBy { it.desktopId to it.routeId }.values.forEach { group ->
                    group.chunked(32).forEach { batch ->
                        val first = batch.first()
                        val observations = client.query(first.desktopId, first.routeId, batch.map { it.payload }) { payload ->
                            GalaxySSIMqttClient.publishJsonForTransport(payload,
                                GalaxySSIMqttClient.outgoingTopicFor(first.handoff.request.toAgentId),
                                first.handoff.request.toAgentId)
                        }
                        observations.forEachIndexed { index, result ->
                            val query = batch[index]
                            val handoff = query.handoff
                            val observation = AgentRemoteRecoveryObservation(handoff.request.conversationId,
                                query.desktopId, result.optString("status"), result.optString("task_id"),
                                result.optString("remote_run_id"), result.optLong("status_sequence", -1L))
                            if (observation.workspaceStatus == null || observation.remoteRunId.isBlank() ||
                                observation.statusSequence < 0L) return@forEachIndexed
                            add(AgentRecoverableRun(
                                handle = AgentRunHandle(handoff.request.runId, handoff.request.taskId,
                                    handoff.request.toAgentId, observation.remoteRunId),
                                // Status revisions are not event cursors. Never skip unread remote events.
                                lastEventSequence = 0L,
                                observation = observation
                            ))
                        }
                    }
                }
            }
        }

    private data class Query(val handoff: AgentHandoffRecord, val desktopId: String,
        val routeId: String, val payload: JSONObject)
}
