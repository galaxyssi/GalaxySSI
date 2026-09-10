package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentMemoryRetractionDeliveryTest {
    @Test fun corruptRetractionsDoNotBlockOrdinaryGlobalEvents() {
        var reported = false
        val result = AgentMemoryRetractionDeliveryPolicy.loadPending(false, { error("corrupt reference") }, { reported = true })
        assertTrue(reported)
        assertTrue(result.isEmpty())
    }

    @Test fun dedicatedRecoveryDoesNotHideReadFailures() {
        assertNotNull(runCatching {
            AgentMemoryRetractionDeliveryPolicy.loadPending(true, { error("corrupt reference") }, { error("Must propagate") })
        }.exceptionOrNull())
    }

    @Test fun cancellationIsNeverSwallowedAsAnEmptyOutbox() {
        assertTrue(runCatching {
            AgentMemoryRetractionDeliveryPolicy.loadPending(false, { throw kotlinx.coroutines.CancellationException() }, { error("Must propagate") })
        }.exceptionOrNull() is kotlinx.coroutines.CancellationException)
    }

    private val event = AgentMemoryCausalDeletionPolicy.retractionEvents(
        AgentMemoryCausalDeletionPolicy.tombstone(listOf(AgentMemoryItem(AgentMemoryKind.PREFERENCE,
            "\u4e2d\u6587\u6d4b\u8bd5", id = "one", key = "key", timestampMillis = 1)), 2)!!).first()

    @Test fun disabledGlobalAgentDoesNotReadOrSchedule() {
        AgentMemoryRetractionDeliveryPolicy.requestIfEnabled({ false }, { error("Must not scan") }, { error("Must not schedule") })
    }

    @Test fun enabledGlobalAgentSchedulesOnlyPendingWork() {
        var count = 0
        AgentMemoryRetractionDeliveryPolicy.requestIfEnabled({ true }, { false }, { count++ })
        assertEquals(0, count)
        AgentMemoryRetractionDeliveryPolicy.requestIfEnabled({ true }, { true }, { count++ })
        assertEquals(1, count)
    }

    @Test fun deletionRetriesAreNotAbandonedAfterThreeFailures() {
        var failure: GlobalEventProcessingFailure? = null
        repeat(10) {
            failure = AgentMemoryRetractionDeliveryPolicy.retainFailure(
                GlobalEventRetryPolicy.recordFailure(event.id, failure, IllegalStateException("storage busy"), 1_000L + it))
            assertFalse(failure!!.quarantined)
            assertTrue(failure!!.nextAttemptAtMillis > failure!!.lastFailedAtMillis)
        }
        assertEquals(10, failure!!.attemptCount)
    }

    @Test fun retryBackoffDoesNotBlockOrdinaryEvents() {
        val failure = AgentMemoryRetractionDeliveryPolicy.retainFailure(
            GlobalEventRetryPolicy.recordFailure(event.id, null, IllegalStateException(), 1_000))
        val ordinary = event.copy(id = "ordinary", type = GlobalConversationEventType.MESSAGE_CREATED, metadata = emptyMap())
        assertEquals(listOf(ordinary), AgentMemoryRetractionDeliveryPolicy.select(listOf(event), listOf(ordinary), listOf(failure), 100, 2_000))
        assertEquals(listOf(event, ordinary), AgentMemoryRetractionDeliveryPolicy.select(listOf(event), listOf(ordinary), listOf(failure), 100, failure.nextAttemptAtMillis))
    }

    @Test fun legacyQueueDuplicatesAreProcessedOncePerBatch() {
        assertEquals(listOf(event), AgentMemoryRetractionDeliveryPolicy.select(listOf(event), listOf(event), emptyList(), 100, 3))
    }

    @Test fun boundedBatchDoesNotImposeARetentionLimit() {
        val events = (0 until 300).map { event.copy(id = "memory-causal-deletion:record:$it") }
        assertEquals(250, AgentMemoryRetractionDeliveryPolicy.select(events, emptyList(), emptyList(), 999, 3).size)
        assertEquals(300, events.size)
    }

    @Test fun retractionsContainNoPersonalMemoryText() {
        assertEquals("", event.content)
        assertTrue(AgentMemoryRetractionDeliveryPolicy.isRetraction(event))
        assertFalse(AgentMemoryRetractionDeliveryPolicy.isRetraction(event.copy(type = GlobalConversationEventType.MESSAGE_CREATED)))
    }
}
