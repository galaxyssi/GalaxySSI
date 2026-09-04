package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentMemoryPssTelemetryTest {
    @Test
    fun processOnlyCaptureDoesNotInventTaskAttribution() {
        val monitor = monitor(readings = listOf(reading(160)))

        val snapshot = monitor.capture(emptyList())

        assertEquals(mib(160), snapshot.processCurrentBytes)
        assertEquals(mib(160), snapshot.processPeakBytes)
        assertTrue(snapshot.byAgent.isEmpty())
        assertTrue(snapshot.bySession.isEmpty())
        assertTrue(snapshot.byProvider.isEmpty())
    }

    @Test
    fun sharedPssIsSplitAcrossActiveTasksAndGroupedByEveryIdentity() {
        val monitor = monitor(readings = listOf(reading(240)))

        val snapshot = monitor.capture(listOf(
            workspace("task-a", "session-a", "conversation-a", "model:deepseek"),
            workspace("task-b", "session-b", "conversation-b", "codex")
        ))

        assertEquals(mib(240), snapshot.processCurrentBytes)
        assertEquals(mib(120), snapshot.byAgent.first { it.id == "model:deepseek" }.currentBytes)
        assertEquals(mib(120), snapshot.bySession.first { it.id == "session-b" }.currentBytes)
        assertEquals(mib(120), snapshot.byProvider.first { it.id == "deepseek" }.currentBytes)
        assertEquals(mib(120), snapshot.byProvider.first { it.id == "codex" }.currentBytes)
        assertTrue(snapshot.byAgent.all { it.estimated })
    }

    @Test
    fun currentAndPeakRemainDistinctAcrossSamples() {
        var now = 1_000L
        val monitor = AgentMemoryPssMonitor(
            sampler = queueSampler(listOf(reading(300), reading(180))),
            store = InMemoryAgentMemoryPssSampleStore(),
            clock = { now.also { now += 1_000L } }
        )
        val workspace = workspace("task", "session", "conversation", "cloud:openai")

        monitor.capture(listOf(workspace))
        val snapshot = monitor.capture(listOf(workspace))

        assertEquals(mib(180), snapshot.processCurrentBytes)
        assertEquals(mib(300), snapshot.processPeakBytes)
        assertEquals(mib(180), snapshot.byProvider.single().currentBytes)
        assertEquals(mib(300), snapshot.byProvider.single().peakBytes)
        assertEquals(mib(240), snapshot.byProvider.single().averageBytes)
    }

    @Test
    fun completedTaskDoesNotRemainAsCurrentMemory() {
        var now = 1_000L
        val monitor = AgentMemoryPssMonitor(
            sampler = queueSampler(listOf(reading(200), reading(150))),
            store = InMemoryAgentMemoryPssSampleStore(),
            clock = { now.also { now += 1_000L } }
        )
        monitor.capture(listOf(workspace("task", "session", "conversation", "codex")))

        val snapshot = monitor.capture(emptyList())

        assertEquals(0L, snapshot.byAgent.single().currentBytes)
        assertEquals(mib(200), snapshot.byAgent.single().peakBytes)
    }

    @Test
    fun retentionRemovesExpiredAndOverflowSamples() {
        val store = InMemoryAgentMemoryPssSampleStore()
        repeat(5) { index ->
            store.append(sample(id = "$index", at = index.toLong() * 1_000L))
        }

        store.prune(beforeMillis = 1_000L, maxSamples = 2)
        val retained = store.recent(limit = 10, sinceMillis = 0L)

        assertEquals(listOf("3", "4"), retained.map { it.id })
    }

    @Test
    fun providerIdentityNormalizesModelsWithoutHidingAgents() {
        assertEquals(
            "deepseek",
            AgentMemoryPssMonitor.providerIdForAgent("model:DeepSeek")
        )
        assertEquals(
            "openai",
            AgentMemoryPssMonitor.providerIdForAgent("provider:OpenAI:gpt-5")
        )
        assertEquals(
            "on-device",
            AgentMemoryPssMonitor.providerIdForAgent("galaxyssi-mobile")
        )
        assertEquals("claude", AgentMemoryPssMonitor.providerIdForAgent("Claude"))
        assertFalse(AgentMemoryPssMonitor.providerIdForAgent("").isNotBlank())
    }

    private fun monitor(readings: List<AgentMemoryPssReading>): AgentMemoryPssMonitor =
        AgentMemoryPssMonitor(
            sampler = queueSampler(readings),
            store = InMemoryAgentMemoryPssSampleStore(),
            clock = { 10_000L }
        )

    private fun queueSampler(readings: List<AgentMemoryPssReading>): AgentMemoryPssSampler {
        val queue = ArrayDeque(readings)
        return AgentMemoryPssSampler { queue.removeFirst() }
    }

    private fun reading(totalMib: Long): AgentMemoryPssReading = AgentMemoryPssReading(
        totalBytes = mib(totalMib),
        nativeBytes = mib(totalMib / 4),
        dalvikBytes = mib(totalMib / 2),
        otherBytes = mib(totalMib / 4)
    )

    private fun workspace(
        taskId: String,
        sessionId: String,
        conversationId: String,
        agentId: String
    ): AgentWorkspace = AgentWorkspace(
        workspaceId = "workspace-$taskId",
        sessionId = sessionId,
        conversationId = conversationId,
        taskId = taskId,
        agentId = agentId
    )

    private fun sample(id: String, at: Long): AgentMemoryPssSample = AgentMemoryPssSample(
        id = id,
        sampledAtMillis = at,
        processTotalBytes = mib(100),
        attributedBytes = 0L,
        nativeBytes = 0L,
        dalvikBytes = 0L,
        otherBytes = 0L,
        measurementKind = AgentMemoryMeasurementKind.ANDROID_PSS.wireName,
        attributionMode = AgentMemoryAttributionMode.PROCESS_TOTAL.wireName
    )

    private fun mib(value: Long): Long = value * 1_048_576L
}
