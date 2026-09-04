package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSessionInterruptionPolicyTest {
    @Test
    fun activeSessionReloadedInsideSameProcessIsNotInterrupted() {
        assertFalse(
            AgentSessionInterruptionPolicy.wasInterrupted(
                snapshot(
                    phase = AgentPhase.EXECUTING,
                    processInstanceId = AgentProcessIdentity.instanceId
                )
            )
        )
    }

    @Test
    fun activeSessionFromPreviousProcessIsInterrupted() {
        assertTrue(
            AgentSessionInterruptionPolicy.wasInterrupted(
                snapshot(
                    phase = AgentPhase.EXECUTING,
                    processInstanceId = "previous-process"
                )
            )
        )
    }

    @Test
    fun waitingSessionIsNotChangedAcrossProcesses() {
        assertFalse(
            AgentSessionInterruptionPolicy.wasInterrupted(
                snapshot(
                    phase = AgentPhase.WAITING_RESPONSE,
                    processInstanceId = "previous-process"
                )
            )
        )
    }

    private fun snapshot(
        phase: AgentPhase,
        processInstanceId: String
    ) = AgentSessionSnapshot(
        sessionId = "session",
        phase = phase,
        currentGoal = "test",
        currentScreen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent"),
        currentPlan = null,
        auditTrail = emptyList(),
        lastActionResult = null,
        processInstanceId = processInstanceId,
        updatedAtMillis = 1L
    )
}
