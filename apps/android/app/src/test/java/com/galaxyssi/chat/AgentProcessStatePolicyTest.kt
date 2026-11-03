package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentProcessStatePolicyTest {
    private fun projection(status: AgentWorkspaceStatus, revision: Long) = AgentProcessCompletionLookup(
        completedAtMillis = 3000L.takeIf { status.isTerminal }, checkedAtElapsedRealtime = 10,
        status = status, startedAtMillis = 1000, conversationId = "conversation", revision = revision)

    @Test fun committedTerminalStatesWinOverEveryStaleRuntimePhase() {
        for ((status, expected) in listOf(AgentWorkspaceStatus.COMPLETED to AgentPhase.COMPLETED,
            AgentWorkspaceStatus.FAILED to AgentPhase.FAILED, AgentWorkspaceStatus.CANCELLED to AgentPhase.CANCELLED)) {
            AgentPhase.entries.forEach { stale ->
                assertEquals(expected, AgentProcessClockPolicy.phase(status, stale))
            }
        }
    }

    @Test fun anAttemptCompletionCannotCompleteTheWholeTurn() {
        for (status in AgentWorkspaceStatus.entries.filterNot { it.isTerminal }) {
            assertTrue(status.name, AgentProcessClockPolicy.isRunning(AgentProcessClockPolicy.phase(status, AgentPhase.COMPLETED)))
        }
    }

    @Test fun anOlderReadCannotOverwriteACommittedCompletion() {
        val done = projection(AgentWorkspaceStatus.COMPLETED, 12)
        assertEquals(done, AgentProcessClockPolicy.merge(done, projection(AgentWorkspaceStatus.WAITING_RESPONSE, 11)))
        assertEquals(done, AgentProcessClockPolicy.merge(done, done.copy(status = null, revision = -1)))
    }

    @Test fun anotherConversationCannotAcknowledgeThisTurn() {
        val waiting = projection(AgentWorkspaceStatus.WAITING_RESPONSE, 2)
        assertEquals(waiting, AgentProcessClockPolicy.merge(waiting,
            projection(AgentWorkspaceStatus.COMPLETED, 3).copy(conversationId = "other")))
    }

    @Test fun aNewCommittedRecoveryCanResumeAStoppedClock() {
        val completed = projection(AgentWorkspaceStatus.FAILED, 4)
        val resumed = AgentProcessClockPolicy.merge(completed, projection(AgentWorkspaceStatus.RUNNING, 5))
        assertNull(resumed.completedAtMillis)
        assertEquals(AgentPhase.EXECUTING, AgentProcessClockPolicy.phase(resumed.status, AgentPhase.FAILED))
        val clock = AgentProcessClock(1000, completed.completedAtMillis)
        clock.observe(resumed.completedAtMillis, AgentProcessClockPolicy.isRunning(AgentProcessClockPolicy.phase(resumed.status, null)))
        assertEquals(4000L, clock.elapsed(5000))
    }

    @Test fun laterCheckpointsDoNotInflateCompletionTime() {
        val done = projection(AgentWorkspaceStatus.COMPLETED, 8)
        val refresh = AgentProcessClockPolicy.merge(done, done.copy(revision = 9, completedAtMillis = 9000,
            startedAtMillis = 500, checkedAtElapsedRealtime = 20))
        assertEquals(3000L, refresh.completedAtMillis)
        assertEquals(500L, refresh.startedAtMillis)
        assertEquals(9L, refresh.revision)
        assertEquals(20L, refresh.checkedAtElapsedRealtime)
    }

    @Test fun activeRuntimeDetailsAreKeptOnlyForARunningWorkspace() {
        assertEquals(AgentPhase.VERIFYING, AgentProcessClockPolicy.phase(AgentWorkspaceStatus.RUNNING, AgentPhase.VERIFYING))
        assertEquals(AgentPhase.WAITING_RESPONSE,
            AgentProcessClockPolicy.phase(AgentWorkspaceStatus.WAITING_RESPONSE, AgentPhase.VERIFYING))
        assertEquals(AgentPhase.WAITING_RESPONSE, AgentProcessClockPolicy.phase(null, AgentPhase.WAITING_RESPONSE))
    }
}
