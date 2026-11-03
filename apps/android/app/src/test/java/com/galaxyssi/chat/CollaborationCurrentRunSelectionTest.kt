package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationCurrentRunSelectionTest {
    private fun team(id: String, state: AgentTeamExecutionState, at: Long, research: Boolean = false) =
        AgentTeamExecutionSnapshot(id, "team", "group", id, "agent", "goal", AgentTeamVisibilityMode.VISIBLE, state,
            listOf(AgentTeamMemberSnapshot("agent", "role", AgentDeliveryMode.RESPOND, AgentSubagentStatus.RUNNING,
                researchStage = if (research) "explore" else "")), createdAtMillis = at)

    @Test fun completedFollowupCannotHideInterruptedLongGoal() {
        val original = team("original", AgentTeamExecutionState.INTERRUPTED, 1, true)
        val followup = team("followup", AgentTeamExecutionState.SUCCEEDED, 2)
        assertEquals(original, CollaborationCurrentStatePolicy.current(listOf(original, followup)))
        assertEquals(original, CollaborationCurrentStatePolicy.current(listOf(followup, original)))
    }

    @Test fun activeFollowupDoesNotReplaceResearchRecoveryOrUserPause() {
        val original = team("original", AgentTeamExecutionState.INTERRUPTED, 1, true).copy(paused = true)
        assertEquals(original, CollaborationCurrentStatePolicy.current(listOf(original, team("followup", AgentTeamExecutionState.RUNNING, 2))))
    }

    @Test fun finishedResearchReleasesHeaderToNewestTurnButContinuingGoalsStayVisible() {
        val original = team("original", AgentTeamExecutionState.SUCCEEDED, 1, true)
        val latest = team("latest", AgentTeamExecutionState.SUCCEEDED, 2)
        assertEquals(latest, CollaborationCurrentStatePolicy.current(listOf(original, latest)))
        for (disposition in listOf("continue", "blocked")) {
            val continuing = original.copy(goalDisposition = disposition)
            assertEquals(continuing, CollaborationCurrentStatePolicy.current(listOf(continuing, latest)))
        }
        assertEquals(latest, CollaborationCurrentStatePolicy.current(listOf(original.copy(state = AgentTeamExecutionState.CANCELLED,
            goalDisposition = "continue"), latest)))
        assertNull(CollaborationCurrentStatePolicy.current(emptyList()))
    }
}
