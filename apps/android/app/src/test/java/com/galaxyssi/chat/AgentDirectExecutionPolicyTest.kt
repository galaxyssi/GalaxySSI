package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentDirectExecutionPolicyTest {
    @Test
    fun cloudConnectorDoesNotWaitForUiThread() {
        assertFalse(AgentDirectExecutionPolicy.requiresUiThread(action(AgentActionKind.CALL_CONNECTOR)))
    }

    @Test
    fun AndroidSystemActionStillUsesUiThread() {
        assertTrue(AgentDirectExecutionPolicy.requiresUiThread(action(AgentActionKind.CALL_NATIVE_TOOL)))
    }

    private fun action(kind: AgentActionKind): AgentAction = AgentAction(
        id = "test-action",
        kind = kind,
        target = "test",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "test"
    )
}
