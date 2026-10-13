package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentInteractiveBrowserToolsTest {
    private val context = AgentNativeToolInvocationContext(sessionId = "agent", conversationId = "conversation-a",
        turnId = "turn-1", idempotencyKey = "browser-1", attributes = mapOf("workspace_id" to "workspace-a"))

    @Test fun browserScopeSurvivesTurnsButSeparatesConversationsWorkspacesAndCallers() {
        val original = AgentInteractiveBrowserTools.scope(context)
        assertEquals(original, AgentInteractiveBrowserTools.scope(context.copy(turnId = "turn-2", invocationId = "later")))
        assertNotEquals(original, AgentInteractiveBrowserTools.scope(context.copy(conversationId = "conversation-b")))
        assertNotEquals(original, AgentInteractiveBrowserTools.scope(context.copy(sessionId = "other-agent")))
        assertNotEquals(original, AgentInteractiveBrowserTools.scope(context.copy(attributes = mapOf("workspace_id" to "other"))))
        assertNotEquals(original, AgentInteractiveBrowserTools.scope(context.copy(callerId = "other-caller")))
        assertThrows(IllegalArgumentException::class.java) { AgentInteractiveBrowserTools.scope(context.copy(conversationId = "")) }
    }

    @Test fun passwordValuesUseEphemeralEnvironmentNotScriptArgumentsOrProgress() {
        var captured: AgentRuntimeExecutionRequest? = null
        val registry = registry { captured = it; response("""{"ok":true,"result":{"action_dispatched":true,"business_success_verified":false}}""") }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT,
            mapOf("operation" to "fill", "session_id" to "s", "page_id" to "p", "node_id" to "n", "revision" to "r", "value" to "private-password"), context)
        assertTrue(result.isSuccess)
        assertEquals(false, result.output["business_success_verified"])
        val request = captured!!
        assertFalse(request.source.contains("private-password"))
        assertFalse(request.arguments.any { it.contains("private-password") })
        assertTrue(decodeEnvironment(request.secretEnvironment).contains("private-password"))
        assertFalse(request.workspaceMutationExpected)
        assertFalse(request.discoverBuildArtifacts)
        assertEquals("workspace-a", request.workspaceId)
    }

    @Test fun missingBrowserRuntimeReturnsInstallationEvidenceWithoutPretendingTheGoalFailed() {
        val registry = registry { AgentRuntimeExecutionResponse(127, "", "", 1) }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "create"), context)
        assertEquals("browser_runtime_missing", result.error?.code)
        assertEquals(false, result.error?.details?.get("executed"))
        assertEquals(false, result.error?.details?.get("goal_terminal"))
        assertEquals(listOf("browser-automation", "node-js"), result.error?.details?.get("required_packs"))
    }

    @Test fun lostBrowserResultDoesNotClaimAnActionFailedOrAutomaticallyRepeatIt() {
        var executions = 0
        val registry = registry { executions++; AgentRuntimeExecutionResponse(1, "not-json", "private-error", 1) }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), context)
        assertEquals(1, executions)
        assertEquals("browser_result_unobserved", result.error?.code)
        assertEquals(true, result.error?.details?.get("outcome_unknown"))
        assertFalse(result.toJson().contains("private-error"))
    }

    @Test fun staleControlErrorsAreObservationsForModelReplanning() {
        val registry = registry { response("""{"ok":false,"error":{"code":"page_observation_stale","message":"Observe again.","details":{"executed":false}}}""") }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), context)
        assertEquals("page_observation_stale", result.error?.code)
        assertEquals(false, result.error?.details?.get("executed"))
        assertEquals(false, result.error?.details?.get("goal_terminal"))
    }

    @Test fun readOnlyBrowserToolCannotDispatchMutations() {
        val registry = registry { error("Invalid input must not execute") }
        assertFalse(registry.invoke(AgentInteractiveBrowserTools.OBSERVE, mapOf("operation" to "click"), context).isSuccess)
        val descriptor = registry.lookup(AgentInteractiveBrowserTools.OBSERVE)!!.descriptor
        assertFalse(descriptor.requiresEffectClaim)
        assertTrue(registry.lookup(AgentInteractiveBrowserTools.ACT)!!.descriptor.requiresEffectClaim)
    }

    @Test fun browserToolsAreDisclosedForBothPhoneExecutionModes() {
        for (id in AgentInteractiveBrowserTools.toolIds) {
            assertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(id))
            assertTrue(AgentPhoneDevelopmentPolicy.isPhoneDevelopmentTool(id))
            assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(id))
        }
        assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(AgentOnDeviceRuntimeTools.INSTALL_PACK))
    }

    @Test fun userControlHostMethodsAndCapabilitiesAreNotModelInputs() {
        var executed = false
        val registry = registry { executed = true; error("Host-only control must not execute") }
        for (operation in listOf("human_control_begin", "human_control_finish", "executeHuman")) {
            val result = registry.invoke(AgentInteractiveBrowserTools.ACT,
                mapOf("operation" to operation, "session_id" to "s", "page_id" to "p"), context)
            assertFalse(result.isSuccess)
        }
        assertFalse(registry.invoke(AgentInteractiveBrowserTools.ACT,
            mapOf("operation" to "click", "control_token" to "private-host-token"), context).isSuccess)
        assertFalse(executed)
    }

    @Test fun waitingForUserControlUsesOneReadOnlyObservationAndNeverClaimsLoginSuccess() {
        var executions = 0
        var captured: AgentRuntimeExecutionRequest? = null
        val registry = registry { request ->
            executions++
            captured = request
            response("""{"ok":true,"result":{"session_id":"s","handoff_id":"h","control_owner":"agent","next_action":"observe","authentication_verified":false,"business_success_verified":false}}""")
        }
        val result = registry.invoke(AgentInteractiveBrowserTools.OBSERVE,
            mapOf("operation" to "wait_for_user", "session_id" to "s", "handoff_id" to "h"), context)
        assertTrue(result.isSuccess)
        assertEquals(1, executions)
        assertEquals(false, result.output["authentication_verified"])
        assertEquals(false, result.output["business_success_verified"])
        assertEquals("observe", result.output["next_action"])
        assertTrue(decodeEnvironment(captured!!.secretEnvironment).contains("wait_for_user"))
        assertFalse(captured!!.source.contains("host"))
        assertFalse(registry.lookup(AgentInteractiveBrowserTools.OBSERVE)!!.descriptor.requiresEffectClaim)
    }

    @Test fun largeUnicodeInputsFitTheExistingSecureEnvironmentValueLimits() {
        val value = "\u4f60\u597d".repeat(5000)
        val environment = AgentInteractiveBrowserTools.secretEnvironment(mapOf("operation" to "fill", "value" to value))
        assertTrue(environment.size <= 32)
        assertTrue(environment.values.all { it.toByteArray(Charsets.UTF_8).size <= 4096 })
        assertTrue(decodeEnvironment(environment).contains(value))
    }

    private fun decodeEnvironment(environment: Map<String, String>): String {
        val count = environment.getValue("GALAXYSSI_BROWSER_REQUEST_COUNT").toInt()
        return String(java.util.Base64.getDecoder().decode((0 until count).joinToString("") {
            environment.getValue("GALAXYSSI_BROWSER_REQUEST_$it")
        }), Charsets.UTF_8)
    }

    private fun registry(execute: (AgentRuntimeExecutionRequest) -> AgentRuntimeExecutionResponse) =
        AgentNativeToolRegistry().registerAll(AgentInteractiveBrowserTools.definitions(execute))
    private fun response(json: String) = AgentRuntimeExecutionResponse(0, json, "", 1)
}
