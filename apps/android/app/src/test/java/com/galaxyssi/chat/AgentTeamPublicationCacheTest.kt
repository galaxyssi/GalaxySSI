package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentTeamPublicationCacheTest {
    private val snapshot = AgentTeamExecutionSnapshot("run", "team", "conversation", "turn", "agent", "Goal",
        AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.SUCCEEDED, emptyList(), "Answer", updatedAtMillis = 10)

    @Test fun unchangedSnapshotsSkipWorkButCorrectionsAtSameTimestampDoNot() {
        val cache = AgentTeamPublicationCache()
        assertFalse(cache.isCurrent(snapshot))
        cache.mark(snapshot)
        assertTrue(cache.isCurrent(snapshot.copy()))
        assertFalse(cache.isCurrent(snapshot.copy(finalOutput = "Correction")))
        assertFalse(cache.isCurrent(snapshot.copy(paused = true)))
        assertFalse(cache.isCurrent(snapshot.copy(taskId = "another-turn")))
    }

    @Test fun expiryAndBackgroundClearAllowColdRebuild() {
        var now = 0L
        val cache = AgentTeamPublicationCache(clock = { now })
        cache.mark(snapshot)
        now = RuntimeCachePolicy.SENSITIVE_TTL_NANOS - 1
        assertTrue(cache.isCurrent(snapshot))
        now++
        assertFalse(cache.isCurrent(snapshot))
        cache.mark(snapshot)
        RuntimeSensitiveCaches.clearAll()
        assertFalse(cache.isCurrent(snapshot))
    }

    @Test fun capacityAndLargeOutputsDoNotCreateUnboundedRetention() {
        val cache = AgentTeamPublicationCache(capacity = 1)
        cache.mark(snapshot)
        val next = snapshot.copy(supervisorRunId = "other")
        cache.mark(next)
        assertFalse(cache.isCurrent(snapshot))
        assertTrue(cache.isCurrent(next))
        val large = snapshot.copy(finalOutput = "x".repeat(524_289))
        cache.mark(large)
        assertFalse(cache.isCurrent(large))
    }
}
