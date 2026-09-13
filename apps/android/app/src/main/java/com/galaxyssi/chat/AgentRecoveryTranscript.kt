package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** A result commit can be retried without entering the model or action dispatcher. */
internal object AgentRecoveryTranscript {
    const val CHECKPOINT_ID = "recovery-transcript-v1"

    fun pendingCheckpoint(workspace: AgentWorkspace, session: AgentSessionSnapshot): String = JSONObject()
        .put("pending", true)
        .put("workspace_id", workspace.workspaceId)
        .put("conversation_id", workspace.conversationId)
        .put("turn_id", workspace.taskId)
        .put("session_id", session.sessionId)
        .put("phase", session.phase.name)
        .put("updated_at", session.updatedAtMillis)
        .put("loop_revision", session.executionLoopSnapshot?.revision ?: 0L)
        .toString()

    fun needsProjection(workspace: AgentWorkspace, session: AgentSessionSnapshot): Boolean {
        if (workspace.status.isTerminal || workspace.cancellationRequested ||
            workspace.conversationId.isBlank() || workspace.taskId.isBlank() || session.sessionId.isBlank()) return false
        val pending = workspace.checkpoints.lastOrNull { it.id == CHECKPOINT_ID }
            ?.stateJson?.let { runCatching { JSONObject(it) }.getOrNull() }
        if (pending?.optBoolean("pending") == true &&
            pending.optString("workspace_id") == workspace.workspaceId &&
            pending.optString("conversation_id") == workspace.conversationId &&
            pending.optString("turn_id") == workspace.taskId &&
            pending.optString("session_id") == session.sessionId &&
            pending.optString("phase") == session.phase.name &&
            pending.optLong("updated_at", -1L) == session.updatedAtMillis &&
            pending.optLong("loop_revision", -1L) == (session.executionLoopSnapshot?.revision ?: 0L)) return true
        // The runtime commits its session before the worker can mark projection pending.
        return session.phase in setOf(AgentPhase.COMPLETED, AgentPhase.FAILED, AgentPhase.CANCELLED) &&
            session.executionLoopSnapshot?.taskId == workspace.taskId
    }

    fun project(context: Context, workspace: AgentWorkspace, state: AgentUiState, store: AgentTranscriptStore) {
        require(workspace.conversationId.isNotBlank() && workspace.taskId.isNotBlank())
        checkNotNull(store.conversation(workspace.conversationId)) { "Recovery conversation no longer exists" }
        check(store.entriesForTurn(workspace.taskId).any {
            it.role == AgentTranscriptRole.USER && it.conversationId == workspace.conversationId
        }) { "Recovery turn does not belong to the conversation" }
        context.persistAgentTranscript(state, workspace.conversationId, workspace.taskId, store)
    }

    fun commit(project: () -> Unit, persistWorkspace: () -> Unit, acknowledge: () -> Unit) {
        project()
        persistWorkspace()
        acknowledge()
    }

    /** Read-only display adapter: no runtime construction, tool discovery or memory retrieval. */
    fun state(session: AgentSessionSnapshot): AgentUiState {
        val context = AgentRuntimeContext(session.sessionId, session.currentGoal, session.currentScreen,
            PermissionMode.OBSERVE_ONLY, true, false, emptyList(), callableTargets = emptyList(),
            memories = emptyList(), knowledgeItems = emptyList(), knowledgeStats = AgentKnowledgeStats())
        return AgentUiState(session.phase, session.currentGoal, session.currentScreen,
            taskExecutionMode = session.taskExecutionMode, permissionMode = context.permissionMode,
            highRiskGuard = context.highRiskGuard, callableTargets = emptyList(), runtimeContext = context,
            runningTaskCount = 0, steps = session.currentPlan?.steps.orEmpty(),
            lastEvent = AgentEvent.GOAL_RECEIVED, sessionId = session.sessionId, plan = session.currentPlan,
            pendingAction = session.currentPlan?.actions?.firstOrNull {
                session.phase == AgentPhase.WAITING_CONFIRMATION && it.status == AgentActionStatus.PENDING_CONFIRMATION
            }, auditTrail = session.auditTrail, lastActionResult = session.lastActionResult,
            executionLoop = session.executionLoopSnapshot)
    }
}
