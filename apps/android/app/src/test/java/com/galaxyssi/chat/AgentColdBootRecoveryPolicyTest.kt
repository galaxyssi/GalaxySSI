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
}
