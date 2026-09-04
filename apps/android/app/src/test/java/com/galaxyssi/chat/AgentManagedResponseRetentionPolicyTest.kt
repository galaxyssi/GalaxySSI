package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentManagedResponseRetentionPolicyTest {
    @Test
    fun unresolvedResponsesAreNeverEvictedByTheHistoryLimit() {
        val pending = (0 until 20).map { index -> record("pending-$index", AgentManagedResponseState.PENDING, index) }
        val completed = (0 until 20).map { index ->
            record("completed-$index", AgentManagedResponseState.COMPLETED, 100 + index, response = response(100 + index))
        }
        val applied = (0 until 20).map { index ->
            record("applied-$index", AgentManagedResponseState.APPLIED, 200 + index, response = response(200 + index))
        }

        val retained = AgentManagedResponseRetentionPolicy.retain(
            pending + completed + applied,
            nowMillis = NOW,
            maxAppliedHistoryRecords = 5
        )

        assertEquals(
            pending.map { it.ownerRunId }.toSet(),
            retained.filter { it.state == AgentManagedResponseState.PENDING }.map { it.ownerRunId }.toSet()
        )
        assertEquals(
            completed.map { it.ownerRunId }.toSet(),
            retained.filter { it.state == AgentManagedResponseState.COMPLETED }.map { it.ownerRunId }.toSet()
        )
        assertEquals(
            (15 until 20).map { "applied-$it" },
            retained.filter { it.state == AgentManagedResponseState.APPLIED }.map { it.ownerRunId }
        )
    }

    @Test
    fun appliedHistoryDropsResponseBodiesButKeepsCorrelationTombstones() {
        val retained = AgentManagedResponseRetentionPolicy.retain(
            listOf(record("applied", AgentManagedResponseState.APPLIED, 1, response(1))),
            nowMillis = NOW
        ).single()

        assertEquals("applied", retained.ownerRunId)
        assertNull(retained.response)
    }

    @Test
    fun staleRecordsExpireRegardlessOfState() {
        val stale = record(
            ownerRunId = "stale-pending",
            state = AgentManagedResponseState.PENDING,
            index = 1,
            createdAtMillis = NOW - EIGHT_DAYS_MILLIS
        )

        assertTrue(AgentManagedResponseRetentionPolicy.retain(listOf(stale), nowMillis = NOW).isEmpty())
    }

    private fun record(
        ownerRunId: String,
        state: AgentManagedResponseState,
        index: Int,
        response: AgentConnectorResponse? = null,
        createdAtMillis: Long = NOW - 1_000L + index
    ) = AgentManagedResponseRecord(
        ownerRunId = ownerRunId,
        supervisorRunId = "supervisor",
        agentId = "agent",
        deliveryMode = AgentDeliveryMode.RESPOND,
        sourceMessageId = index + 1L,
        contactId = "contact",
        state = state,
        response = response,
        createdAtMillis = createdAtMillis,
        completedAtMillis = if (state == AgentManagedResponseState.PENDING) 0L else createdAtMillis
    )

    private fun response(index: Int) = AgentConnectorResponse(
        sourceMessageId = index + 1L,
        contactId = "contact",
        content = "result-$index",
        receivedAtMillis = NOW - 1_000L + index
    )

    private companion object {
        const val NOW = 2_000_000_000_000L
        const val EIGHT_DAYS_MILLIS = 8L * 24L * 60L * 60L * 1_000L
    }
}
