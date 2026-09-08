package com.galaxyssi.chat

import android.util.Log

internal fun MainActivity.finishAgentDeliveryFailure(
    sourceMessageId: Long,
    contactId: String,
    binding: PendingDirectConnectorRun
) {
    if (AgentConnectorResponseStore.hasReceivedDelivery(this, sourceMessageId, contactId)) return
    val message = getString(R.string.agent_message_not_delivered)
    val delivery = AgentDeliveryFailureRecorder.record(
        this,
        sourceMessageId,
        contactId,
        message
    ) ?: AgentPendingDelivery(
        sourceMessageId = sourceMessageId,
        conversationId = binding.conversationId,
        turnId = binding.turnId,
        taskId = binding.taskId,
        contactId = binding.contactId
    ).also { fallback ->
        AgentTerminalDeliveryStore.mark(this, fallback, message)
        agentTranscriptStore.upsert(
            role = AgentTranscriptRole.ASSISTANT,
            text = message,
            dedupeKey = AgentDeliveryFailureRecorder.dedupeKey(sourceMessageId),
            conversationId = fallback.conversationId,
            turnId = fallback.turnId,
            taskId = fallback.taskId
        )
    }
    AgentPendingDeliveryStore.remove(this, sourceMessageId)
    runOnUiThread { finishAgentDeliveryFailureUi(delivery) }
}

internal fun MainActivity.finishAgentDeliveryFailureUi(delivery: AgentPendingDelivery) {
    // Direct connector runs also have a runtime snapshot; retire only this exact turn.
    agentRuntimeConversationIds.entries.toList().filter { (runtime, conversation) ->
        conversation == delivery.conversationId && agentRuntimeTurnIds[runtime] == delivery.turnId
    }.forEach { (runtime, _) ->
        runtime.handleConnectorDeliveryFailure(delivery.sourceMessageId,
            getString(R.string.agent_message_not_delivered), allowFallback = false)?.let { state ->
            val terminal = finalizeAgentExecutionLoop(runtime, delivery.turnId, state)
            persistAgentWorkspaceSnapshot(delivery.turnId, terminal, runtime)
            renderAgentState(terminal, delivery.conversationId, delivery.turnId, syncTranscript = false)
        }
    }
    pendingAgentReplyIndicators.remove(delivery.turnId)
    liveAgentConnectorStreams.remove(delivery.sourceMessageId)
    pendingAgentConnectorStreamUpdates.remove(delivery.sourceMessageId)
    deleteAgentTranscriptByDedupeKey(delivery.conversationId, "connector-turn:${delivery.turnId}")
    clearAgentTaskWatchdogTranscript(delivery.conversationId, delivery.turnId)
    if (delivery.conversationId == agentTranscriptStore.activeConversation().id) {
        refreshAgentTranscriptWindow(delivery.conversationId)
        refreshAgentConversationHeader()
    }
}

internal fun logDeliveryFailure(sourceMessageId: Long, contactId: String, reason: String) {
    Log.e(
        "GalaxySSILink",
        "Delivery failed source=$sourceMessageId contact=$contactId reason=$reason"
    )
}
