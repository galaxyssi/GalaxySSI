package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AgentModelHistoryLoopTest {
    private val request = AgentModelToolLoopRequest.forUserMessage("s", "c", "t", "task", "w",
        "Inspect old observations and continue the original task", budget = AgentModelToolLoopBudget(enforceCountLimits = false))
        .copy(loopId = "history-loop")
    private fun tool(id: String, effect: AgentNativeToolEffect = AgentNativeToolEffect.READ_ONLY,
        execute: () -> AgentNativeToolExecutionResult) = AgentNativeToolDefinition(AgentNativeToolDescriptor(
        id, "1.0.0", "Public fixture", "Public evidence", AgentNativeToolLocation.APPLICATION,
        AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
        effect = effect), AgentNativeToolExecutor { execute() })
    private fun call(id: String, tool: String, input: AgentNativeJsonObject = emptyMap()) =
        AgentModelResponse(toolCalls = listOf(AgentModelToolCall(id, tool, input)))

    @Test fun restoredLoopRetrievesTheOriginalEvidenceWithoutRepeatingTheUnderlyingOperation() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var reads = 0
        fun registry() = AgentNativeToolRegistry().register(tool("public.read") {
            reads++; AgentNativeToolExecutionResult.success(mapOf("proof" to "public-proof-123"))
        }).register(AgentModelHistoryTools.definition())
        try {
            AgentModelToolLoop(AgentModelAdapter { when (it.round) {
                1 -> call("read", "public.read")
                2 -> call("history-page", AgentModelHistoryTools.ID)
                else -> throw CancellationException("Simulated interruption")
            } }, registry(), journal = journal).run(request)
            fail("Expected interruption")
        } catch (_: CancellationException) { }
        val outcome = AgentModelToolLoop(AgentModelAdapter { response ->
            when (response.round) {
                3 -> {
                    val page = response.messages.last().toolResult!!
                    val record = ((page.output["entries"] as List<*>).single() as Map<*, *>)["record"]
                    call("detail", AgentModelHistoryTools.ID, mapOf("record" to record, "path" to "/observation/output/proof"))
                }
                else -> {
                    assertEquals("public-proof-123", response.messages.last().toolResult!!.output["text"])
                    AgentModelResponse("Original evidence recovered without repeating work")
                }
            }
        }, registry(), journal = journal).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(1, reads)
    }

    @Test fun pastHistoryCannotUnlockAnUnknownMutationOutcome() = runBlocking {
        var submissions = 0
        val registry = AgentNativeToolRegistry().register(tool("public.submit", AgentNativeToolEffect.MUTATION) {
            submissions++
            AgentNativeToolExecutionResult.failure("effect_outcome_unknown", "Inspect the external operation")
        }).register(AgentModelHistoryTools.definition())
        val outcome = AgentModelToolLoop(AgentModelAdapter { when (it.round) {
            1 -> call("first", "public.submit")
            2 -> call("past", AgentModelHistoryTools.ID)
            3 -> call("second", "public.submit")
            else -> {
                assertEquals("repeated_tool_call", it.messages.last().toolResult?.error?.code)
                AgentModelResponse("Need a current external-state observation")
            }
        } }, registry).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
        assertEquals(1, submissions)
    }

    @Test fun parallelReadersUseOneObservedPrefixAndNeverSeeTheirOwnResults() = runBlocking {
        val registry = AgentNativeToolRegistry().register(tool("public.read") {
            AgentNativeToolExecutionResult.success(mapOf("proof" to "parallel-public"))
        }).register(AgentModelHistoryTools.definition())
        val outcome = AgentModelToolLoop(AgentModelAdapter { when (it.round) {
            1 -> call("read", "public.read")
            2 -> AgentModelResponse(toolCalls = listOf(AgentModelToolCall("history-a", AgentModelHistoryTools.ID),
                AgentModelToolCall("history-b", AgentModelHistoryTools.ID, mapOf("tool_id" to "public.read"))))
            else -> {
                val history = it.messages.mapNotNull { message -> message.toolResult }.filter { result -> result.toolId == AgentModelHistoryTools.ID }
                assertEquals(2, history.size)
                history.forEach { result -> assertEquals(1, result.output["snapshot_observations"]) }
                AgentModelResponse("Verified parallel reads")
            }
        } }, registry).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, outcome.status)
    }
}
