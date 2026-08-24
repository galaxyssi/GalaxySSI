package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentConnectorPlanningSnapshotTest {
    @Test
    fun `planning snapshot derives registrations from one target read`() {
        val registry = CountingConnectorRegistry()

        val snapshot = registry.planningSnapshot()

        assertEquals(1, registry.readCount)
        assertEquals("agent-1", snapshot.targets.single().id)
        assertEquals("agent-1", snapshot.registrations.single().agentId)
    }

    private class CountingConnectorRegistry : AgentConnectorRegistry {
        var readCount = 0

        override fun availableTargets(): List<AgentCallableTarget> {
            readCount += 1
            return listOf(
                AgentCallableTarget(
                    id = "agent-$readCount",
                    title = "Agent $readCount",
                    kind = AgentConnectorKind.AGENT,
                    status = AgentConnectorStatus.AVAILABLE,
                    capabilities = listOf(AgentCapability.REASONING)
                )
            )
        }
    }
}
