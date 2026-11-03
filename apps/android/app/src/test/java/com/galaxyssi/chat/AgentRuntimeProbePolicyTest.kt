package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentRuntimeProbePolicyTest {
    @Test fun `missing health evidence retains the shared bridge`() {
        assertFalse(AgentRuntimeProbePolicy.shouldDiscardBridge(
            AgentRuntimeBridgeHealth(false, observationConfirmed = false)))
        assertFalse(AgentRuntimeProbePolicy.shouldDiscardBridge(AgentRuntimeBridgeHealth(true)))
        assertTrue(AgentRuntimeProbePolicy.shouldDiscardBridge(AgentRuntimeBridgeHealth(false)))
    }

    @Test fun `only a stopped engine can be launched by an ordinary start`() {
        assertFalse(AgentRuntimeProbePolicy.mayLaunchEngine(engineRunning = true))
        assertTrue(AgentRuntimeProbePolicy.mayLaunchEngine(engineRunning = false))
    }

    @Test fun `unknown probe is not described as an observed guest failure`() {
        val unknown = AgentRuntimeProbePolicy.unavailableReason(null)
        assertTrue(unknown.contains("unconfirmed"))
        assertTrue(unknown.contains("not restarted"))
        assertEquals(unknown, AgentRuntimeProbePolicy.unavailableReason(
            AgentRuntimeBridgeHealth(false, reason = "No acknowledgement", observationConfirmed = false)))
        assertEquals("Guest API mismatch", AgentRuntimeProbePolicy.unavailableReason(
            AgentRuntimeBridgeHealth(false, reason = "Guest API mismatch")))
        assertTrue(AgentRuntimeProbePolicy.unavailableReason(AgentRuntimeBridgeHealth(false))
            .contains("guest reported"))
    }
}
