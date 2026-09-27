package com.galaxyssi.chat

import android.content.Context

internal object ScreenAssistantTaskCancellation {
    /** Never use the currently selected conversation or a default runtime as a fallback. */
    fun cancel(context: Context, conversationId: String, turnId: String, runner: MainActivity?): Boolean {
        if (conversationId.isBlank() || turnId.isBlank()) return true
        val supervisor = AgentTaskRuntime.supervisor(context)
        val workspace = supervisor.findWorkspace(turnId)
        require(workspace == null || workspace.conversationId == conversationId) {
            "Screen analysis task identity does not match"
        }
        PhoneAssistantTaskControl.cancel(turnId)
        if (workspace?.status in setOf(AgentWorkspaceStatus.COMPLETED, AgentWorkspaceStatus.FAILED)) return true
        val runtime = runner?.let { activity ->
            (activity.activeAgentTasks.values + activity.provisionalAgentTasks + activity.mobileNativeAgent)
                .distinct().firstOrNull {
                    activity.agentRuntimeTurnIds[it] == turnId &&
                        activity.agentRuntimeConversationIds[it] == conversationId
                }
        }
        var remoteDelivered = true
        if (runtime != null && runner != null) {
            val state = runtime.snapshot()
            supervisor.cancelWorkspace(turnId, "User stopped screen analysis")
            remoteDelivered = if (state.lastActionResult?.metadata?.get("resource_location") == "cloud") true
                else runner.publishRemoteAgentTaskCancellation(state) != false
            AgentCloudDispatchRegistry.cancel(state.lastActionResult)
            PhoneExecutionAuthority.requestCancellation(state.sessionId)
            val cancelled = runtime.cancelCurrentTask()
            runner.persistAgentWorkspaceSnapshot(turnId, cancelled, runtime)
        } else {
            supervisor.cancelWorkspace(turnId, "User stopped screen analysis")
            // An Activity can have been recreated while the durable remote task is still running.
            var cursor: Long? = null
            do {
                val page = AgentPendingDeliveryStore.page(context, cursor)
                page.deliveries.filter { it.turnId == turnId && it.conversationId == conversationId }
                    .forEach { delivery ->
                        val sent = GalaxySSIMqttClient.publishAgentTaskCancel(
                            taskId = delivery.taskId, contactId = delivery.contactId,
                            sourceMessageId = delivery.sourceMessageId,
                            conversationId = conversationId, turnId = turnId,
                            topicOverride = AppStore.outgoingTopicForContact(context, delivery.contactId)
                        )
                        remoteDelivered = remoteDelivered && sent
                    }
                cursor = page.nextBeforeSource
            } while (cursor != null)
        }
        runner?.runOnUiThread {
            runner.pendingAgentReplyIndicators.remove(turnId)
            runner.refreshAgentTranscriptWindow(conversationId)
        }
        return remoteDelivered
    }
}
