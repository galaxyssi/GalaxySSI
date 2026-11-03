package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Rebuild only a waiting receiver from independently persisted, identity-bound team checkpoints. */
internal object AgentTeamClearedParentPolicy {
    fun restore(team: AgentTeamExecutionSnapshot, checkpoint: AgentTeamExecutionCheckpoint,
        workspace: AgentWorkspace, saved: AgentSessionSnapshot, control: AgentTeamUserControl,
        now: Long): AgentSessionSnapshot? = runCatching {
        if (control != AgentTeamUserControl.RUN || team.paused || team.state == AgentTeamExecutionState.CANCELLED ||
            workspace.cancellationRequested || workspace.status !in setOf(AgentWorkspaceStatus.PAUSED, AgentWorkspaceStatus.WAITING_RESPONSE) ||
            workspace.workspaceId != team.taskId || workspace.conversationId != team.conversationId ||
            checkpoint.request.runId != team.supervisorRunId || checkpoint.request.taskId != team.taskId ||
            checkpoint.request.conversationId != team.conversationId || checkpoint.definition.teamId != team.teamId ||
            saved.phase != AgentPhase.OBSERVING || saved.currentGoal.isNotBlank() || saved.currentPlan != null ||
            saved.lastActionResult != null || saved.pendingPlanning != null || saved.auditTrail.isNotEmpty()) return null
        val result = JSONObject(workspace.resultJson)
        val raw = result.getJSONObject("metadata")
        val metadata = raw.keys().asSequence().associateWith { raw.getString(it) }
        val source = AgentTeamDispatchIds.sourceMessageId(team.supervisorRunId)
        if (!AgentTeamParentRecoveryPolicy.acceptsLateResult(AgentPhase.PAUSED, metadata, source) ||
            metadata["team_run_id"] != team.supervisorRunId || metadata["team_id"] != team.teamId ||
            metadata["contact_id"] != AgentTeamDispatchIds.responseContactId(team.teamId)) return null
        val lastControl = workspace.eventJournal.lastOrNull { it.kind in setOf("task.paused", "task.resumed", "task.cancelled") }
        if (lastControl?.kind == "task.cancelled" || lastControl?.kind == "task.paused" &&
            lastControl.message != result.optString("message")) return null
        val loop = result.getJSONObject("execution_loop")
        if (loop.getString("task_id") != team.taskId) return null
        val actionId = loop.getString("last_action_id").takeIf(String::isNotBlank) ?: return null
        val actions = JSONArray(workspace.currentPlanSnapshot)
        val original = (0 until actions.length()).map(actions::getJSONObject).singleOrNull {
            it.optString("id") == actionId && it.optString("kind") == "CALL_CONNECTOR" &&
                it.optString("status") == "WAITING_RESPONSE"
        } ?: return null
        val waitingMetadata = (metadata - AgentTeamParentRecoveryPolicy.PAUSED) + ("team_state" to "interrupted")
        val action = AgentAction(actionId, AgentActionKind.CALL_CONNECTOR, original.getString("target"),
            AgentRisk.LOW, AgentActionStatus.WAITING_RESPONSE, "Await the original team result",
            parameters = mapOf(AGENT_TEAM_SPEC_PARAMETER to AgentTeamDispatchSpecCodec.encode(
                AgentTeamDispatchSpec(checkpoint.definition, team.supervisorRunId)),
                INTERNAL_CONVERSATION_ID to team.conversationId, INTERNAL_TURN_ID to team.taskId),
            requiresConfirmation = false)
        saved.copy(sessionId = workspace.sessionId, phase = AgentPhase.WAITING_RESPONSE, currentGoal = workspace.goal,
            currentPlan = AgentPlan(workspace.goal, saved.currentScreen, emptyList(), listOf(action),
                confirmationRequired = false, plannerProfile = "recovered-team-receiver"),
            lastActionResult = AgentActionResult(actionId, false, result.optString("message"), waitingMetadata),
            executionLoopSnapshot = AgentExecutionLoopJsonCodec.decode(loop.toString())?.let {
                it.copy(phase = AgentExecutionLoopPhase.WAITING_RESPONSE, updatedAtMillis = now,
                    revision = it.revision + 1, lastReason = "Restored original team receiver")
            },
            auditTrail = listOf(AgentAuditEntry(AgentAuditEvent.TASK_RESUMED,
                "Restored original team receiver; no operation replayed", now)), updatedAtMillis = now)
    }.getOrNull()
}

internal class AgentTeamClearedParentRecovery(private val context: Context) {
    fun restore(team: AgentTeamExecutionSnapshot): Boolean {
        if (AgentTranscriptStore(context).conversation(team.conversationId) == null) return false
        val control = AgentTeamDurableControl(context)
        if (control.get(team.supervisorRunId) != AgentTeamUserControl.RUN) return false
        val store = EncryptedAgentWorkspaceStore(context)
        val workspace = store.find(team.taskId) ?: return false
        val sessions = SharedPreferencesAgentSessionStore(context, "task:${team.taskId}")
        val saved = sessions.load() ?: return false
        val checkpoint = EncryptedAgentTeamExecutionStore(context).interruptedCheckpoint(team.supervisorRunId) ?: return false
        val restored = AgentTeamClearedParentPolicy.restore(team, checkpoint, workspace, saved,
            control.get(team.supervisorRunId), System.currentTimeMillis()) ?: return false
        if (!AgentPendingDeliveryStore.restoreTeamParent(context, AgentPendingDelivery(
                AgentTeamDispatchIds.sourceMessageId(team.supervisorRunId), team.conversationId, team.taskId,
                team.taskId, AgentTeamDispatchIds.responseContactId(team.teamId)))) return false
        if (!sessions.restoreIfUnchanged(saved, restored)) return false
        if (control.get(team.supervisorRunId) != AgentTeamUserControl.RUN) return false
        try {
            store.upsert(workspace.copy(status = AgentWorkspaceStatus.WAITING_RESPONSE), expectedRevision = workspace.revision)
        } catch (_: AgentWorkspaceRevisionConflictException) { return false }
        return true
    }
}
