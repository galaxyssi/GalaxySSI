package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentBrowserModelEventWaitTest {
    private val request = AgentModelToolLoopRequest("session", "conversation", "turn", "task", "workspace",
        listOf(AgentModelMessage.user("Read after sign-in")), loopId = "loop")
    private val context = AgentNativeToolInvocationContext("invocation", "session", "conversation", "turn",
        request.callerId, attributes = mapOf("workspace_id" to "workspace", "task_id" to "task"))
    private val scope = AgentInteractiveBrowserTools.scope(context)
    private val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "browser"), "generation", scope,
        "session", "conversation", "turn", request.callerId, "workspace", "browser", "page", "handoff", "active",
        "task", "loop", "run", "run-owner", runPlanningBinding = "planning-binding")
    private val call = AgentModelToolCall("call", AgentInteractiveBrowserTools.ACT,
        mapOf("operation" to "request_user_control", "session_id" to "browser", "page_id" to "page"))
    private fun result() = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
        AgentNativeToolDescriptor(call.toolId, "1.0.0", "Test", "Test", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW),
        AgentNativeToolExecutor { AgentNativeToolExecutionResult.success(mapOf("durable_resume_available" to true,
            "host_wait_key" to record.key, "host_wait_generation" to record.generation)) }))
        .invoke(call.toolId, call.arguments, context)
    private fun resolver(value: AgentBrowserUserRequest? = record, owned: Boolean = true) =
        AgentBrowserModelEventWaitResolver({ value }, { owned })

    @Test fun `only a host-bound takeover suspends the loop`() {
        assertTrue(resolver().resolve(request, call, result()) is AgentModelToolEventWait.Pending)
        assertNull(resolver().resolve(request, call.copy(toolId = AgentInteractiveBrowserTools.OBSERVE), result()))
        assertNull(resolver().resolve(request, call.copy(arguments = call.arguments + ("operation" to "navigate")), result()))
        assertNull(resolver().resolve(request, call, result().copy(output = mapOf("durable_resume_available" to false))))
        assertNull(resolver().resolve(request, call, result().copy(output = emptyMap())))
    }

    @Test fun `all identity dimensions and generation must match before waiting or returning`() {
        listOf(record.copy(generation = "other"), record.copy(sessionId = "other"), record.copy(conversationId = "other"),
            record.copy(turnId = "other"), record.copy(callerId = "other"), record.copy(workspaceId = "other"),
            record.copy(taskId = "other"), record.copy(modelLoopId = "other"), record.copy(browserSessionId = "other"),
            record.copy(pageId = "other"), null).forEach { changed ->
            val resolution = resolver(changed).resolve(request, call, result()) as AgentModelToolEventWait.Resolved
            val event = resolution.result.metadata["external_event"] as Map<*, *>
            assertEquals("browser_wait_binding_changed", event["code"])
            assertEquals("unknown", event["control_owner"])
            assertEquals(false, event["goal_terminal"])
        }
        val unknown = resolver(owned = false).resolve(request, call, result()) as AgentModelToolEventWait.Resolved
        assertEquals("browser_control_unobserved", (unknown.result.metadata["external_event"] as Map<*, *>)["kind"])
    }

    @Test fun `returned control is an event not proof of login or a modified tool receipt`() {
        val original = result()
        val resumed = resolver(record.copy(state = "returned")).resolve(request, call, original)
            as AgentModelToolEventWait.Resolved
        val event = resumed.result.metadata["external_event"] as Map<*, *>
        assertEquals("browser_control_returned", event["kind"])
        assertEquals(false, event["authentication_verified"])
        assertEquals(true, event["requires_observation"])
        assertEquals(original.receipt, resumed.result.receipt)
        assertEquals(original.output, resumed.result.output)
        assertEquals(resumed, resolver(record.copy(state = "returned", runWakeAcknowledged = true))
            .resolve(request, call, original))
    }

    @Test fun `host restart resolves the saved wait without inventing login or control ownership`() {
        val interrupted = record.copy(hostProcessId = "previous-host").afterHostRestart("current-host")
        val original = result()
        val resolution = resolver(interrupted).resolve(request, call, original) as AgentModelToolEventWait.Resolved
        val event = resolution.result.metadata["external_event"] as Map<*, *>
        assertEquals("browser_control_interrupted", event["kind"])
        assertEquals("browser_host_restarted", event["code"])
        assertEquals("unknown", event["control_owner"])
        assertEquals(false, event["authentication_verified"])
        assertEquals(false, event["goal_terminal"])
        assertEquals(true, event["requires_observation"])
        assertEquals(original.output, resolution.result.output)
        assertEquals(original.receipt, resolution.result.receipt)
        assertEquals(resolution, resolver(interrupted.copy(runWakeAcknowledged = true)).resolve(request, call, original))
    }

    @Test fun `an interrupted foreign generation cannot be consumed as this task's observation`() {
        val foreign = record.copy(hostProcessId = "previous-host", generation = "foreign")
            .afterHostRestart("current-host")
        val resolution = resolver(foreign).resolve(request, call, result()) as AgentModelToolEventWait.Resolved
        val event = resolution.result.metadata["external_event"] as Map<*, *>
        assertEquals("browser_wait_binding_changed", event["code"])
        assertFalse(event.containsKey("event_id"))
    }

    @Test fun `host marker requires the exact committed observation and owner`() {
        val returned = record.copy(state = "returned")
        val marked = mutableListOf<AgentBrowserUserRequest>()
        val resolver = AgentBrowserModelEventWaitResolver({ returned }, { true }, commitObservation = marked::add)
        val native = result()
        resolver.observationCommitted(request, call, native)
        assertTrue(marked.isEmpty())
        val resolved = resolver.resolve(request, call, native) as AgentModelToolEventWait.Resolved
        resolver.observationCommitted(request.copy(conversationId = "foreign"), call, resolved.result)
        assertTrue(marked.isEmpty())
        resolver.observationCommitted(request, call, resolved.result)
        assertEquals(listOf(returned), marked)
    }

    @Test fun `changed generation or live ownership cannot mark a prior resolved event`() {
        var current = record.copy(state = "returned")
        var marks = 0
        val resolver = AgentBrowserModelEventWaitResolver({ current }, { true }, commitObservation = { marks++ })
        val resolved = resolver.resolve(request, call, result()) as AgentModelToolEventWait.Resolved
        current = current.copy(generation = "new-generation")
        resolver.observationCommitted(request, call, resolved.result)
        current = record
        resolver.observationCommitted(request, call, resolved.result)
        assertEquals(0, marks)
    }
}
