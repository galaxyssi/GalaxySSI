package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentCollaboratorBrowserIsolationTest {
    private val context = AgentNativeToolInvocationContext(sessionId = "parent-session", conversationId = "group",
        turnId = "turn", callerId = "public-framework-test", invocationId = "invocation",
        attributes = mapOf("workspace_id" to "files", "task_id" to "task"))

    private fun record(owner: AgentNativeToolInvocationContext = context): AgentBrowserUserRequest {
        val scope = AgentInteractiveBrowserTools.scope(owner)
        return AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "browser"), "generation", scope,
            owner.sessionId, owner.conversationId, owner.turnId, owner.callerId,
            owner.attributes.getValue("workspace_id"), "browser", "page", "handoff", "active",
            taskId = "task", modelLoopId = "loop", collaborationSourceMessageId = owner.collaborationSourceMessageId)
    }

    @Test fun ordinaryScopeIsByteForByteCompatibleWithThePreviousOwnerHash() {
        assertEquals(AgentNativeJsonCodec.sha256(mapOf("session" to context.sessionId,
            "conversation" to context.conversationId, "workspace" to "files", "caller" to context.callerId)),
            AgentInteractiveBrowserTools.scope(context))
    }

    @Test fun twoMembersInTheSameParentCannotShareABrowserOrOperationReceipt() {
        val first = context.copy(collaborationSourceMessageId = 101)
        val second = context.copy(collaborationSourceMessageId = 102)
        assertNotEquals(AgentInteractiveBrowserTools.scope(first), AgentInteractiveBrowserTools.scope(second))
        assertNotEquals(AgentInteractiveBrowserTools.operationId(first), AgentInteractiveBrowserTools.operationId(second))
        assertNotEquals(record(first).key, record(second).key)
        assertNotEquals(record(first).scope, record().scope)
    }

    @Test fun sourceIdentityUsesAllSixtyFourBitsWithoutNullOrZeroAliasing() {
        val sources = listOf(null, 0L, 1L, -1L, Long.MIN_VALUE, Long.MAX_VALUE, 1L shl 32)
        assertEquals(sources.size, sources.map { AgentInteractiveBrowserTools.scope(
            context.copy(collaborationSourceMessageId = it)) }.toSet().size)
        sources.forEach { source ->
            val original = record(context.copy(collaborationSourceMessageId = source))
            assertEquals(original, AgentBrowserUserRequest.fromJson(original.toJson()))
        }
    }

    @Test fun aMemberKeepsItsScopeAcrossObservationsAndTurnsButNotItsMutationId() {
        val first = context.copy(collaborationSourceMessageId = 101)
        val later = first.copy(turnId = "later-turn", invocationId = "later-invocation")
        assertEquals(AgentInteractiveBrowserTools.scope(first), AgentInteractiveBrowserTools.scope(later))
        assertNotEquals(AgentInteractiveBrowserTools.operationId(first), AgentInteractiveBrowserTools.operationId(later))
        assertFalse(record(first).sameOwner(later))
    }

    @Test fun sourceAndScopeMustBothMatchEvenIfOtherHostBindingsAreIdentical() {
        val first = context.copy(collaborationSourceMessageId = 101)
        val bound = record(first)
        assertTrue(bound.sameOwner(first.copy(invocationId = "observer")))
        assertFalse(bound.sameOwner(context))
        assertFalse(bound.sameOwner(first.copy(collaborationSourceMessageId = 102)))
        assertFalse(bound.copy(collaborationSourceMessageId = null).sameOwner(first))
        assertFalse(bound.copy(scope = record().scope).sameOwner(first))
        assertFalse(record().sameOwner(first))
    }

    @Test fun sameGenerationCannotMoveBetweenMembersOrBecomeAnOrdinaryHandoff() {
        val bound = record(context.copy(collaborationSourceMessageId = 101))
        assertTrue(bound.permitsSameGeneration(bound.copy(state = "returned")))
        assertFalse(bound.permitsSameGeneration(bound.copy(collaborationSourceMessageId = 102)))
        assertFalse(bound.permitsSameGeneration(bound.copy(collaborationSourceMessageId = null)))
        assertFalse(record().permitsSameGeneration(record().copy(collaborationSourceMessageId = 101)))
    }

    @Test fun legacyRecordsRemainOrdinaryAndNeverInheritAMemberFromNewContext() {
        val legacy = record().toJson().apply { remove("collaboration_source") }
        val restored = AgentBrowserUserRequest.fromJson(legacy)
        assertNull(restored.collaborationSourceMessageId)
        assertTrue(restored.sameOwner(context))
        assertFalse(restored.sameOwner(context.copy(collaborationSourceMessageId = 101)))
        assertNull(AgentBrowserUserRequest.fromJson(legacy.put("collaboration_source", JSONObject.NULL))
            .collaborationSourceMessageId)
    }

    @Test fun memberBrowserScopeCannotBeSelectedByModelToolArguments() {
        val definition = AgentInteractiveBrowserTools.definitions(execute = { error("Invalid input must not dispatch") })
        val registry = AgentNativeToolRegistry().registerAll(definition)
        val result = registry.invoke(AgentInteractiveBrowserTools.OBSERVE,
            mapOf("operation" to "pages", "collaboration_source" to 102), context.copy(collaborationSourceMessageId = 101))
        assertFalse(result.isSuccess)
        var captured: AgentRuntimeExecutionRequest? = null
        val runtime = AgentNativeToolRegistry().registerAll(AgentInteractiveBrowserTools.definitions(execute = {
            captured = it
            AgentRuntimeExecutionResponse(0, """{"ok":true,"result":{"pages":[]}}""", "", 1)
        }))
        assertTrue(runtime.invoke(AgentInteractiveBrowserTools.OBSERVE, mapOf("operation" to "pages"),
            context.copy(collaborationSourceMessageId = 101)).isSuccess)
        assertTrue(captured!!.source.contains(AgentInteractiveBrowserTools.scope(context.copy(collaborationSourceMessageId = 101))))
        assertFalse(captured!!.source.contains(AgentInteractiveBrowserTools.scope(context.copy(collaborationSourceMessageId = 102))))
    }

    private val call = AgentModelToolCall("call", AgentInteractiveBrowserTools.ACT,
        mapOf("operation" to "request_user_control", "session_id" to "browser", "page_id" to "page"))
    private fun result(bound: AgentBrowserUserRequest) = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
        AgentNativeToolDescriptor(call.toolId, "1.0.0", "Public test", "Public test", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW),
        AgentNativeToolExecutor { AgentNativeToolExecutionResult.success(mapOf("durable_resume_available" to true,
            "host_wait_key" to bound.key, "host_wait_generation" to bound.generation)) }))
        .invoke(call.toolId, call.arguments, context)

    private fun request(source: Long?) = AgentModelToolLoopRequest(context.sessionId, context.conversationId,
        context.turnId, "task", "files", listOf(AgentModelMessage.user("Public browser framework test")),
        callerId = context.callerId, loopId = "loop", collaborationSourceMessageId = source)

    @Test fun eventResolverUsesTheOriginalMemberWhenReconstructingTheToolContext() {
        val bound = record(context.copy(collaborationSourceMessageId = 101))
        val resolver = AgentBrowserModelEventWaitResolver({ bound }, { true })
        assertTrue(resolver.resolve(request(101), call, result(bound)) is AgentModelToolEventWait.Pending)
        listOf(null, 102L).forEach { source ->
            val mismatch = resolver.resolve(request(source), call, result(bound)) as AgentModelToolEventWait.Resolved
            val event = mismatch.result.metadata["external_event"] as Map<*, *>
            assertEquals("browser_wait_binding_changed", event["code"])
            assertFalse(event.containsKey("event_id"))
        }
    }

    @Test fun anotherMembersReturnCannotCommitOrAcknowledgeThisMembersObservation() {
        val returned = record(context.copy(collaborationSourceMessageId = 101)).copy(state = "returned")
        var commits = 0
        val resolver = AgentBrowserModelEventWaitResolver({ returned }, { true }, commitObservation = { commits++ })
        val native = result(returned)
        val resolved = resolver.resolve(request(101), call, native) as AgentModelToolEventWait.Resolved
        val event = resolved.result.metadata["external_event"] as Map<*, *>
        assertEquals("browser_control_returned", event["kind"])
        assertEquals(false, event["authentication_verified"])
        resolver.observationCommitted(request(102), call, resolved.result)
        resolver.observationCommitted(request(null), call, resolved.result)
        assertEquals(0, commits)
        resolver.observationCommitted(request(101), call, resolved.result)
        assertEquals(1, commits)
    }
}
