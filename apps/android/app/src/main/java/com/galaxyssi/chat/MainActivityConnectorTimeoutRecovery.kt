package com.galaxyssi.chat

import android.util.Log
import kotlinx.coroutines.runBlocking

/** Runs on the timeout worker, never on the UI thread. A missing local event is not a remote timeout. */
internal fun MainActivity.deferConnectorTimeoutForRemoteObservation(runtime: MobileNativeAgent,
    source: Long, conversation: String, turn: String, stage: AgentConnectorTimeoutStage): Boolean {
    val state = runtime.snapshot()
    if (state.phase != AgentPhase.WAITING_RESPONSE) return false
    val pending = AgentProviderAttemptJournal.recover(applicationContext, state.lastActionResult ?: return false)
    if (pending.metadata["source_message_id"]?.toLongOrNull() != source ||
        !AgentConnectorHandoffRecovery.needsPreTimeoutObservation(pending.metadata, stage)) return false
    val delivery = AgentPendingDeliveryStore.find(this, source) ?: return false
    if (delivery.conversationId != conversation || delivery.turnId != turn ||
        !AndroidAgentRemoteRecovery.hasCurrentBinding(this, delivery)) return false
    val observation = runCatching {
        runBlocking { AndroidAgentRemoteRecovery.inspectPendingReply(applicationContext, delivery) }
    }.onFailure { Log.w("GalaxySSIRecovery", "Pre-timeout observation deferred", it) }.getOrNull() ?: return false
    if (!runtime.canAcceptConnectorResponse(source, delivery.contactId, conversation, turn, observation.remoteTaskId)) return true
    runtime.recordConnectorTaskStatus(source, delivery.contactId, observation.remoteTaskId, observation.status,
        observation.statusSequence, conversation, turn, observation.executionGeneration)
    runtime.persistSession()
    AndroidAgentRecoveryWake.request(this)
    // Terminal results use the same durable inbox/fallback path as live responses. Active
    // remote tasks remain owned by their Desktop watchdog, including queued concurrent work.
    if (AgentConnectorHandoffRecovery.needsPreTimeoutObservation(
            runtime.snapshot().lastActionResult?.metadata.orEmpty(), stage)) {
        scheduleConnectorTimeout(runtime, source, conversation, turn, 30_000L, stage)
    }
    return true
}
