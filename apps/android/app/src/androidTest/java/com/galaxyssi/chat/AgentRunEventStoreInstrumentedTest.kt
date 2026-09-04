package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentRunEventStoreInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = AgentRunEventStore(context)

    @Before
    fun setUp() {
        store.clear()
    }

    @After
    fun cleanUp() {
        store.clear()
    }

    @Test
    fun batchedEventsReceiveConsecutiveSequencesAndOneRecoverableSnapshot() {
        val runId = UUID.randomUUID().toString()
        val events = listOf(
            event(runId, AgentRunControlEventType.RUN_CREATED),
            event(runId, AgentRunControlEventType.RUN_STARTED)
        )

        val appended = store.appendNextAll(events)

        assertEquals(listOf(1L, 2L), appended.map(AgentRunControlEvent::sequence))
        assertEquals(
            listOf(AgentRunControlEventType.RUN_CREATED, AgentRunControlEventType.RUN_STARTED),
            store.events(runId).map(AgentRunControlEvent::type)
        )
        assertEquals(AgentRunControlState.RUNNING, store.snapshot(runId)?.state)
        assertEquals(listOf(runId), store.recoverableRuns().map(AgentRunControlSnapshot::runId))
    }

    private fun event(runId: String, type: AgentRunControlEventType) = AgentRunControlEvent(
        conversationId = "conversation",
        messageId = "message",
        taskId = "task",
        runId = runId,
        agentId = "codex",
        deviceId = "device",
        type = type,
        sequence = 0L
    )
}
