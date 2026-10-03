package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTeamParentRecoveryPolicyTest {
    @Test fun restoreOnlyAuditedSystemPauseNotUserPauseOrAnotherRun() {
        val original = AgentSessionSnapshot("session", AgentPhase.PAUSED, "Test", ScreenContext("", pageTitle = ""),
            null, listOf(AgentAuditEntry(AgentAuditEvent.TASK_PAUSED,
                "Saved Agent team unavailable; awaiting original outcome", 1)),
            AgentActionResult("dispatch", false, "Awaiting original outcome", metadata = metadata + ("team_state" to "interrupted")),
            updatedAtMillis = 1)
        fun restored(session: AgentSessionSnapshot) = AgentTeamParentRecoveryPolicy.restorePauseMarker(session)
            .lastActionResult!!.metadata[AgentTeamParentRecoveryPolicy.PAUSED] == "true"
        assertTrue(restored(original))
        assertFalse(restored(original.copy(auditTrail = listOf(AgentAuditEntry(AgentAuditEvent.TASK_PAUSED, "User paused", 2)))))
        assertFalse(restored(original.copy(auditTrail = original.auditTrail + AgentAuditEntry(AgentAuditEvent.TASK_CANCELLED, "Stopped", 3))))
        assertFalse(restored(original.copy(lastActionResult = original.lastActionResult!!.copy(
            metadata = original.lastActionResult.metadata + ("team_run_id" to "other")))))
    }
    private val runId = "original-team-run"
    private val source = AgentTeamDispatchIds.sourceMessageId(runId)
    private val metadata = mapOf(
        "resource_location" to "distributed",
        "team_run_id" to runId,
        "source_message_id" to source.toString()
    )

    @Test
    fun onlyDistributedTeamWaitsAreReconciled() {
        assertTrue(AgentTeamParentRecoveryPolicy.isTeamWait(AgentPhase.WAITING_RESPONSE, metadata))
        assertFalse(AgentTeamParentRecoveryPolicy.isTeamWait(AgentPhase.COMPLETED, metadata))
        assertFalse(AgentTeamParentRecoveryPolicy.isTeamWait(AgentPhase.WAITING_RESPONSE,
            metadata + ("resource_location" to "desktop")))
        assertFalse(AgentTeamParentRecoveryPolicy.isTeamWait(AgentPhase.WAITING_RESPONSE,
            metadata - "team_run_id"))
        assertFalse(AgentTeamParentRecoveryPolicy.isTeamWait(AgentPhase.WAITING_RESPONSE,
            metadata + ("source_message_id" to "0")))
    }

    @Test
    fun pausedTeamAcceptsOnlyItsOriginalSource() {
        val paused = metadata + (AgentTeamParentRecoveryPolicy.PAUSED to "true")
        assertTrue(AgentTeamParentRecoveryPolicy.acceptsLateResult(AgentPhase.PAUSED, paused, source))
        assertFalse(AgentTeamParentRecoveryPolicy.acceptsLateResult(AgentPhase.PAUSED, paused, source + 1))
        assertFalse(AgentTeamParentRecoveryPolicy.acceptsLateResult(AgentPhase.PAUSED,
            paused + ("team_run_id" to "another-team"), source))
        assertFalse(AgentTeamParentRecoveryPolicy.acceptsLateResult(AgentPhase.COMPLETED, paused, source))
        assertFalse(AgentTeamParentRecoveryPolicy.acceptsLateResult(AgentPhase.PAUSED, metadata, source))
    }

    @Test
    fun missingInterruptedOrMismatchedTeamsPauseWithoutReplay() {
        assertTrue(AgentTeamParentRecoveryPolicy.shouldPause(null, "conversation", "turn"))
        assertTrue(AgentTeamParentRecoveryPolicy.shouldPause(team(AgentTeamExecutionState.INTERRUPTED), "conversation", "turn"))
        assertTrue(AgentTeamParentRecoveryPolicy.shouldPause(team(AgentTeamExecutionState.SUCCEEDED), "other", "turn"))
        assertTrue(AgentTeamParentRecoveryPolicy.shouldPause(team(AgentTeamExecutionState.RUNNING), "conversation", "other"))
    }

    @Test
    fun liveAndCompletedOriginalTeamsRemainEligible() {
        assertFalse(AgentTeamParentRecoveryPolicy.shouldPause(team(AgentTeamExecutionState.RUNNING), "conversation", "turn"))
        assertFalse(AgentTeamParentRecoveryPolicy.shouldPause(team(AgentTeamExecutionState.SUCCEEDED), "conversation", "turn"))
        assertFalse(AgentTeamParentRecoveryPolicy.shouldPause(team(AgentTeamExecutionState.FAILED), "conversation", "turn"))
    }

    private fun team(state: AgentTeamExecutionState) = AgentTeamExecutionSnapshot(
        supervisorRunId = runId, teamId = "team", conversationId = "conversation", taskId = "turn",
        primaryAgentId = "primary", goal = "Test", visibilityMode = AgentTeamVisibilityMode.VISIBLE,
        state = state, members = emptyList()
    )
}
