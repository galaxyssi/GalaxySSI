package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class AgentDurableModelLoopTest {
    private val descriptor = AgentNativeToolDescriptor("phone.test.durable", "1.0.0", "Test", "Test",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, setOf("test"), idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT)
    private val request = AgentModelToolLoopRequest("session", "conversation", "turn", "task", "workspace",
        listOf(AgentModelMessage.user("Test durable reasoning")), loopId = "planning-1")
    private val call = AgentModelToolCall("call-1", descriptor.id)

    @Test fun interruptedModelRoundResumesWithTheCommittedObservation() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var executions = 0
        val native = registry { executions++; AgentNativeToolExecutionResult.success(mapOf("answer" to "observed")) }
        try {
            AgentModelToolLoop(AgentModelAdapter { if (it.round == 1) AgentModelResponse(toolCalls = listOf(call))
                else throw CancellationException("process lost") }, native, journal = journal).run(request)
            fail("Expected interruption")
        } catch (_: CancellationException) { }
        val emitted = mutableListOf<AgentModelToolLoopEvent>()
        val resumed = AgentModelToolLoop(AgentModelAdapter {
            assertEquals(2, it.round)
            assertEquals("observed", it.messages.last().toolResult?.output?.get("answer"))
            AgentModelResponse("Finished after observation")
        }, registry { error("A committed tool must not run again") }, journal = journal)
            .run(request.copy(eventSink = AgentModelToolLoopEventSink(emitted::add)))
        assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
        assertEquals(1, executions)
        assertTrue(emitted.none { it.type == AgentModelToolLoopEventType.TOOL_STARTED })
        assertTrue(emitted.filter { it.type == AgentModelToolLoopEventType.MODEL_REQUESTED }.all { it.round == 2 })
    }

    @Test fun completedLoopIsReconstructedWithoutProviderToolsOrDuplicateProgress() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val first = AgentModelToolLoop(adapter(), registry(), journal = journal).run(request)
        val events = mutableListOf<AgentModelToolLoopEvent>()
        val restored = AgentModelToolLoop(AgentModelAdapter { error("No new model request") },
            registry { error("No new tool request") }, journal = journal)
            .run(request.copy(eventSink = AgentModelToolLoopEventSink(events::add)))
        assertEquals(first.assistantText, restored.assistantText)
        assertEquals(first.messages.map { it.role }, restored.messages.map { it.role })
        assertTrue(events.isEmpty())
    }

    @Test fun failedCheckpointCommitCannotAdvanceToAnotherModelRoundOrRepeatTheEffect() = runBlocking {
        val backing = InMemoryAgentModelLoopJournal()
        var failWrite = true
        val broken = object : AgentModelLoopJournal {
            override fun hasRecords(scope: AgentModelLoopScope) = backing.hasRecords(scope)
            override suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T =
                backing.withLease(scope) { records -> block(object : AgentModelLoopRecords by records {
                    override fun write(operation: String, json: String) {
                        if (operation.endsWith(":result") && failWrite) {
                            failWrite = false
                            throw AgentModelLoopRecoveryException("test_disk_failure")
                        }
                        records.write(operation, json)
                    }
                }) }
        }
        var writes = 0
        var modelCalls = 0
        val native = registry { writes++; AgentNativeToolExecutionResult.success(mapOf("saved" to true)) }
        expectRecovery { AgentModelToolLoop(AgentModelAdapter {
            modelCalls++; AgentModelResponse(toolCalls = listOf(call))
        }, native, journal = broken).run(request) }
        assertEquals(1, modelCalls)
        val recovered = AgentModelToolLoop(adapter(), native, journal = backing).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, recovered.status)
        assertEquals(1, writes)
        assertTrue(recovered.messages.first { it.role == AgentModelMessageRole.TOOL }.toolResult!!.receipt!!["replayed"] as Boolean)
    }

    @Test fun aDifferentInputUnderTheSameIdentityCannotReuseAPlan() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        AgentModelToolLoop(adapter(), registry(), journal = journal).run(request)
        expectRecovery { AgentModelToolLoop(adapter(), registry(), journal = journal)
            .run(request.copy(messages = listOf(AgentModelMessage.user("Different goal")))) }
    }

    @Test fun interruptedParallelResultsResumeInModelOrderWithoutRepeatingEffects() = runBlocking {
        val backing = InMemoryAgentModelLoopJournal()
        val firstCommitted = CountDownLatch(1)
        val firstKey = "tool:" + AgentNativeJsonCodec.sha256(listOf(1, "call-1", 1)) + ":result"
        val secondKey = "tool:" + AgentNativeJsonCodec.sha256(listOf(1, "call-2", 1)) + ":result"
        val interrupted = object : AgentModelLoopJournal {
            override fun hasRecords(scope: AgentModelLoopScope) = backing.hasRecords(scope)
            override suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T =
                backing.withLease(scope) { records -> block(object : AgentModelLoopRecords by records {
                    override fun write(operation: String, json: String) {
                        if (operation == secondKey) {
                            check(firstCommitted.await(5, TimeUnit.SECONDS))
                            throw AgentModelLoopRecoveryException("test_partial_batch_commit")
                        }
                        records.write(operation, json)
                        if (operation == firstKey) firstCommitted.countDown()
                    }
                }) }
        }
        val writes = AtomicInteger()
        val native = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor.copy(
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY), AgentNativeToolExecutor {
            writes.incrementAndGet()
            AgentNativeToolExecutionResult.success(mapOf("value" to it.input["value"]))
        }))
        expectRecovery { AgentModelToolLoop(AgentModelAdapter {
            assertEquals(1, it.round)
            AgentModelResponse(toolCalls = listOf(call.copy(arguments = mapOf("value" to "first")),
                call.copy(callId = "call-2", arguments = mapOf("value" to "second"))))
        }, native, journal = interrupted).run(request) }
        val resumed = AgentModelToolLoop(AgentModelAdapter {
            assertEquals(2, it.round)
            assertEquals(listOf("first", "second"), it.messages.filter { m -> m.role == AgentModelMessageRole.TOOL }
                .map { m -> m.toolResult?.output?.get("value") })
            AgentModelResponse("Both observations recovered")
        }, native, journal = backing).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
        assertEquals(2, writes.get())
    }

    @Test fun explicitPlannerInputIdentityRestoresItsOriginalContextSnapshot() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val initial = request.copy(recoveryInputIdentity = "goal-and-revision")
        AgentModelToolLoop(adapter(), registry(), journal = journal).run(initial)
        val restored = AgentModelToolLoop(AgentModelAdapter { error("No model request") }, registry(), journal = journal)
            .run(initial.copy(messages = listOf(AgentModelMessage.user("A fresh screen snapshot"))))
        assertEquals(initial.messages.first(), restored.messages.first())
    }

    @Test fun scopeFieldsAndLoopRevisionHaveSeparateRecordsAndEffectKeys() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var writes = 0
        val native = registry { writes++; AgentNativeToolExecutionResult.success() }
        val scopes = listOf(request, request.copy(sessionId = "another"), request.copy(conversationId = "another"),
            request.copy(turnId = "another"), request.copy(taskId = "another"), request.copy(workspaceId = "another"),
            request.copy(callerId = "another"), request.copy(loopId = "planning-2"))
        scopes.forEach { assertEquals(AgentModelToolLoopStatus.COMPLETED,
            AgentModelToolLoop(adapter(), native, journal = journal).run(it).status) }
        assertEquals(scopes.size, writes)
    }

    @Test fun sameLoopCannotBeOwnedTwice() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val scope = AgentModelLoopScope.from(request)
        journal.withLease(scope) { expectRecovery { journal.withLease(scope) { error("Second owner") } } }
        journal.withLease(scope) { assertNull(it.read("missing")) }
    }

    @Test fun manifestDriftCannotFallThroughToExecution() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        AgentModelToolLoop(adapter(), registry(), journal = journal).run(request)
        expectRecovery { AgentModelToolLoop(adapter(), registry(), disclosedToolManifestJson = "{}",
            disclosedToolManifestSha256 = "different", journal = journal).run(request) }
    }

    @Test fun cancelledLoopCannotRestartWithAFreshCancellationToken() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        journal.withLease(AgentModelLoopScope.from(request)) { AgentModelLoopCheckpoint(it).cancel() }
        val result = AgentModelToolLoop(AgentModelAdapter { error("Cancelled loop") }, registry(), journal = journal).run(request)
        assertEquals(AgentModelToolLoopStatus.CANCELLED, result.status)
    }

    @Test fun manyRoundsRemainRecoverableWithoutLifetimeCountLimits() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var tools = 0
        val native = registry { tools++; AgentNativeToolExecutionResult.success() }
        val longRequest = request.copy(budget = AgentModelToolLoopBudget(maxRounds = 2, maxToolCalls = 2, enforceCountLimits = false))
        val first = AgentModelToolLoop(AgentModelAdapter {
            if (it.round <= 129) AgentModelResponse(toolCalls = listOf(call.copy(callId = "call-${it.round}",
                arguments = mapOf("round" to it.round)))) else AgentModelResponse("All observations complete")
        }, native, journal = journal).run(longRequest)
        val restored = AgentModelToolLoop(AgentModelAdapter { error("Already completed") }, native, journal = journal).run(longRequest)
        assertEquals(130, restored.usage.rounds)
        assertEquals(first.assistantText, restored.assistantText)
        assertEquals(129, tools)
    }

    private fun adapter() = AgentModelAdapter {
        if (it.round == 1) AgentModelResponse(toolCalls = listOf(call)) else AgentModelResponse("Done")
    }
    private fun registry(execute: () -> AgentNativeToolExecutionResult = { AgentNativeToolExecutionResult.success() }) =
        AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor { execute() }))
    private suspend fun expectRecovery(block: suspend () -> Any?) {
        try { block(); fail("Expected a recovery exception") } catch (_: AgentModelLoopRecoveryException) { }
    }
}
