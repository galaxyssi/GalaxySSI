package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRecoveryPacingTest {
    @Test fun repeatedWakesCannotCreateUnboundedQueries() {
        var state = AgentRecoveryPacing.State()
        var requests = 0
        for (second in 0 until 24 * 3600) {
            AgentRecoveryPacing.reserve(state, second * 1000L)?.let { state = it; requests++ }
        }
        assertTrue("Unchanged recovery should not poll thousands of times: $requests", requests <= 31)
    }
    @Test fun identicalTerminalResponsesDoNotResetBackoff() {
        var state = AgentRecoveryPacing.observed(AgentRecoveryPacing.State(), "1:3:completed", 0)
        repeat(10) {
            state = requireNotNull(AgentRecoveryPacing.reserve(state, state.nextAt))
            state = AgentRecoveryPacing.observed(state, "1:3:completed", state.nextAt - 1)
        }
        assertEquals(7, state.attempts)
    }
    @Test fun realProgressResetsOnlyItsTaskState() {
        val old = AgentRecoveryPacing.State(7, 3_600_000, "1:3:running")
        val next = AgentRecoveryPacing.observed(old, "1:4:completed", 100)
        assertEquals(0, next.attempts)
        assertEquals(15_100, next.nextAt)
        assertEquals(7, old.attempts)
    }
    @Test fun clockRollbackCannotLeaveRecoveryStuck() {
        assertNotNull(AgentRecoveryPacing.reserve(AgentRecoveryPacing.State(2, 99_999_999), 0))
    }
}
