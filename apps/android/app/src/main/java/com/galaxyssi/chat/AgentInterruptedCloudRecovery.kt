package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal object AgentInterruptedCloudPolicy {
    const val ERROR = "cloud_request_interrupted"

    fun pending(session: AgentSessionSnapshot, processId: String, active: Boolean): AgentAction? {
        if (active || session.phase in setOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED) ||
            session.lastActionResult?.actionId == "agent-paused") return null
        if (session.phase == AgentPhase.FAILED && session.lastActionResult?.metadata?.get("error_code") != ERROR) return null
        if (session.processInstanceId == processId && session.lastActionResult?.actionId != "agent-interrupted" &&
            session.phase != AgentPhase.PAUSED &&
            session.lastActionResult?.metadata?.get("error_code") != ERROR) return null
        return session.currentPlan?.actions?.singleOrNull { action ->
            action.kind == AgentActionKind.CALL_CONNECTOR &&
                (action.parameters["connector_adapter_type"] == "cloud-model-api" ||
                    action.parameters["connector_id"].orEmpty().startsWith("cloud:")) &&
                (action.status == AgentActionStatus.WAITING_RESPONSE ||
                    (action.status == AgentActionStatus.RUNNING && session.lastActionResult?.actionId == action.id &&
                        session.lastActionResult?.metadata?.get("awaiting_response") == "true") ||
                    (action.status == AgentActionStatus.FAILED && session.lastActionResult?.metadata?.get("error_code") == ERROR))
        }
    }

    fun finish(session: AgentSessionSnapshot, action: AgentAction, processId: String,
               now: Long, message: String): AgentSessionSnapshot {
        val result = AgentActionResult(action.id, false, message,
            session.lastActionResult?.takeIf { it.actionId == action.id }?.metadata.orEmpty() + mapOf(
                "error_code" to ERROR, "non_retriable" to "true", "recovery_exhausted" to "true",
                "awaiting_response" to "false", "resource_location" to "cloud"))
        return session.copy(phase = AgentPhase.FAILED,
            currentPlan = session.currentPlan?.markAction(action.id, AgentActionStatus.FAILED, result),
            lastActionResult = result, processInstanceId = processId, updatedAtMillis = now,
            executionLoopSnapshot = session.executionLoopSnapshot?.let { loop ->
                loop.copy(phase = AgentExecutionLoopPhase.FAILED, lastReason = message, lastActionId = action.id,
                    updatedAtMillis = now, usage = loop.usage.copy(activeSinceMillis = 0L), revision = loop.revision + 1)
            })
    }
}

/** A phone HTTP request cannot survive process death. Preserve committed inbox results; never replay tools. */
internal object AgentInterruptedCloudRecovery {
    private const val CHECKPOINT = "cloud-interruption-projected-v1"

    internal fun checkpoint(workspace: AgentWorkspace, now: Long) = AgentWorkspaceCheckpoint(
        CHECKPOINT, eventSequence = workspace.eventSequence, stateJson = "{}", createdAtMillis = now)

    fun reconcile(context: Context): Int {
        val app = AppLanguage.wrap(context.applicationContext)
        val workspaces = EncryptedAgentWorkspaceStore(app)
        val transcript = AgentTranscriptStore(app)
        val active = AgentTaskRuntime.activeWorkspaceIds()
        val deliveries = mutableListOf<AgentPendingDelivery>()
        var cursor: Long? = null
        do {
            val page = AgentPendingDeliveryStore.page(app, cursor)
            deliveries += page.deliveries
            cursor = page.nextBeforeSource
        } while (cursor != null)
        var count = 0
        workspaces.list().filter { it.workspaceId !in active && !it.cancellationRequested &&
            it.status !in setOf(AgentWorkspaceStatus.COMPLETED, AgentWorkspaceStatus.CANCELLED) &&
            it.checkpoints.none { checkpoint -> checkpoint.id == CHECKPOINT } }.forEach { workspace ->
            val sessions = SharedPreferencesAgentSessionStore(app, "task:${workspace.workspaceId}")
            val session = sessions.load() ?: return@forEach
            val action = AgentInterruptedCloudPolicy.pending(session, AgentProcessIdentity.instanceId,
                AgentCloudDispatchRegistry.hasActive(workspace.conversationId, workspace.taskId)) ?: return@forEach
            val source = session.lastActionResult?.metadata?.get("source_message_id")?.toLongOrNull()
            val contact = action.parameters["connector_id"].orEmpty()
            val pending = deliveries.filter { it.conversationId == workspace.conversationId &&
                it.turnId == workspace.taskId && it.contactId == contact }
            if (pending.any { AgentConnectorResponseStore.hasReceivedDelivery(app, it.sourceMessageId, it.contactId) } ||
                (source != null && AgentConnectorResponseStore.hasReceivedDelivery(app, source, contact))) return@forEach
            if (transcript.conversation(workspace.conversationId) == null) return@forEach
            val message = app.getString(R.string.agent_cloud_request_interrupted, action.target)
            val now = System.currentTimeMillis()
            val finished = if (session.lastActionResult?.metadata?.get("error_code") == AgentInterruptedCloudPolicy.ERROR)
                session else AgentInterruptedCloudPolicy.finish(session, action, AgentProcessIdentity.instanceId, now, message)
            sessions.save(finished)
            AgentRecoveryTranscript.project(app, workspace, AgentRecoveryTranscript.state(finished), transcript)
            pending.forEach {
                AgentTerminalDeliveryStore.mark(app, it, message)
                AgentPendingDeliveryStore.remove(app, it.sourceMessageId)
                AgentGlobalRunSlotStore(app).releaseBySourceMessageId(it.sourceMessageId)
            }
            workspaces.upsert(workspace.copy(status = AgentWorkspaceStatus.FAILED, errorMessage = message,
                resultJson = JSONObject().put("phase", "FAILED").put("message", message)
                    .put("metadata", JSONObject(finished.lastActionResult?.metadata.orEmpty())).toString(),
                checkpoints = workspace.checkpoints + checkpoint(workspace, now),
                updatedAtMillis = now), expectedRevision = workspace.revision)
            count++
        }
        return count
    }
}
