package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentManagedResponseCodecTest {
    @Test fun everyTerminalOutcomeAndExecutionVersionSurvivesLedgerRoundTrip() {
        for (status in AgentRemoteOutcomeCodec.TERMINAL + "") {
            for (generation in listOf(1L, 7L, 9_007_199_254_740_991L)) {
                for (sequence in listOf(-1L, 0L, 91L)) {
                    val expected = record.copy(response = response.copy(taskStatus = status,
                        success = status.isBlank() || status == "completed",
                        executionGeneration = generation, statusSequence = sequence))
                    assertEquals(expected, AgentManagedResponseCodec.decode(
                        AgentManagedResponseCodec.encode(listOf(expected)).toString()).single())
                }
            }
        }
    }

    @Test fun legacyReceiptsKeepTheirOriginalFailureWithoutInventingAStatusOrGeneration() {
        val encoded = AgentManagedResponseCodec.encode(listOf(record.copy(response = response.copy(success = false))))
        val body = encoded.getJSONObject(0).getJSONObject("response")
        listOf("task_status", "execution_generation", "status_sequence").forEach(body::remove)
        val restored = requireNotNull(AgentManagedResponseCodec.decode(encoded.toString()).single().response)
        assertFalse(restored.success)
        assertEquals("", restored.taskStatus)
        assertEquals(1L, restored.executionGeneration)
        assertEquals(-1L, restored.statusSequence)
    }

    @Test fun aTerminalFailureCannotBecomeSuccessfulFromAnInconsistentBoolean() {
        val encoded = AgentManagedResponseCodec.encode(listOf(record))
        encoded.getJSONObject(0).getJSONObject("response").put("task_status", "cancelled").put("success", true)
        val restored = requireNotNull(AgentManagedResponseCodec.decode(encoded.toString()).single().response)
        assertFalse(restored.success)
        assertTrue(restored.remoteFailure)
        assertEquals("cancelled", restored.taskStatus)
    }

    @Test fun malformedExecutionVersionsAndNonterminalReceiptsAreNotAcceptedAsCompletedRecords() {
        for ((key, value) in listOf("execution_generation" to 0L, "execution_generation" to "2",
            "status_sequence" to -2L, "task_status" to "running")) {
            val encoded = AgentManagedResponseCodec.encode(listOf(record))
            encoded.getJSONObject(0).getJSONObject("response").put(key, value)
            assertTrue(AgentManagedResponseCodec.decode(encoded.toString()).isEmpty())
        }
    }

    private val response = AgentConnectorResponse(123, "local-llm", "Public receipt", "conversation", "turn", "task",
        inputTokens = 12, outputTokens = 13, costMicros = 14, richOutputJson = "{}", receivedAtMillis = 21,
        resolvedContactId = "selected-profile")
    private val record = AgentManagedResponseRecord("owner", "supervisor", "member", AgentDeliveryMode.OBSERVE,
        response.sourceMessageId, response.contactId, response.conversationId, response.turnId, response.taskId,
        AgentManagedResponseState.COMPLETED, response, createdAtMillis = 10, completedAtMillis = 21)
}
