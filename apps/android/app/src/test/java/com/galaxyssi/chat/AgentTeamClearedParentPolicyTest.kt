package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentTeamClearedParentPolicyTest {
    private val team = AgentTeamExecutionSnapshot("run", "team", "group", "turn", "codex", "Research",
        AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.INTERRUPTED, emptyList())
    private val definition = AgentTeamDefinition("team", "codex", listOf(
        AgentTeamMember("codex", AgentDeliveryMode.RESPOND)), AgentTeamVisibilityMode.VISIBLE)
    private val checkpoint = AgentTeamExecutionCheckpoint(definition,
        AgentRunRequest(runId = "run", taskId = "turn", conversationId = "group", messageId = "turn", goal = "Research"), emptyMap(), 3)
    private val saved = AgentSessionSnapshot("accidental-new-session", AgentPhase.OBSERVING, "",
        ScreenContext("", pageTitle = ""), null, emptyList(), null, updatedAtMillis = 200)
    private val metadata = mapOf("team_run_id" to "run", "team_id" to "team", "resource_location" to "distributed",
        "source_message_id" to AgentTeamDispatchIds.sourceMessageId("run").toString(),
        "contact_id" to AgentTeamDispatchIds.responseContactId("team"), AgentTeamParentRecoveryPolicy.PAUSED to "true")
    private val workspace = AgentWorkspace("turn", "original-session", "group", "turn", goal = "Research",
        status = AgentWorkspaceStatus.PAUSED, resultJson = JSONObject().put("message", "automatic pause")
            .put("metadata", JSONObject(metadata)).put("execution_loop", JSONObject(AgentExecutionLoopJsonCodec.encode(
                AgentExecutionLoop.create { 100 }.apply { start("turn", AgentExecutionLoopBudget()) }.snapshot!!.copy(phase = AgentExecutionLoopPhase.PAUSED,
                    lastActionId = "dispatch")))).toString(),
        currentPlanSnapshot = JSONArray().put(JSONObject().put("id", "dispatch").put("kind", "CALL_CONNECTOR")
            .put("status", "WAITING_RESPONSE").put("target", "Team")).toString(),
        eventJournal = listOf(AgentWorkspaceEvent(kind = "task.paused", message = "automatic pause")))

    private fun restore(w: AgentWorkspace = workspace, s: AgentSessionSnapshot = saved,
        control: AgentTeamUserControl = AgentTeamUserControl.RUN, c: AgentTeamExecutionCheckpoint = checkpoint) =
        AgentTeamClearedParentPolicy.restore(team, c, w, s, control, 300)

    @Test fun restoresOnlyOriginalWaitingReceiverWithoutProposingActions() {
        val result = requireNotNull(restore())
        assertEquals("original-session", result.sessionId)
        assertEquals(AgentPhase.WAITING_RESPONSE, result.phase)
        assertEquals(AgentExecutionLoopPhase.WAITING_RESPONSE, result.executionLoopSnapshot!!.phase)
        assertEquals(100L, result.executionLoopSnapshot.startedAtMillis)
        assertEquals(listOf(AgentActionStatus.WAITING_RESPONSE), result.currentPlan!!.actions.map { it.status })
        assertEquals("run", result.lastActionResult!!.metadata["team_run_id"])
        assertNull(result.lastActionResult.metadata[AgentTeamParentRecoveryPolicy.PAUSED])
        assertEquals("run", AgentTeamDispatchSpecCodec.decode(result.currentPlan.actions.single()
            .parameters.getValue(AGENT_TEAM_SPEC_PARAMETER))!!.supervisorRunId)
    }
    @Test fun neverOverridesUserPauseStopOrCancelledWorkspace() {
        assertNull(restore(control = AgentTeamUserControl.PAUSE))
        assertNull(restore(control = AgentTeamUserControl.STOP))
        assertNull(restore(workspace.copy(cancellationRequested = true)))
        assertNull(restore(workspace.copy(status = AgentWorkspaceStatus.CANCELLED)))
        assertNull(restore(workspace.copy(eventJournal = listOf(AgentWorkspaceEvent(kind = "task.paused", message = "User paused")))))
    }
    @Test fun rejectsWrongConversationTurnRunOrMissingAutomaticPauseProof() {
        assertNull(restore(workspace.copy(conversationId = "other")))
        assertNull(restore(workspace.copy(workspaceId = "other")))
        assertNull(restore(c = checkpoint.copy(request = checkpoint.request.copy(runId = "other"))))
        assertNull(restore(c = checkpoint.copy(request = checkpoint.request.copy(taskId = "other"))))
        assertNull(restore(workspace.copy(resultJson = "{}")))
        assertNull(restore(workspace.copy(currentPlanSnapshot = "[]")))
    }
    @Test fun preservesAnyNewerOrNonemptySession() {
        assertNull(restore(s = saved.copy(currentGoal = "New work")))
        assertNull(restore(s = saved.copy(phase = AgentPhase.PAUSED)))
        assertNull(restore(s = saved.copy(lastActionResult = AgentActionResult("another", true, "done"))))
        assertNull(restore(s = saved.copy(auditTrail = listOf(AgentAuditEntry(AgentAuditEvent.TASK_PAUSED, "User paused", 2)))))
    }

    @Test fun repairsGenericResumeAndWatchdogWithoutRedispatch() {
        val receiver = requireNotNull(restore())
        listOf(AgentActionResult("agent-resumed", true, "Task resumed"),
            AgentActionResult("agent-interrupted", false, "Process interrupted"),
            AgentActionResult("agent-resumed", false, "Assess progress",
                mapOf("failure_kind" to "liveness_assessment_required"))).forEach { lost ->
            val repaired = AgentTeamParentRecoveryPolicy.restoreWaitingIdentity(receiver.copy(lastActionResult = lost))
            assertEquals("run", repaired.lastActionResult!!.metadata["team_run_id"])
            assertEquals("dispatch", repaired.lastActionResult.actionId)
            assertEquals(receiver.currentPlan, repaired.currentPlan)
            assertEquals(AgentLongTaskRecoveryMode.TEAM_RECONCILIATION,
                AgentLongTaskRecoveryPolicy.decide(workspace.copy(status = AgentWorkspaceStatus.WAITING_RESPONSE), repaired)?.mode)
        }
    }

    @Test fun identityRepairRejectsUserControlOtherTasksAndTerminalActions() {
        val receiver = requireNotNull(restore()).copy(lastActionResult = AgentActionResult("agent-resumed", true, "Task resumed"))
        fun unchanged(candidate: AgentSessionSnapshot) = assertEquals(candidate,
            AgentTeamParentRecoveryPolicy.restoreWaitingIdentity(candidate))
        unchanged(receiver.copy(phase = AgentPhase.COMPLETED))
        unchanged(receiver.copy(auditTrail = listOf(AgentAuditEntry(AgentAuditEvent.TASK_PAUSED, "User paused", 400))))
        unchanged(receiver.copy(auditTrail = listOf(AgentAuditEntry(AgentAuditEvent.TASK_CANCELLED, "Stopped", 400))))
        unchanged(receiver.copy(executionLoopSnapshot = receiver.executionLoopSnapshot!!.copy(taskId = "different")))
        unchanged(receiver.copy(lastActionResult = AgentActionResult("new-action", false, "New result")))
        unchanged(receiver.copy(lastActionResult = AgentActionResult("agent-resumed", true, "Other team", mapOf("team_run_id" to "other"))))
        unchanged(receiver.copy(currentPlan = receiver.currentPlan!!.copy(actions = receiver.currentPlan.actions.map {
            it.copy(status = AgentActionStatus.COMPLETED)
        })))
    }
}
