package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimeRecoveryGateTest {
    @Test
    fun `one timeout quarantines a runtime generation once`() {
        val gate = AgentRuntimeRecoveryGate()
        val ready = snapshot(AgentRuntimeLifecyclePhase.READY)
        val first = gate.acquire { ready }
        val second = gate.acquire { ready }
        var stops = 0

        assertTrue(gate.quarantine(first) { stops += 1 })
        assertFalse(gate.quarantine(second) { stops += 1 })
        assertEquals(1, stops)
    }

    @Test
    fun `late timeout cannot stop a recovered guest`() {
        val gate = AgentRuntimeRecoveryGate()
        val oldLease = gate.acquire { snapshot(AgentRuntimeLifecyclePhase.READY) }
        assertTrue(gate.quarantine(oldLease) {})
        val recovered = gate.acquire { snapshot(AgentRuntimeLifecyclePhase.READY) }
        var stops = 0

        assertFalse(gate.quarantine(oldLease) { stops += 1 })
        assertTrue(gate.quarantine(recovered) { stops += 1 })
        assertEquals(1, stops)
    }

    @Test
    fun `acquire returns the lifecycle failure without changing its generation`() {
        val gate = AgentRuntimeRecoveryGate()
        val blocked = gate.acquire { snapshot(AgentRuntimeLifecyclePhase.BLOCKED) }

        assertEquals(AgentRuntimeLifecyclePhase.BLOCKED, blocked.lifecycle.phase)
        assertEquals(0L, blocked.generation)
    }

    private fun snapshot(phase: AgentRuntimeLifecyclePhase) = AgentRuntimeLifecycleSnapshot(
        phase = phase,
        reason = phase.name
    )
}
