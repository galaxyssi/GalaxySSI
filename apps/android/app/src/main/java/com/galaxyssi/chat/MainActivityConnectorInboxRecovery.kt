package com.galaxyssi.chat

import android.util.Log

internal fun MainActivity.consumePendingAgentConnectorResponses() = consumePendingAgentConnectorResponsesAsync()

internal fun MainActivity.consumePendingAgentConnectorResponsesAsync() {
    if (isFinishing || isDestroyed || agentRuntimeRecoveryExecutor.isShutdown) return
    if (!agentConnectorResponsesInFlight.add(CONNECTOR_INBOX_DRAIN)) return
    scheduleConnectorInboxPage(afterSequence = 0, throughSequence = null)
}

private fun MainActivity.scheduleConnectorInboxPage(afterSequence: Long, throughSequence: Long?) {
    runCatching {
        agentRuntimeRecoveryExecutor.execute {
            var continued = false
            try {
                if (isFinishing || isDestroyed) return@execute
                val end = throughSequence ?: AgentConnectorResponseStore.highWatermark(applicationContext)
                val page = AgentConnectorResponseStore.pendingPage(applicationContext, afterSequence, end)
                if (page.unreadableCount > 0) {
                    Log.w("GalaxySSIAgent", "Connector inbox retained ${page.unreadableCount} unreadable replies")
                }
                page.responses.forEach { response ->
                    if (isFinishing || isDestroyed) return@execute
                    if (!AgentConnectorResponseStore.contains(applicationContext, response)) return@forEach
                    runtimeForConnectorResponse(
                        sourceMessageId = response.sourceMessageId, contactId = response.contactId,
                        conversationId = response.conversationId, turnId = response.turnId,
                        taskId = response.taskId, restorePersisted = true
                    )
                    consumeAgentConnectorResponse(response)
                }
                if (page.nextSequence > afterSequence && page.nextSequence < end && !isFinishing && !isDestroyed) {
                    // Yield to queued recovery work between bounded pages. New arrivals use the live listener.
                    scheduleConnectorInboxPage(page.nextSequence, end)
                    continued = true
                }
            } catch (error: Exception) {
                Log.w("GalaxySSIAgent", "Connector inbox recovery deferred (${error.javaClass.simpleName})")
            } finally {
                if (!continued) agentConnectorResponsesInFlight.remove(CONNECTOR_INBOX_DRAIN)
            }
        }
    }.onFailure {
        agentConnectorResponsesInFlight.remove(CONNECTOR_INBOX_DRAIN)
    }
}

private const val CONNECTOR_INBOX_DRAIN = "durable-connector-inbox-drain"
