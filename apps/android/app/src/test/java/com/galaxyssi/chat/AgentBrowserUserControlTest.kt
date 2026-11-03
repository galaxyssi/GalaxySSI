package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentBrowserUserControlTest {
    private val context = AgentNativeToolInvocationContext(sessionId = "agent", conversationId = "conversation",
        turnId = "turn", callerId = "caller", attributes = mapOf("workspace_id" to "task-workspace",
            "task_id" to "task", "model_loop_id" to "loop"))
    private val scope = AgentInteractiveBrowserTools.scope(context)
    private val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "browser"), "generation", scope,
        "agent", "conversation", "turn", "caller", "task-workspace", "browser", "page", "handoff", "active",
        taskId = "task", modelLoopId = "loop")

    @Test fun hostWorkspaceCannotDeadlockBehindTheWaitingModelWorkspace() {
        val request = AgentBrowserUserControl.hostRequest(record, mapOf("operation" to "human_control_state"), "c".repeat(64))
        assertNotEquals(record.workspaceId, request.workspaceId)
        assertEquals(AgentWorkspaceScope.id("browser-control:$scope"), request.workspaceId)
        assertFalse(request.workspaceMutationExpected)
        assertFalse(request.discoverBuildArtifacts)
        assertTrue(request.artifactPaths.isEmpty())
    }

    @Test fun hostAuthorityAndTypedSecretsNeverEnterScriptsOrCommandArguments() {
        val capability = "a".repeat(64)
        val request = AgentBrowserUserControl.hostRequest(record, mapOf("operation" to "human_control_execute",
            "action" to mapOf("operation" to "insert_text", "value" to "secret-user-input")), capability)
        assertFalse(request.source.contains(capability))
        assertFalse(request.source.contains("secret-user-input"))
        assertTrue(request.arguments.isEmpty())
        assertEquals(capability, request.secretEnvironment["GALAXYSSI_BROWSER_HOST_TOKEN"])
        assertTrue(request.source.contains(".cjs host "))
        assertTrue(request.secretEnvironment.size <= 32)
    }

    @Test fun hostEnvelopeAlwaysUsesTheOriginalBrowserRatherThanAnInputOverride() {
        val request = AgentBrowserUserControl.hostRequest(record,
            mapOf("operation" to "human_control_state", "session_id" to "other-account"), "b".repeat(64))
        val environment = request.secretEnvironment
        val count = environment.getValue("GALAXYSSI_BROWSER_REQUEST_COUNT").toInt()
        val input = String(java.util.Base64.getDecoder().decode((0 until count).joinToString("") {
            environment.getValue("GALAXYSSI_BROWSER_REQUEST_$it")
        }))
        assertTrue(input.contains("browser"))
        assertFalse(input.contains("other-account"))
    }

    @Test fun userRequestsAreBoundToOriginalSessionConversationTurnCallerAndWorkspace() {
        assertTrue(record.sameOwner(context))
        assertTrue(record.sameOwner(context.copy(invocationId = "retry")))
        assertTrue(record.sameOwner(context.copy(attributes = context.attributes + ("model_loop_id" to "replanned-loop"))))
        for (other in listOf(context.copy(sessionId = "other"), context.copy(conversationId = "other"),
            context.copy(turnId = "other"), context.copy(callerId = "other"),
            context.copy(attributes = context.attributes + ("workspace_id" to "other")),
            context.copy(attributes = context.attributes + ("task_id" to "other")),
            context.copy(attributes = context.attributes - "task_id"))) {
            assertFalse(record.sameOwner(other))
        }
    }

    @Test fun anUnboundLegacyRecordCannotBeClaimedByAnUnrelatedBoundTask() {
        val legacy = record.toJson().apply { remove("task"); remove("model_loop") }
        val restored = AgentBrowserUserRequest.fromJson(legacy)
        assertEquals("", restored.taskId)
        assertEquals("", restored.modelLoopId)
        assertFalse(restored.sameOwner(context))
    }

    @Test fun sameGenerationUpdatesCannotChangeTaskIdentityOrReopenReturnedControl() {
        assertTrue(record.permitsSameGeneration(record.copy(state = "returned")))
        assertTrue(record.permitsSameGeneration(record))
        assertTrue(record.copy(handoffId = "", state = "requested").permitsSameGeneration(record))
        for (replacement in listOf(record.copy(taskId = "other"), record.copy(modelLoopId = "other"),
            record.copy(conversationId = "other"), record.copy(turnId = "other"), record.copy(sessionId = "other"),
            record.copy(callerId = "other"), record.copy(workspaceId = "other"), record.copy(pageId = "other"),
            record.copy(handoffId = "other"), record.copy(state = "requested"))) {
            assertFalse(record.permitsSameGeneration(replacement))
        }
        assertFalse(record.copy(state = "returned").permitsSameGeneration(record))
    }

    @Test fun recordRoundTripHasNoHostCapabilityOrCredentials() {
        assertEquals(record, AgentBrowserUserRequest.fromJson(record.toJson()))
        val serialized = record.toJson().toString()
        assertFalse(serialized.contains("token"))
        assertFalse(serialized.contains("password"))
        assertFalse(serialized.contains("cookie"))
        assertNotEquals(record.key, AgentBrowserUserRequest.key(scope, "other-browser"))
        assertNotEquals(record.key, AgentBrowserUserRequest.key("other-scope", "browser"))
    }

    @Test fun nativeRequestUsesHostAdapterNotAnUnauthorizedModelRpc() {
        var hostRequests = 0
        val registry = AgentNativeToolRegistry().registerAll(AgentInteractiveBrowserTools.definitions(
            execute = { error("A user request must not use the model RPC channel") },
            requestUserControl = {
                hostRequests++
                AgentNativeToolExecutionResult.success(mapOf("handoff_id" to "h", "authentication_verified" to false))
            }))
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT,
            mapOf("operation" to "request_user_control", "session_id" to "browser", "page_id" to "page"),
            context.copy(idempotencyKey = "user-request"))
        assertTrue(result.isSuccess)
        assertEquals(1, hostRequests)
        assertEquals(false, result.output["authentication_verified"])
    }

    @Test fun reservedHostEnvironmentSlotNeverOverflowsTheRuntimeChannel() {
        val environment = AgentInteractiveBrowserTools.secretEnvironment(mapOf("value" to "x".repeat(80_000)), "a".repeat(64))
        assertTrue(environment.size <= 32)
        assertTrue(environment.values.all { it.toByteArray().size <= 4096 })
        assertThrows(IllegalArgumentException::class.java) {
            AgentInteractiveBrowserTools.secretEnvironment(mapOf("value" to "x".repeat(100_000)), "a".repeat(64))
        }
    }

    @Test fun hostRestartIsAnUnconfirmedEventRatherThanReturnedControl() {
        val original = record.copy(hostProcessId = "previous-host", runWorkspaceId = "run")
        val interrupted = original.afterHostRestart("current-host")
        assertEquals("interrupted", interrupted.state)
        assertEquals("browser_host_restarted", interrupted.interruptionCode)
        assertEquals(original.generation, interrupted.generation)
        assertEquals(original.handoffId, interrupted.handoffId)
        assertEquals(original.hostProcessId, interrupted.hostProcessId)
        assertTrue(interrupted.pendingRunWake)
        assertTrue(original.permitsSameGeneration(interrupted))
        assertEquals(interrupted, interrupted.afterHostRestart("another-host"))
        assertEquals(interrupted, AgentBrowserUserRequest.fromJson(interrupted.toJson()))
    }

    @Test fun currentOrUnboundHostDoesNotInventAnInterruption() {
        assertEquals(record, record.afterHostRestart("current-host"))
        val current = record.copy(hostProcessId = "current-host")
        assertEquals(current, current.afterHostRestart("current-host"))
        val returned = record.copy(state = "returned", hostProcessId = "previous-host")
        assertEquals(returned, returned.afterHostRestart("current-host"))
        val requested = record.copy(state = "requested", hostProcessId = "previous-host")
        assertEquals("interrupted", requested.afterHostRestart("current-host").state)
        assertThrows(IllegalArgumentException::class.java) { current.afterHostRestart("") }
    }

    @Test fun interruptedGenerationCannotBeReopenedOrConvertedToSuccessfulReturn() {
        val interrupted = record.copy(hostProcessId = "previous-host", runWorkspaceId = "run")
            .afterHostRestart("current-host")
        assertFalse(interrupted.permitsSameGeneration(interrupted.copy(state = "active", interruptionCode = "")))
        assertFalse(interrupted.permitsSameGeneration(interrupted.copy(state = "returned", interruptionCode = "")))
        assertFalse(interrupted.permitsSameGeneration(interrupted.copy(hostProcessId = "current-host")))
        assertFalse(interrupted.permitsSameGeneration(interrupted.copy(interruptionCode = "invented")))
        val acknowledged = interrupted.copy(runWakeAcknowledged = true)
        assertTrue(interrupted.permitsSameGeneration(acknowledged))
        assertFalse(acknowledged.pendingRunWake)
        assertFalse(acknowledged.permitsSameGeneration(interrupted))
    }

    @Test fun runtimeIdentityCanBeBoundOnceButNotChangedByLaterUpdates() {
        val bound = record.copy(runtimeInstanceId = "original-runtime")
        assertTrue(record.permitsSameGeneration(bound))
        assertEquals(bound, AgentBrowserUserRequest.fromJson(bound.toJson()))
        assertFalse(bound.permitsSameGeneration(bound.copy(runtimeInstanceId = "replacement-runtime")))
        assertFalse(bound.permitsSameGeneration(bound.copy(runtimeInstanceId = "")))
        assertFalse(record.copy(state = "returned").permitsSameGeneration(bound.copy(state = "returned")))
        assertEquals("", AgentBrowserUserRequest.fromJson(record.toJson().apply { remove("runtime_instance") }).runtimeInstanceId)
    }
}
