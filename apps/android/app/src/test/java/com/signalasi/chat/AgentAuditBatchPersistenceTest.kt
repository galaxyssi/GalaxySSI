package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentAuditBatchPersistenceTest {
    @Test
    fun `batch preserves order and persists once`() {
        val trail = mutableListOf<AgentAuditEntry>()
        var timestamp = 100L
        var persistCount = 0
        var persistedEvents = emptyList<AgentAuditEvent>()

        AgentAuditBatchPersistence.appendAndPersist(
            auditTrail = trail,
            records = listOf(
                AgentAuditRecord(AgentAuditEvent.REASONING_SUMMARY, "reason"),
                AgentAuditRecord(AgentAuditEvent.GOAL_RECEIVED, "goal"),
                AgentAuditRecord(AgentAuditEvent.ACTION_EXECUTED, "done")
            ),
            maxItems = 20,
            timestampMillis = { timestamp++ }
        ) {
            persistCount += 1
            persistedEvents = trail.map(AgentAuditEntry::event)
        }

        assertEquals(1, persistCount)
        assertEquals(
            listOf(
                AgentAuditEvent.REASONING_SUMMARY,
                AgentAuditEvent.GOAL_RECEIVED,
                AgentAuditEvent.ACTION_EXECUTED
            ),
            persistedEvents
        )
        assertEquals(listOf(100L, 101L, 102L), trail.map(AgentAuditEntry::timestampMillis))
    }

    @Test
    fun `batch trims oldest entries before persistence`() {
        val trail = MutableList(4) { index ->
            AgentAuditEntry(AgentAuditEvent.SCREEN_OBSERVED, "old-$index", index.toLong())
        }
        var persistedDetails = emptyList<String>()

        AgentAuditBatchPersistence.appendAndPersist(
            auditTrail = trail,
            records = listOf(
                AgentAuditRecord(AgentAuditEvent.TOOL_STARTED, "new-1"),
                AgentAuditRecord(AgentAuditEvent.TOOL_COMPLETED, "new-2")
            ),
            maxItems = 4,
            timestampMillis = { 10L }
        ) {
            persistedDetails = trail.map(AgentAuditEntry::detail)
        }

        assertEquals(listOf("old-2", "old-3", "new-1", "new-2"), persistedDetails)
    }

    @Test
    fun `empty batch does not persist`() {
        var persisted = false

        AgentAuditBatchPersistence.appendAndPersist(
            auditTrail = mutableListOf(),
            records = emptyList(),
            maxItems = 20
        ) {
            persisted = true
        }

        assertTrue(!persisted)
    }
}
