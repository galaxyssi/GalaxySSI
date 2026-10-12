package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AgentModelToolEventWaitTest {
    private val descriptor = AgentNativeToolDescriptor("test.external-event", "1.0.0", "Event", "Host event",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY)
    private val request = AgentModelToolLoopRequest("session", "conversation", "turn", "task", "workspace",
        listOf(AgentModelMessage.user("Continue after the external event")), loopId = "loop")
    private val call = AgentModelToolCall("call", descriptor.id)
    private fun registry(execute: () -> AgentNativeToolExecutionResult) = AgentNativeToolRegistry()
        .register(AgentNativeToolDefinition(descriptor, AgentNativeToolExecutor { execute() }))
    private fun resolver(committed: (AgentNativeToolResult) -> Unit = {},
        resolve: (AgentNativeToolResult) -> AgentModelToolEventWait?) =
        object : AgentModelToolEventWaitResolver {
            override fun supports(toolId: String) = toolId == descriptor.id
            override fun resolve(request: AgentModelToolLoopRequest, call: AgentModelToolCall,
                result: AgentNativeToolResult) = resolve(result)
            override fun observationCommitted(request: AgentModelToolLoopRequest, call: AgentModelToolCall,
                result: AgentNativeToolResult) = committed(result)
        }
    private fun pending() = resolver { AgentModelToolEventWait.Pending("event", "Waiting for the user") }

    @Test fun `waiting yields without a timer next model call or terminal completion`() = runBlocking {
        var models = 0
        var tools = 0
        val outcome = AgentModelToolLoop(AgentModelAdapter {
            models++; AgentModelResponse(toolCalls = listOf(call))
        }, registry { tools++; AgentNativeToolExecutionResult.success() }, journal = InMemoryAgentModelLoopJournal(),
            eventWaitResolver = pending()).run(request)
        assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, outcome.status)
        assertFalse(outcome.isTerminal)
        assertEquals(1, models)
        assertEquals(1, tools)
        assertEquals("event", outcome.error!!.details["event_id"])
        assertTrue(outcome.events.any { it.type == AgentModelToolLoopEventType.LOOP_WAITING })
        assertFalse(outcome.events.any { it.type == AgentModelToolLoopEventType.LOOP_COMPLETED })
    }

    @Test fun `repeated recovery while pending never polls the provider or reexecutes the tool`() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call)) },
            registry { AgentNativeToolExecutionResult.success() }, journal = journal, eventWaitResolver = pending()).run(request)
        repeat(20) {
            val outcome = AgentModelToolLoop(AgentModelAdapter { error("No provider polling") },
                registry { error("No repeated takeover") }, journal = journal, eventWaitResolver = pending()).run(request)
            assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, outcome.status)
        }
    }

    @Test fun `resolved event is committed before the model observes it and survives event source loss`() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val native = registry { AgentNativeToolExecutionResult.success(mapOf("control_owner" to "user")) }
        AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call)) }, native,
            journal = journal, eventWaitResolver = pending()).run(request)
        val returned = resolver { AgentModelToolEventWait.Resolved(it.copy(metadata = it.metadata +
            mapOf("external_event" to mapOf("control_owner" to "agent", "authentication_verified" to false)))) }
        try {
            AgentModelToolLoop(AgentModelAdapter {
                assertEquals(2, it.round)
                assertNotNull(it.messages.last().toolResult?.nativeResult?.get("metadata"))
                throw CancellationException("Process ended after event commit")
            }, native, journal = journal, eventWaitResolver = returned).run(request)
            fail("Expected interruption")
        } catch (_: CancellationException) { }
        val resumed = AgentModelToolLoop(AgentModelAdapter {
            assertEquals(2, it.round)
            val metadata = it.messages.last().toolResult!!.nativeResult!!["metadata"] as Map<*, *>
            val event = metadata["external_event"] as Map<*, *>
            assertEquals("agent", event["control_owner"])
            assertEquals(false, event["authentication_verified"])
            AgentModelResponse("Now inspect the page")
        }, registry { error("No repeated effect") }, journal = journal,
            eventWaitResolver = resolver { error("Committed event must not require its live source") }).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, resumed.status)
    }

    @Test fun `waiting tool is a batch barrier even when its descriptor permits parallel reads`() = runBlocking {
        var tools = 0
        val result = AgentModelToolLoop(AgentModelAdapter {
            AgentModelResponse(toolCalls = listOf(call, call.copy(callId = "later")))
        }, registry { tools++; AgentNativeToolExecutionResult.success() }, journal = InMemoryAgentModelLoopJournal(),
            eventWaitResolver = pending()).run(request)
        assertEquals(AgentModelToolLoopStatus.WAITING_FOR_EVENT, result.status)
        assertEquals(1, tools)
    }

    @Test fun `cancellation wins over an external wait`() = runBlocking {
        val token = AgentNativeToolCancellationSource()
        val outcome = AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call)) },
            registry { token.cancel(); AgentNativeToolExecutionResult.success() }, journal = InMemoryAgentModelLoopJournal(),
            eventWaitResolver = resolver { error("Cancellation must not suspend") })
            .run(request.copy(cancellationToken = token.token))
        assertEquals(AgentModelToolLoopStatus.CANCELLED, outcome.status)
    }

    @Test fun `event waiting projects as waiting and never asks for approval`() {
        val projection = AgentModelToolLoopTimelinePolicy.project(AgentModelToolLoopEvent(1,
            AgentModelToolLoopEventType.LOOP_WAITING, 1, "session", "turn", "task", "manifest", 1,
            details = mapOf("message" to "Waiting for the user")))
        assertEquals(AgentModelToolTimelineText.TOOL_WAITING, projection.text)
        assertNotEquals(AgentRunControlEventType.TOOL_PERMISSION_REQUIRED, projection.controlEventType)
    }

    @Test fun `remaining calls in a suspended batch resume in order after the event`() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var tools = 0
        val native = registry { tools++; AgentNativeToolExecutionResult.success() }
        AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call, call.copy(callId = "later"))) },
            native, journal = journal, eventWaitResolver = pending()).run(request)
        assertEquals(1, tools)
        val returned = AgentModelToolLoop(AgentModelAdapter {
            assertEquals(listOf("call", "later"), it.messages.filter { m -> m.toolResult != null }.map { m -> m.toolResult!!.callId })
            AgentModelResponse("Both tools observed")
        }, native, journal = journal, eventWaitResolver = resolver { AgentModelToolEventWait.Resolved(it) }).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, returned.status)
        assertEquals(2, tools)
    }

    @Test fun `failure to commit a returned event cannot advance the provider or repeat the effect`() = runBlocking {
        val backing = InMemoryAgentModelLoopJournal()
        var tools = 0
        val native = registry { tools++; AgentNativeToolExecutionResult.success() }
        AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call)) }, native,
            journal = backing, eventWaitResolver = pending()).run(request)
        val broken = object : AgentModelLoopJournal {
            override fun hasRecords(scope: AgentModelLoopScope) = backing.hasRecords(scope)
            override suspend fun <T> withLease(scope: AgentModelLoopScope, block: suspend (AgentModelLoopRecords) -> T): T =
                backing.withLease(scope) { records -> block(object : AgentModelLoopRecords by records {
                    override fun write(operation: String, json: String) {
                        if (operation.endsWith(":event-result")) throw AgentModelLoopRecoveryException("test_event_disk_failure")
                        records.write(operation, json)
                    }
                }) }
        }
        var committed = 0
        val returned = resolver(committed = { committed++ }) { AgentModelToolEventWait.Resolved(it) }
        try {
            AgentModelToolLoop(AgentModelAdapter { error("No model call before event commit") }, native,
                journal = broken, eventWaitResolver = returned).run(request)
            fail("Expected failed event commit")
        } catch (expected: AgentModelLoopRecoveryException) { assertEquals("test_event_disk_failure", expected.message) }
        assertEquals(0, committed)
        val restored = AgentModelToolLoop(AgentModelAdapter { AgentModelResponse("Returned event observed") }, native,
            journal = backing, eventWaitResolver = returned).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, restored.status)
        assertEquals(1, tools)
        assertEquals(1, committed)
    }

    @Test fun `observation commit callback can recover after its source write fails without replaying a tool`() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        var tools = 0
        val native = registry { tools++; AgentNativeToolExecutionResult.success() }
        AgentModelToolLoop(AgentModelAdapter { AgentModelResponse(toolCalls = listOf(call)) }, native,
            journal = journal, eventWaitResolver = pending()).run(request)
        val failed = resolver(committed = { throw AgentModelLoopRecoveryException("observation_marker_disk_failure") }) {
            AgentModelToolEventWait.Resolved(it)
        }
        try {
            AgentModelToolLoop(AgentModelAdapter { error("No provider call before the host marker") }, native,
                journal = journal, eventWaitResolver = failed).run(request)
            fail("Expected failed marker")
        } catch (expected: AgentModelLoopRecoveryException) {
            assertEquals("observation_marker_disk_failure", expected.message)
        }
        var marked = false
        val restored = AgentModelToolLoop(AgentModelAdapter {
            assertTrue(marked)
            AgentModelResponse("Inspect the browser next")
        }, native, journal = journal, eventWaitResolver = resolver(committed = { marked = true }) {
            error("The event result is already durable")
        }).run(request)
        assertEquals(AgentModelToolLoopStatus.COMPLETED, restored.status)
        assertEquals(1, tools)
    }
}
