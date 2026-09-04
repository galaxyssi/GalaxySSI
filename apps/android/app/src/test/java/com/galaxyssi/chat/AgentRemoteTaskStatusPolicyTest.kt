package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRemoteTaskStatusPolicyTest {
    @Test
    fun failedTerminalEventsSettleWithoutAResponse() {
        listOf("failed", "cancelled", "timed_out", "not_found").forEach { status ->
            assertTrue(AgentRemoteTaskStatusPolicy.isTerminal(status))
            assertTrue(AgentRemoteTaskStatusPolicy.settlesWithoutResponse(status))
        }
        assertTrue(AgentRemoteTaskStatusPolicy.isTerminal("completed"))
        assertFalse(AgentRemoteTaskStatusPolicy.settlesWithoutResponse("completed"))
        assertFalse(AgentRemoteTaskStatusPolicy.isTerminal("running"))
    }

    @Test
    fun terminalEventAlwaysGetsACompletionTimestamp() {
        assertEquals(
            120L,
            AgentRemoteTaskStatusPolicy.completionTimestamp(
                status = "timed_out",
                declaredCompletedAtMillis = 0L,
                updatedAtMillis = 120L,
                observedAtMillis = 130L
            )
        )
        assertEquals(
            130L,
            AgentRemoteTaskStatusPolicy.completionTimestamp(
                status = "failed",
                declaredCompletedAtMillis = 0L,
                updatedAtMillis = 0L,
                observedAtMillis = 130L
            )
        )
        assertEquals(
            0L,
            AgentRemoteTaskStatusPolicy.completionTimestamp(
                status = "running",
                declaredCompletedAtMillis = 100L,
                updatedAtMillis = 120L,
                observedAtMillis = 130L
            )
        )
    }

    @Test
    fun terminalStatusMapsToVisibleTerminalPhase() {
        assertEquals(AgentPhase.COMPLETED, AgentRemoteTaskStatusPolicy.phase("COMPLETED"))
        assertEquals(AgentPhase.CANCELLED, AgentRemoteTaskStatusPolicy.phase(" cancelled "))
        assertEquals(AgentPhase.FAILED, AgentRemoteTaskStatusPolicy.phase("timed_out"))
        assertEquals(
            AgentWorkspaceStatus.FAILED,
            AgentRemoteTaskStatusPolicy.workspaceStatus("not_found")
        )
    }

    @Test
    fun failedStatusDoesNotResetResourceHealth() {
        listOf("failed", "cancelled", "timed_out", "not_found").forEach { status ->
            assertFalse(AgentRemoteTaskStatusPolicy.keepsResourceHealthy(status))
        }
        listOf("accepted", "running", "completed").forEach { status ->
            assertTrue(AgentRemoteTaskStatusPolicy.keepsResourceHealthy(status))
        }
    }

    @Test
    fun restoredTaskUsesOnlyItsRemainingDeadline() {
        assertEquals(
            2_000L,
            AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(
                deadlineMillis = 10_000L,
                startedAtMillis = 2_000L,
                nowMillis = 10_000L
            )
        )
        assertEquals(
            0L,
            AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(
                deadlineMillis = 10_000L,
                startedAtMillis = 2_000L,
                nowMillis = 20_000L
            )
        )
        assertEquals(
            10_000L,
            AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(
                deadlineMillis = 10_000L,
                startedAtMillis = 0L,
                nowMillis = 20_000L
            )
        )
    }
}
