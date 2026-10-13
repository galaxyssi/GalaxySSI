package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class AgentModelCallAdmissionTest {
    private val request = AgentModelToolLoopRequest.forUserMessage("session", "conversation", "turn", "task",
        "workspace", "Keep pursuing the original goal", budget = AgentModelToolLoopBudget(
            maxRetriesPerCall = 0, enforceCountLimits = false)).copy(loopId = "call-admission")
    private fun call(id: String, operation: String = "submit") =
        AgentModelToolCall(id, "test.admission", mapOf("operation" to operation))
    private fun registry(execute: (String) -> Unit) = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
        AgentNativeToolDescriptor("test.admission", "1.0.0", "Test", "Test", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
            idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT), AgentNativeToolExecutor {
                execute(it.input["operation"].toString())
                AgentNativeToolExecutionResult.success(mapOf("observed" to true))
            }))

    @Test fun identicalModelResponsesReturnRejectionWithoutRepeatingEffectsOrEndingTheGoal() = runBlocking {
        val executed = mutableListOf<String>()
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                1, 2, 3 -> AgentModelResponse(toolCalls = listOf(call("same")))
                4 -> {
                    assertEquals("tool_call_id_reused", it.messages.last().toolResult?.error?.code)
                    AgentModelResponse(toolCalls = listOf(call("inspect", "inspect")))
                }
                else -> AgentModelResponse("Verified the existing submission.")
            }
        }, registry(executed::add)).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(listOf("submit", "inspect"), executed)
        assertEquals(2, outcome.messages.count { it.toolResult?.error?.code == "tool_call_id_reused" })
        assertTrue(outcome.events.none { it.type == AgentModelToolLoopEventType.LOOP_DETECTED })
        assertTranscriptPairs(outcome.messages)
    }

    @Test fun reusingAnIdForDifferentArgumentsDoesNotExecuteThoseArguments() = runBlocking {
        val executed = mutableListOf<String>()
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                1 -> AgentModelResponse(toolCalls = listOf(call("used", "inspect")))
                2 -> AgentModelResponse(toolCalls = listOf(call("used", "delete")))
                else -> AgentModelResponse("Choose another action after the rejection.")
            }
        }, registry(executed::add)).run(request)
        assertEquals(listOf("inspect"), executed)
        val error = outcome.messages.last { it.toolResult != null }.toolResult!!.error!!
        assertEquals(false, error.details["executed"])
        assertEquals(false, error.details["goal_terminal"])
        assertEquals("used", error.details["original_call_id"])
        assertTranscriptPairs(outcome.messages)
    }

    @Test fun duplicateIdsInOneBatchKeepTheFirstCallAndRejectTheSecond() = runBlocking {
        val executed = mutableListOf<String>()
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            if (it.round == 1) AgentModelResponse(toolCalls = listOf(call("duplicate", "inspect"), call("duplicate", "delete")))
            else AgentModelResponse("The duplicate was rejected.")
        }, registry(executed::add)).run(request)
        assertEquals(listOf("inspect"), executed)
        assertTranscriptPairs(outcome.messages)
    }

    @Test fun invalidIdsGetUniqueTranscriptOnlyAliasesAndNeverExecute() = runBlocking {
        var executions = 0
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            if (it.round == 1) AgentModelResponse(toolCalls = listOf(call(""), call(" "), call("x".repeat(161))))
            else AgentModelResponse("Correct the invalid call IDs.")
        }, registry { executions++ }).run(request)
        assertEquals(0, executions)
        assertEquals(3, outcome.messages.count { it.toolResult?.error?.code == "invalid_tool_call_id" })
        assertTranscriptPairs(outcome.messages)
    }

    @Test fun aliasesAreDeterministicAndCannotCollideWithOtherProposedIds() {
        val first = AgentModelCallAdmission.admit(listOf(call("")), emptySet(), 2)
        assertEquals(first, AgentModelCallAdmission.admit(listOf(call("")), emptySet(), 2))
        val alias = first.calls.single().callId
        val collision = AgentModelCallAdmission.admit(listOf(call(""), call(alias)), emptySet(), 2)
        assertNotEquals(alias, collision.calls.first().callId)
        assertEquals(alias, collision.calls.last().callId)
        assertEquals(1, collision.rejections.size)
    }

    @Test fun rejectionIsNotFreshEvidencePermittingTheSameMutation() = runBlocking {
        var executions = 0
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            when (it.round) {
                1, 2 -> AgentModelResponse(toolCalls = listOf(call("used")))
                3 -> AgentModelResponse(toolCalls = listOf(call("fresh")))
                else -> AgentModelResponse("Inspect before submitting again.")
            }
        }, registry { executions++ }).run(request)
        assertEquals(1, executions)
        assertEquals("repeated_tool_call", outcome.messages.last { it.toolResult != null }.toolResult?.error?.code)
    }

    @Test fun rejectedResponseReplaysWithIdenticalAliasesAndNoRepeatedEffect() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var executions = 0
        try {
            AgentModelToolLoop(AgentModelAdapter {
                if (it.round <= 2) AgentModelResponse(toolCalls = listOf(call("same")))
                else throw CancellationException("Simulated process loss")
            }, registry { executions++ }, journal = journal).run(request)
            fail("Expected interruption")
        } catch (_: CancellationException) { }
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            assertEquals(3, it.round)
            assertEquals("tool_call_id_reused", it.messages.last().toolResult?.error?.code)
            AgentModelResponse("Continue from the saved rejection.")
        }, registry { error("Do not repeat a committed effect") }, journal = journal).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(1, executions)
        assertTranscriptPairs(outcome.messages)
    }

    @Test fun unversionedRecordedResponsesKeepTheirOriginalTranscriptBeforeNewRoundsUpgrade() = runBlocking {
        val backing = InMemoryAgentModelLoopJournal()
        val legacyView = object : AgentModelLoopJournal {
            override fun hasRecords(scope: AgentModelLoopScope) = backing.hasRecords(scope)
            override suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T =
                backing.withLease(scope) { records -> block(object : AgentModelLoopRecords by records {
                    override fun read(operation: String): String? = records.read(operation)?.let {
                        if (operation == "model:1") JSONObject(it).apply { remove("call_admission_version") }.toString() else it
                    }
                }) }
        }
        try {
            AgentModelToolLoop(AgentModelAdapter {
                if (it.round == 1) AgentModelResponse(toolCalls = listOf(call("")))
                else throw CancellationException("Simulated legacy interruption")
            }, registry { error("An invalid call cannot execute") }, journal = legacyView).run(request)
            fail("Expected interruption")
        } catch (_: CancellationException) { }
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            if (it.round == 2) {
                assertEquals("", it.messages.last().toolResult?.callId)
                assertEquals("Tool call id must not be blank", it.messages.last().toolResult?.message)
                AgentModelResponse(toolCalls = listOf(call("")))
            } else {
                assertTrue(it.messages.last().toolResult!!.callId.startsWith("rejected_"))
                AgentModelResponse("New rounds use the current admission contract.")
            }
        }, registry { error("Rejected calls cannot execute") }, journal = legacyView).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
    }

    private fun assertTranscriptPairs(messages: List<AgentModelMessage>) {
        val calls = messages.flatMap { it.toolCalls }.map { it.callId }
        val results = messages.mapNotNull { it.toolResult?.callId }
        assertEquals(calls.size, calls.distinct().size)
        assertEquals(calls, results)
    }
}
