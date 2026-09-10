package com.galaxyssi.chat

import android.util.Log
import android.os.SystemClock

internal fun MainActivity.consumePendingAgentConnectorResponses() = consumePendingAgentConnectorResponsesAsync()

internal fun MainActivity.consumePendingAgentConnectorResponsesAsync() {
    if (isFinishing || isDestroyed || agentRuntimeRecoveryExecutor.isShutdown) return
    if (!agentConnectorResponsesInFlight.add(CONNECTOR_INBOX_DRAIN)) return
    scheduleConnectorInboxPage(afterSequence = 0, throughSequence = null)
}

private fun MainActivity.scheduleConnectorInboxPage(afterSequence: Long, throughSequence: Long?) {
    val scheduledAt = SystemClock.elapsedRealtime()
    runCatching {
        agentRuntimeRecoveryExecutor.execute {
            var continued = false
            try {
                if (isFinishing || isDestroyed) return@execute
                val startedAt = SystemClock.elapsedRealtime()
                val end = throughSequence ?: AgentConnectorResponseStore.highWatermark(applicationContext)
                val page = AgentConnectorResponseStore.pendingPage(applicationContext, afterSequence, end)
                Log.i("GalaxySSIStartup", "connector_inbox_page queue=${startedAt - scheduledAt}ms " +
                    "read=${SystemClock.elapsedRealtime() - startedAt}ms replies=${page.responses.size}")
                if (page.unreadableCount > 0) {
                    Log.w("GalaxySSIAgent", "Connector inbox retained ${page.unreadableCount} unreadable replies")
                }
                page.responses.forEach { response ->
                    if (isFinishing || isDestroyed) return@execute
                    if (!AgentConnectorResponseStore.contains(applicationContext, response)) return@forEach
                    val restoreStartedAt = SystemClock.elapsedRealtime()
                    runtimeForConnectorResponse(
                        sourceMessageId = response.sourceMessageId, contactId = response.contactId,
                        conversationId = response.conversationId, turnId = response.turnId,
                        taskId = response.taskId, restorePersisted = true
                    )
                    val consumeStartedAt = SystemClock.elapsedRealtime()
                    consumeAgentConnectorResponse(response)
                    Log.i("GalaxySSIStartup", "connector_inbox_dispatch " +
                        "restore=${consumeStartedAt - restoreStartedAt}ms " +
                        "consume=${SystemClock.elapsedRealtime() - consumeStartedAt}ms")
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
