package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentRunEventStoreInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = AgentRunEventStore(context)
    private val testRunIds = mutableSetOf<String>()
    private var retainRunsForRestart = false

    @After
    fun cleanUp() {
        if (!retainRunsForRestart) store.removeRuns(testRunIds)
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
        assertEquals(listOf(runId), store.recoverableRuns().map { it.runId }.filter { it in testRunIds })
    }

    @Test
    fun idempotentReplayIsStoredOnce() {
        val runId = UUID.randomUUID().toString()
        val first = event(runId, AgentRunControlEventType.RUN_STARTED).copy(
            eventId = "event-first",
            idempotencyKey = "event-key",
            actionId = "start-action"
        )
        val replay = first.copy(eventId = "event-replay")

        assertEquals(1L, store.appendNext(first)?.sequence)
        assertEquals(null, store.appendNext(replay))
        assertEquals(1, store.events(runId).size)
    }

    @Test
    fun sameRunCannotCrossClientRouteEvenWithReusedIdempotencyKey() {
        val runId = UUID.randomUUID().toString()
        val first = event(runId, AgentRunControlEventType.RUN_STARTED).copy(
            idempotencyKey = "shared-key",
            clientRouteId = "phone-s26u"
        )
        store.appendNext(first)

        val failure = runCatching {
            store.appendNext(first.copy(
                eventId = "cross-route",
                clientRouteId = "phone-s20u"
            ))
        }.exceptionOrNull()

        assertTrue(failure is IllegalArgumentException)
        assertEquals(1, store.events(runId).size)
    }

    @Test
    fun appendOnlyLedgerRetainsMoreThanLegacyArrayLimitAndPagesInOrder() {
        val runId = UUID.randomUUID().toString()
        val eventCount = 2_051
        val appended = store.appendNextAll((1..eventCount).map { index ->
            event(runId, AgentRunControlEventType.TOOL_PROGRESS).copy(
                eventId = "event-$index",
                idempotencyKey = "event-$index",
                actionId = "action-$index"
            )
        })

        assertEquals(eventCount, appended.size)
        assertEquals(eventCount, store.events(runId).size)
        assertEquals(
            (2_001L..2_051L).toList(),
            store.eventsPage(runId, afterSequence = 2_000L, limit = 100).map { it.sequence }
        )
        assertEquals(eventCount.toLong(), store.snapshot(runId)?.lastSequence)
    }

    @Test
    fun completedRunRejectsLateExactEventAndIgnoresLateAppendNext() {
        val runId = UUID.randomUUID().toString()
        store.appendNext(event(runId, AgentRunControlEventType.RUN_STARTED))
        store.appendNext(event(runId, AgentRunControlEventType.RUN_COMPLETED))

        val late = event(runId, AgentRunControlEventType.TOOL_PROGRESS).copy(sequence = 3L)
        val failure = runCatching { store.append(late) }.exceptionOrNull()

        assertTrue(failure is IllegalStateException)
        assertNull(store.appendNext(late.copy(sequence = 0L)))
        assertEquals(2, store.events(runId).size)
        assertEquals(AgentRunControlState.COMPLETED, store.snapshot(runId)?.state)
    }

    @Test
    fun newFacadeReopensPersistedRunWithoutRewritingHistory() {
        val runId = UUID.randomUUID().toString()
        store.appendNext(event(runId, AgentRunControlEventType.RUN_STARTED))
        val reopened = AgentRunEventStore(context)

        assertEquals(1L, reopened.latestEvent(runId)?.sequence)
        assertEquals(AgentRunControlState.RUNNING, reopened.snapshot(runId)?.state)
        assertEquals(listOf(runId), reopened.recoverableRuns().map { it.runId }.filter { it in testRunIds })
    }

    @Test
    fun checkpointPreservesPausedStateInEncryptedLedger() {
        val runId = UUID.randomUUID().toString()
        store.appendNextAll(listOf(
            event(runId, AgentRunControlEventType.RUN_STARTED),
            event(runId, AgentRunControlEventType.PAUSED),
            event(runId, AgentRunControlEventType.CHECKPOINT_SAVED)
        ))
        assertEquals(AgentRunControlState.PAUSED, store.snapshot(runId)?.state)
        assertEquals(3L, store.snapshot(runId)?.lastSequence)
    }

    @Test
    fun persistForProcessRestart() {
        val runId = InstrumentationRegistry.getArguments().getString("runKernelRecoveryId").orEmpty()
        assumeTrue(runId.startsWith("kernel-process-test-"))
        store.appendNextAll(listOf(
            event(runId, AgentRunControlEventType.RUN_STARTED),
            event(runId, AgentRunControlEventType.PAUSED),
            event(runId, AgentRunControlEventType.CHECKPOINT_SAVED)
        ))
        assertEquals(3L, store.snapshot(runId)?.lastSequence)
        retainRunsForRestart = true
    }

    @Test
    fun recoverAfterProcessRestart() {
        val runId = InstrumentationRegistry.getArguments().getString("runKernelRecoveryId").orEmpty()
        assumeTrue(runId.startsWith("kernel-process-test-"))
        testRunIds += runId
        assertEquals(AgentRunControlState.PAUSED, store.snapshot(runId)?.state)
        assertEquals(listOf(1L, 2L, 3L), store.eventsPage(runId).map { it.sequence })
        assertEquals(4L, store.appendNext(event(runId, AgentRunControlEventType.RUN_RECOVERED))?.sequence)
        assertEquals(AgentRunControlState.RUNNING, store.snapshot(runId)?.state)
    }

    private fun event(runId: String, type: AgentRunControlEventType): AgentRunControlEvent {
        testRunIds += runId
        return AgentRunControlEvent(
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
}
