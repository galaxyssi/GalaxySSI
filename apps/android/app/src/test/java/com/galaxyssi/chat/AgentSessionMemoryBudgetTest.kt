package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSessionMemoryBudgetTest {
    @Test
    fun recordsRealIncrementInsteadOfDividingWholeProcessMemory() {
        var now = 1_000L
        val monitor = AgentSessionMemoryBudgetMonitor(
            sampler = queueSampler(mib(120), mib(132)),
            store = InMemoryAgentSessionMemoryBudgetStore(),
            clock = { now.also { now += 100L } }
        )

        val baseline = monitor.begin()
        val snapshot = monitor.complete("conversation-a", baseline)

        assertEquals(mib(12), snapshot.latestIncrementalBytes)
        assertEquals(mib(12), snapshot.peakIncrementalBytes)
        assertEquals(1, snapshot.sampleCount)
        assertEquals(0, snapshot.exceededCount)
        assertEquals("conversation-a", snapshot.latestConversationId)
        assertTrue(snapshot.withinBudget)
    }

    @Test
    fun flagsOnlyTheSessionShellThatExceedsTwentyMibibytes() {
        val monitor = AgentSessionMemoryBudgetMonitor(
            sampler = queueSampler(mib(100), mib(121)),
            store = InMemoryAgentSessionMemoryBudgetStore(),
            clock = { 2_000L }
        )

        val snapshot = monitor.complete("conversation-b", monitor.begin())

        assertEquals(mib(20), snapshot.targetBytes)
        assertEquals(1, snapshot.exceededCount)
        assertFalse(snapshot.withinBudget)
    }

    @Test
    fun garbageCollectionDoesNotProduceNegativeSessionCost() {
        val monitor = AgentSessionMemoryBudgetMonitor(
            sampler = queueSampler(mib(150), mib(140)),
            store = InMemoryAgentSessionMemoryBudgetStore(),
            clock = { 3_000L }
        )

        val snapshot = monitor.complete("conversation-c", monitor.begin())

        assertEquals(0L, snapshot.latestIncrementalBytes)
        assertTrue(snapshot.withinBudget)
    }

    @Test
    fun aggregateKeepsAStableBudgetAcrossManyLightweightSessions() {
        val samples = (1..1_000).map { index ->
            AgentSessionMemoryBudgetSample(
                id = "sample-$index",
                conversationId = "conversation-$index",
                sampledAtMillis = index.toLong(),
                beforeBytes = mib(100),
                afterBytes = mib(100) + index % 10 * 1024L,
                incrementalBytes = index % 10 * 1024L,
                targetBytes = mib(20)
            )
        }

        val snapshot = AgentSessionMemoryBudgetMonitor.aggregate(samples)

        assertEquals(1_000, snapshot.sampleCount)
        assertEquals(0, snapshot.exceededCount)
        assertTrue(snapshot.peakIncrementalBytes < snapshot.targetBytes)
    }

    private fun queueSampler(vararg totals: Long): AgentMemoryPssSampler {
        val queue = ArrayDeque(totals.toList())
        return AgentMemoryPssSampler {
            AgentMemoryPssReading(totalBytes = queue.removeFirst())
        }
    }

    private fun mib(value: Long): Long = value * 1_048_576L
}
