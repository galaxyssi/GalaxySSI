package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentFailureRecoveryTest {
    @Test
    fun payloadRoundTripsBoundedRecoveryContext() {
        val payload = AgentFailureRecoveryPayload(
            action = AgentFailureRecoveryAction.SWITCH_AGENT,
            taskId = "task-1",
            conversationId = "conversation-1",
            turnId = "turn-1",
            agentId = "codex",
            originalGoal = "Build the project",
            failure = "Codex is unavailable"
        )

        assertEquals(payload, AgentFailureRecoveryPayload.decode(payload.encode()))
        assertNull(AgentFailureRecoveryPayload.decode("{}"))
    }

    @Test
    fun policyRecommendsTheMatchingRecoveryPath() {
        assertEquals(
            AgentFailureRecoveryAction.RETRY,
            AgentFailureRecoveryPolicy.recommended("timed_out", "Execution timed out")
        )
        assertEquals(
            AgentFailureRecoveryAction.SWITCH_AGENT,
            AgentFailureRecoveryPolicy.recommended("failed", "Agent unavailable")
        )
        assertEquals(
            AgentFailureRecoveryAction.DEGRADE,
            AgentFailureRecoveryPolicy.recommended("failed", "Verification failed")
        )
        assertEquals(
            AgentFailureRecoveryAction.DIAGNOSTICS,
            AgentFailureRecoveryPolicy.recommended("failed", "Permanent failure")
        )
    }

    @Test
    fun safeFallbackAndDiagnosticsAlwaysCompileToPlanOnly() {
        assertEquals(
            AgentTaskExecutionMode.PLAN_ONLY,
            AgentFailureRecoveryPolicy.executionMode(AgentFailureRecoveryAction.DEGRADE)
        )
        assertEquals(
            AgentTaskExecutionMode.PLAN_ONLY,
            AgentFailureRecoveryPolicy.executionMode(AgentFailureRecoveryAction.DIAGNOSTICS)
        )
        assertNull(AgentFailureRecoveryPolicy.executionMode(AgentFailureRecoveryAction.RETRY))
    }

    @Test
    fun recoveryInstructionPreservesGoalAndFailure() {
        val instruction = AgentFailureRecoveryPolicy.instruction(
            AgentFailureRecoveryPayload(
                action = AgentFailureRecoveryAction.RETRY,
                taskId = "task-1",
                conversationId = "conversation-1",
                turnId = "turn-1",
                agentId = "codex",
                originalGoal = "Build the app",
                failure = "Network unavailable"
            ),
            chinese = false
        )

        assertTrue(instruction.contains("latest safe checkpoint"))
        assertTrue(instruction.contains("Build the app"))
        assertTrue(instruction.contains("Network unavailable"))
    }
}
