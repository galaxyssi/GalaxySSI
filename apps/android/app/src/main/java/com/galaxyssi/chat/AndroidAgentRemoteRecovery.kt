package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal object AndroidAgentRemoteRecovery {
    private val observationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val observationSlots = Semaphore(2)
    private val client = AgentRemoteRecoveryClient { requestHash, outcome ->
        if (BuildConfig.DEBUG) Log.i("GalaxySSIRecovery", "query=${requestHash.take(12)} boundary=$outcome")
    }

    internal fun hasCurrentBinding(context: Context, delivery: AgentPendingDelivery): Boolean =
        resolveQuery(context, delivery.contactId, delivery.sourceMessageId,
            delivery.conversationId, delivery.turnId) != null

    fun receive(context: Context, payload: JSONObject, desktopId: String) {
        val link = GalaxySSILinkProtocol.serverLink(context, desktopId) ?: return
        if (link.paired && link.routes.clientRouteId == payload.optString("client_route_id")) {
            client.receive(payload, desktopId)
        }
    }

    suspend fun recover(context: Context, handoffs: List<AgentHandoffRecord>): List<AgentRecoverableRun> =
        queryHandoffs(context, handoffs, inspectOnly = false)

    /** Query authenticated facts without registering execution or requesting final-result redelivery. */
    suspend fun inspect(context: Context, handoffs: List<AgentHandoffRecord>): List<AgentRecoverableRun> =
        queryHandoffs(context, handoffs, inspectOnly = true)

    private suspend fun queryHandoffs(context: Context, handoffs: List<AgentHandoffRecord>, inspectOnly: Boolean): List<AgentRecoverableRun> =
        withContext(Dispatchers.IO) {
            val queries = handoffs.mapNotNull { handoff ->
                if (GalaxySSITransportPrivacyPolicy.isLocalOnly(JSONObject(handoff.request.context)
                        .put("conversation_id", handoff.request.conversationId))) return@mapNotNull null
                resolveQuery(context, handoff.request.toAgentId, handoff.sourceMessageId,
                    handoff.request.conversationId, handoff.request.context["turn_id"]?.toString().orEmpty()
                        .ifBlank { handoff.request.taskId })?.copy(handoff = handoff)
            }
            observe(context, queries, inspectOnly).mapNotNull { (query, observation) ->
                val handoff = query.handoff ?: return@mapNotNull null
                AgentRecoverableRun(
                    handle = AgentRunHandle(handoff.request.runId, handoff.request.taskId,
                        handoff.request.toAgentId, observation.remoteRunId),
                    // Status revisions are not event cursors. Never skip unread remote events.
                    lastEventSequence = 0L, observation = observation)
            }
        }

    suspend fun recoverPendingReplies(context: Context, pending: List<AgentPendingDelivery>,
        retry: () -> Unit = {}) =
        withContext(Dispatchers.IO) {
            val queries = pending.mapNotNull { delivery ->
                resolveQuery(context, delivery.contactId, delivery.sourceMessageId,
                    delivery.conversationId, delivery.turnId)?.takeIf {
                    AndroidAgentResultRecovery.eligible(context, it.desktopId, it.payload)
                }
            }
            observe(context, queries, automaticDiscovery = true, retry = retry)
            Unit
        }

    suspend fun inspectPendingReply(context: Context, delivery: AgentPendingDelivery): AgentRemoteRecoveryObservation? =
        withContext(Dispatchers.IO) {
            val query = resolveQuery(context, delivery.contactId, delivery.sourceMessageId,
                delivery.conversationId, delivery.turnId) ?: return@withContext null
            observe(context, listOf(query), inspectOnly = true).singleOrNull()?.second
        }

    private fun resolveQuery(context: Context, contactId: String, source: Long,
        conversationId: String, turnId: String): Query? {
        if (GalaxySSITransportPrivacyPolicy.isLocalOnly(JSONObject().put("conversation_id", conversationId))) return null
        val contact = AppStore.contactById(context, contactId) ?: return null
        val desktopId = contact.optString("desktop_id").takeIf { it.isNotBlank() } ?: return null
        val identity = AgentTaskIdentityStore.find(context, contactId, source) ?: return null
        if (identity.conversationId != conversationId || identity.turnId != turnId) return null
        val link = GalaxySSILinkProtocol.serverLink(context, desktopId) ?: return null
        if (!link.paired || link.routes.clientRouteId != identity.clientRouteId) return null
        val agentId = contact.optString("agent_id").ifBlank { AppStore.agentIdForContact(context, contactId) }
        if (agentId.isBlank()) return null
        return Query(null, desktopId, identity.clientRouteId, JSONObject()
            .put("client_route_id", identity.clientRouteId).put("conversation_id", identity.conversationId)
            .put("task_id", identity.taskId).put("turn_id", identity.turnId).put("contact_id", contactId)
            .put("source_message_id", source.toString()).put("agent_id", agentId))
    }

    private suspend fun observe(context: Context, queries: List<Query>, inspectOnly: Boolean = false,
        automaticDiscovery: Boolean = false, retry: () -> Unit = {}): List<Pair<Query, AgentRemoteRecoveryObservation>> =
            buildList {
                queries.distinctBy { listOf(it.desktopId, it.payload.toString()) }
                    .groupBy { it.desktopId to it.routeId }.values.forEach { group ->
                    group.chunked(32).forEach batches@{ candidates ->
                        // Recheck immediately before each batch; a previous query may have started a body transfer.
                        val batch = if (automaticDiscovery) candidates.filter {
                            AndroidAgentResultRecovery.eligible(context, it.desktopId, it.payload) &&
                                !AndroidAgentResultRecovery.deferAutomaticDiscovery(context, it.desktopId, it.payload)
                        } else candidates
                        if (batch.isEmpty()) return@batches
                        val first = batch.first()
                        val app = context.applicationContext
                        val recoveryBatch = batch.map { it.copy(handoff = null) }
                        val applied = CompletableDeferred<List<Pair<Int, AgentRemoteRecoveryObservation>>>()
                        val observations = try {
                            client.query(first.desktopId, first.routeId, batch.map { it.payload }, report = { outcome ->
                                if (BuildConfig.DEBUG) Log.i("GalaxySSIRecovery", "query_outcome=$outcome")
                                if (outcome == "response_timeout" || outcome == "publish_rejected") retry()
                            }, timing = com.galaxyssi.chat.metrics.AgentLatencyTelemetry.recovery(context),
                                includeResultPage = !inspectOnly,
                                onResponse = if (inspectOnly) null else { results ->
                                    observationScope.launch {
                                        try {
                                            val accepted = observationSlots.withPermit {
                                                results.mapIndexedNotNull { index, result ->
                                                    observation(app, recoveryBatch[index], result, persist = true)?.let {
                                                        index to it
                                                    }
                                                }
                                            }
                                            applied.complete(accepted)
                                        } catch (cancelled: CancellationException) {
                                            applied.cancel(cancelled)
                                            throw cancelled
                                        } catch (error: Exception) {
                                            applied.completeExceptionally(error)
                                            Log.w("GalaxySSIRecovery", "Observation apply deferred: ${error.javaClass.simpleName}")
                                            AndroidAgentRecoveryWake.request(app)
                                        }
                                    }
                                    Unit
                                }) { payload ->
                                GalaxySSIMqttClient.isRequestReplyReady() && GalaxySSIMqttClient.publishJsonForTransport(payload,
                                    GalaxySSIMqttClient.outgoingTopicFor(first.payload.getString("contact_id")),
                                    first.payload.getString("contact_id"))
                            }
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (error: Exception) {
                            Log.w("GalaxySSIRecovery", "Remote observation batch deferred: ${error.javaClass.simpleName}")
                            retry()
                            emptyList()
                        }
                        if (!inspectOnly && observations.isNotEmpty()) {
                            try {
                                applied.await().forEach { (index, observation) -> add(batch[index] to observation) }
                            } catch (cancelled: CancellationException) {
                                throw cancelled
                            } catch (error: Exception) {
                                Log.w("GalaxySSIRecovery", "Observation persistence deferred: ${error.javaClass.simpleName}")
                                retry()
                            }
                            return@batches
                        }
                        observations.forEachIndexed { index, result ->
                            observation(context, batch[index], result, persist = false, validateCurrent = !inspectOnly)?.let {
                                add(batch[index] to it)
                            }
                        }
                    }
                }
            }

    private fun observation(context: Context, query: Query, result: JSONObject,
        persist: Boolean, validateCurrent: Boolean = true): AgentRemoteRecoveryObservation? {
        val version = AgentRemoteOutcomeCodec.version(result) ?: return null
        if (result.optString("remote_run_id").isBlank() || version.sequence < 0L ||
            result.optString("status") == "unavailable") return null
        val fields = JSONObject(query.payload.toString()).put("execution_generation", version.generation)
            .put("status_sequence", version.sequence).put("task_status", result.optString("status"))
            .put("expected_status", result.optString("status"))
        val identity = AgentRemoteOutcomeCodec.observation(fields) ?: return null
        val terminal = result.optString("status") in AgentRemoteOutcomeCodec.TERMINAL
        val observation = AgentRemoteRecoveryObservation(query.payload.getString("conversation_id"),
            query.desktopId, result.optString("status"), result.optString("task_id"),
            result.optString("remote_run_id"), result.optLong("status_sequence", -1L),
            executionGeneration = version.generation, awaitingTerminalReply = terminal)
        if (observation.workspaceStatus == null || observation.remoteRunId.isBlank() ||
            observation.statusSequence < 0L) return null
        if (validateCurrent) {
            // Pairing, identity and terminal state may have changed since the waiter expired.
            val current = resolveQuery(context, identity.contactId, identity.sourceMessageId,
                identity.conversationId, identity.turnId) ?: return null
            if (current.desktopId != query.desktopId || current.routeId != query.routeId ||
                AgentRemoteRecoveryClient.identity(current.payload) != AgentRemoteRecoveryClient.identity(query.payload) ||
                AgentTerminalDeliveryStore.isTerminal(context, identity.sourceMessageId)) return null
            if (!AgentConnectorResponseStore.isCurrentExecution(context, identity)) return null
        }
        if (persist) {
            if (!AgentConnectorResponseStore.observeExecution(context, identity)) return null
            if (terminal) AndroidAgentResultRecovery.request(context, query.desktopId, fields,
                firstPage = result.optJSONObject("result_page"))
        }
        return observation
    }

    private data class Query(val handoff: AgentHandoffRecord?, val desktopId: String,
        val routeId: String, val payload: JSONObject)
}
