package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentColdBootRecoveryPolicyTest {
    @Test
    fun onlyActiveExecutionStatusesPauseAfterRestart() {
        assertTrue(AgentColdBootRecoveryPolicy.shouldPause(workspace(AgentWorkspaceStatus.CREATED)))
        assertTrue(AgentColdBootRecoveryPolicy.shouldPause(workspace(AgentWorkspaceStatus.QUEUED)))
        assertTrue(AgentColdBootRecoveryPolicy.shouldPause(workspace(AgentWorkspaceStatus.RUNNING)))
        assertFalse(AgentColdBootRecoveryPolicy.shouldPause(workspace(AgentWorkspaceStatus.WAITING_RESPONSE)))
        assertFalse(AgentColdBootRecoveryPolicy.shouldPause(workspace(AgentWorkspaceStatus.PAUSED)))
        assertFalse(AgentColdBootRecoveryPolicy.shouldPause(workspace(AgentWorkspaceStatus.COMPLETED)))
    }

    @Test
    fun waitingPhoneLinuxTaskPausesButCloudWaitContinues() {
        val phoneLinux = workspace(AgentWorkspaceStatus.WAITING_RESPONSE).copy(
            currentPlanSnapshot = "tool_id=galaxyssi.project.repository.pull"
        )
        val cloud = workspace(AgentWorkspaceStatus.WAITING_RESPONSE).copy(
            currentPlanSnapshot = "tool_id=galaxyssi.cloud.model.chat"
        )

        assertTrue(AgentColdBootRecoveryPolicy.shouldPause(phoneLinux))
        assertFalse(AgentColdBootRecoveryPolicy.shouldPause(cloud))
    }

    @Test
    fun activeSessionBecomesAutomaticallyRecoverableWithoutReplayingTheMutation() {
        val loop = AgentExecutionLoop.create().also { executionLoop ->
            executionLoop.start("task", AgentExecutionLoopBudget(enforceCountLimits = false))
            executionLoop.transition(
                AgentExecutionLoopPhase.ACT,
                reason = "Run phone Linux tool",
                toolCall = true
            )
        }.snapshot
        val original = AgentSessionSnapshot(
            sessionId = "session",
            phase = AgentPhase.EXECUTING,
            currentGoal = "Update project",
            currentScreen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent"),
            currentPlan = null,
            auditTrail = emptyList(),
            lastActionResult = null,
            executionLoopSnapshot = loop,
            processInstanceId = "old-process",
            updatedAtMillis = 1L
        )

        val paused = AgentColdBootRecoveryPolicy.pauseSession(
            snapshot = original,
            processInstanceId = "new-process",
            nowMillis = 2L,
            reason = "Restarted"
        )

        assertEquals(AgentPhase.PAUSED, paused.phase)
        assertEquals("agent-interrupted", paused.lastActionResult?.actionId)
        assertFalse(paused.lastActionResult?.success ?: true)
        assertEquals(AgentExecutionLoopPhase.PAUSED, paused.executionLoopSnapshot?.phase)
        assertEquals(AgentExecutionLoopPhase.ACT, paused.executionLoopSnapshot?.resumePhase)
        assertEquals("new-process", paused.processInstanceId)
        assertTrue(paused.currentPlan == null || paused.currentPlan.hasInterruptedExecutionEvidence())
    }

    private fun workspace(status: AgentWorkspaceStatus) = AgentWorkspace(
        workspaceId = "workspace",
        sessionId = "session",
        conversationId = "conversation",
        taskId = "task",
        status = status
    )

    private fun connectorWait(status: AgentActionStatus = AgentActionStatus.WAITING_RESPONSE): AgentSessionSnapshot {
        val screen = ScreenContext("", pageTitle = "")
        val action = AgentAction("dispatch", AgentActionKind.CALL_CONNECTOR, "codex", AgentRisk.LOW,
            status, "Scoped research")
        return AgentSessionSnapshot("session", AgentPhase.WAITING_RESPONSE, "Goal", screen,
            AgentPlan("Goal", screen, emptyList(), listOf(action)), emptyList(),
            AgentActionResult(action.id, true, "Awaiting", mapOf("awaiting_response" to "true",
                "source_message_id" to "12", "contact_id" to "peer", "conversation_id" to "conversation",
                "remote_task_id" to "task", "turn_id" to "turn", "resource_location" to "desktop")),
            processInstanceId = "old", updatedAtMillis = 1)
    }

    @Test fun coldBootKeepsExactPhonePlannerReplyAdmissibleWithoutRedispatch() {
        val saved = connectorWait()
        val recovered = AgentColdBootRecoveryPolicy.pauseSession(saved, "new", 2, "Restarted")
        assertEquals(AgentPhase.WAITING_RESPONSE, recovered.phase)
        assertEquals(saved.lastActionResult, recovered.lastActionResult)
        assertEquals(saved.currentPlan, recovered.currentPlan)
        assertTrue(AgentConnectorReceiptAdmission.saved(recovered, 12, "peer", "conversation", "turn", "task"))
        assertFalse(AgentConnectorReceiptAdmission.saved(recovered, 13, "peer", "conversation", "turn", "task"))
        assertFalse(AgentConnectorReceiptAdmission.saved(recovered, 12, "peer", "other", "turn", "task"))
    }

    @Test fun durableReceiptSurvivesCrashBeforeActionWaitStateWasSaved() {
        val saved = connectorWait(AgentActionStatus.RUNNING).copy(phase = AgentPhase.EXECUTING)
        val recovered = AgentColdBootRecoveryPolicy.pauseSession(saved, "new", 2, "Restarted")
        assertEquals(AgentPhase.WAITING_RESPONSE, recovered.phase)
        assertEquals(AgentActionStatus.WAITING_RESPONSE, recovered.currentPlan!!.actions.single().status)
        assertFalse(recovered.currentPlan.hasInterruptedExecutionEvidence())
    }

    @Test fun legacyPausedReceiptRequiresAnExistingWaitingWorkspace() {
        val saved = connectorWait().copy(phase = AgentPhase.PAUSED)
        assertEquals(AgentPhase.PAUSED, AgentColdBootRecoveryPolicy.pauseSession(saved, "new", 2, "Restarted").phase)
        val repaired = AgentColdBootRecoveryPolicy.pauseSession(saved, "new", 2, "Restarted", recoverPendingResponse = true)
        assertTrue(AgentConnectorReceiptAdmission.saved(repaired, 12, "peer", "conversation", "turn", "task"))
        val userPaused = saved.copy(lastActionResult = AgentActionResult("agent-paused", false, "User paused"))
        assertFalse(AgentColdBootRecoveryPolicy.belongsToPreviousProcess(userPaused, "new"))
        assertEquals(AgentPhase.PAUSED, AgentColdBootRecoveryPolicy.pauseSession(userPaused, "new", 2,
            "Restarted", recoverPendingResponse = true).phase)
    }

    @Test fun nativeMutationOrMissingReceiptNeverBecomesRemoteWait() {
        val saved = connectorWait(AgentActionStatus.RUNNING)
        val mutation = saved.copy(phase = AgentPhase.EXECUTING, currentPlan = saved.currentPlan!!.copy(
            actions = saved.currentPlan.actions.map { it.copy(kind = AgentActionKind.CALL_NATIVE_TOOL) }))
        val recovered = AgentColdBootRecoveryPolicy.pauseSession(mutation, "new", 2, "Restarted")
        assertEquals(AgentPhase.PAUSED, recovered.phase)
        assertTrue(recovered.currentPlan!!.hasInterruptedExecutionEvidence())
        assertEquals(AgentPhase.PAUSED, AgentColdBootRecoveryPolicy.pauseSession(saved.copy(lastActionResult = null),
            "new", 2, "Restarted").phase)
        assertFalse(AgentColdBootRecoveryPolicy.belongsToPreviousProcess(saved.copy(phase = AgentPhase.CANCELLED), "new"))
    }
}
