package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentTimerIdentityTest {
    @Test fun newTimerOmitsIdentityAndGuessDoesNotDispatch() {
        assertNull(AgentTimerIdentity.rejection("", null))
        val rejected = requireNotNull(AgentTimerIdentity.rejection("timer-1min", null))
        assertEquals("timer_operation_id_mismatch", rejected["error_code"])
        assertEquals("false", rejected["dispatch_accepted"])
        assertFalse(rejected.containsKey("operation_id"))
        assertTrue(rejected["next_action"].orEmpty().contains("omit operation_id"))
    }

    @Test fun staleIdentityReturnsOnlyCurrentTimerIdentityForInspection() {
        val timer = AgentDeviceOperation("conversation", id = "observed-id", seconds = 60,
            status = "running", dispatched = true)
        assertNull(AgentTimerIdentity.rejection(timer.id, timer))
        val rejected = requireNotNull(AgentTimerIdentity.rejection("stale-id", timer))
        assertEquals(timer.id, rejected["operation_id"])
        assertEquals("running", rejected["timer_state"])
        assertEquals("false", rejected["dispatch_accepted"])
        assertTrue(rejected["next_action"].orEmpty().startsWith("Inspect"))
    }

    @Test fun genericGoalIdentityIsNotATimerIdentity() {
        val goal = AgentDeviceOperation("conversation", id = "goal-id", kind = "agent")
        val rejected = requireNotNull(AgentTimerIdentity.rejection(goal.id, goal))
        assertFalse(rejected.containsKey("operation_id"))
    }

    @Test fun checkpointOwnershipDoesNotDependOnGoalWording() {
        val timer = AgentDeviceOperation("conversation", seconds = 60, sourceTurnId = "turn")
        assertTrue(AgentTimerIdentity.belongsToTurn(timer, "turn"))
        assertFalse(AgentTimerIdentity.belongsToTurn(timer, "other-turn"))
        assertFalse(AgentTimerIdentity.belongsToTurn(timer, ""))
        assertFalse(AgentTimerIdentity.belongsToTurn(timer.copy(kind = "agent"), "turn"))
    }
}
