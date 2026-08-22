package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConnectorStreamAttemptRegistryTest {
    @Test
    fun newerAttemptRejectsDelayedUpdatesFromAbandonedAttempt() {
        val registry = AgentConnectorStreamAttemptRegistry()
        val first = update(attempt = 1)
        val fallback = update(attempt = 2)

        assertTrue(registry.accept(first))
        assertTrue(registry.accept(fallback))
        assertFalse(registry.accept(first.copy(content = "late token")))
        assertFalse(registry.isCurrent(first))
        assertTrue(registry.isCurrent(fallback))
    }

    @Test
    fun sameAttemptCanContinueReplacingItsVisibleSnapshot() {
        val registry = AgentConnectorStreamAttemptRegistry()
        val update = update(attempt = 3)

        assertTrue(registry.accept(update))
        assertTrue(registry.accept(update.copy(content = "more text")))
        assertTrue(registry.isCurrent(update))
    }

    @Test
    fun terminalResponseClosesStreamAgainstLateBatches() {
        val registry = AgentConnectorStreamAttemptRegistry()
        val update = update(attempt = 1)
        assertTrue(registry.accept(update))

        registry.close(update.sourceMessageId)

        assertFalse(registry.accept(update.copy(content = "late terminal token")))
        assertFalse(registry.isCurrent(update))
    }

    @Test
    fun legacySingleAttemptStreamsRemainSupported() {
        val registry = AgentConnectorStreamAttemptRegistry()
        val update = update(attempt = 0)

        assertTrue(registry.accept(update))
        assertTrue(registry.isCurrent(update))
    }

    @Test
    fun activeStreamsAreNeverEvictedByClosedHistoryCapacity() {
        val registry = AgentConnectorStreamAttemptRegistry(maxClosedEntries = 16)
        val active = (1L..600L).map { sourceId ->
            update(attempt = 1).copy(sourceMessageId = sourceId)
        }

        active.forEach { assertTrue(registry.accept(it)) }

        active.forEach { assertTrue(registry.isCurrent(it)) }
    }

    private fun update(attempt: Int) = AgentConnectorStreamUpdate(
        sourceMessageId = 42L,
        contactId = "cloud:model",
        content = "partial",
        attemptOrdinal = attempt
    )
}
