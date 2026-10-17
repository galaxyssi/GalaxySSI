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

    @Test fun arbitraryExit127DoesNotClaimMissingPackagesOrSafeReplay() {
        val registry = registry { AgentRuntimeExecutionResponse(127, "", "", 1) }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "create"), context)
        assertEquals("browser_result_unobserved", result.error?.code)
        assertEquals(true, result.error?.details?.get("outcome_unknown"))
        assertEquals(false, result.error?.details?.get("goal_terminal"))
        assertNull(result.error?.details?.get("required_packs"))
    }

    @Test fun provenPreflightFailureIsDistinctFromAnUnobservedMutation() {
        for (code in listOf("node_missing", "node_path_missing", "node_start_failed", "browser_launcher_missing", "browser_launcher_path_missing")) {
            val registry = registry { response("""{"ok":false,"error":{"code":"$code","message":"Inspect runtime.","details":{"executed":false}}}""") }
            val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), context.copy(idempotencyKey = code))
            assertEquals(code, result.error?.code)
            assertEquals(false, result.error?.details?.get("outcome_unknown"))
            assertEquals(false, result.error?.details?.get("executed"))
        }
    }

    @Test fun readinessUsesAnIsolatedProbeInsteadOfNavigatingTheUserSession() {
        var request: AgentRuntimeExecutionRequest? = null
        val result = registry { request = it; response("""{"ok":true,"result":{"browser_ready":true,"website_verified":false}}""") }
            .invoke(AgentInteractiveBrowserTools.OBSERVE, mapOf("operation" to "readiness"), context)
        assertTrue(result.isSuccess)
        assertTrue(request!!.source.contains("browser-runtime-readiness.cjs"))
        assertFalse(request!!.source.contains("exec galaxyssi-browser .galaxyssi-inputs/browser/browser-session-cli.cjs"))
    }

    @Test fun lostBrowserResultDoesNotClaimAnActionFailedOrAutomaticallyRepeatIt() {
        var executions = 0
        val registry = registry { executions++; AgentRuntimeExecutionResponse(1, "not-json", "private-error", 1) }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), context)
        assertEquals(1, executions)
        assertEquals("browser_result_unobserved", result.error?.code)
        assertEquals(true, result.error?.details?.get("outcome_unknown"))
        assertEquals(AgentInteractiveBrowserTools.operationId(context), result.error?.details?.get("request_id"))
        assertEquals("operation_status", result.error?.details?.get("reconciliation_operation"))
        assertFalse(result.toJson().contains("private-error"))
    }

    @Test fun staleControlErrorsAreObservationsForModelReplanning() {
        val registry = registry { response("""{"ok":false,"error":{"code":"page_observation_stale","message":"Observe again.","details":{"executed":false}}}""") }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), context)
        assertEquals("page_observation_stale", result.error?.code)
        assertEquals(false, result.error?.details?.get("executed"))
        assertEquals(false, result.error?.details?.get("goal_terminal"))
        assertEquals(false, result.error?.details?.get("outcome_unknown"))
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

    @Test fun operationIdentityIsStableForOneInvocationButIsolatedAcrossCallsAndScopes() {
        val id = AgentInteractiveBrowserTools.operationId(context)
        assertEquals(id, AgentInteractiveBrowserTools.operationId(context.copy()))
        assertNotEquals(id, AgentInteractiveBrowserTools.operationId(context.copy(invocationId = "later")))
        assertNotEquals(id, AgentInteractiveBrowserTools.operationId(context.copy(turnId = "later-turn")))
        assertNotEquals(id, AgentInteractiveBrowserTools.operationId(context.copy(conversationId = "other")))
        assertNotEquals(id, AgentInteractiveBrowserTools.operationId(context.copy(callerId = "other")))
    }

    @Test fun operationStatusIsReadOnlyAndUsesTheOriginalRequestIdWithoutResubmitting() {
        val requests = mutableListOf<AgentRuntimeExecutionRequest>()
        val registry = registry { requests += it; response("""{"ok":true,"result":{"request_id":"original-request","state":"completed","business_success_verified":false,"verification_required":true}}""") }
        val result = registry.invoke(AgentInteractiveBrowserTools.OBSERVE,
            mapOf("operation" to "operation_status", "request_id" to "original-request"), context)
        assertTrue(result.isSuccess)
        assertEquals("original-request", result.output["request_id"])
        assertEquals(false, result.output["business_success_verified"])
        assertEquals(1, requests.size)
        assertTrue(decodeEnvironment(requests.single().secretEnvironment).contains("original-request"))
        assertEquals(AgentInteractiveBrowserTools.operationId(context),
            requests.single().secretEnvironment["GALAXYSSI_BROWSER_OPERATION_ID"])
        assertFalse(registry.invoke(AgentInteractiveBrowserTools.ACT,
            mapOf("operation" to "operation_status", "request_id" to "original-request"), context).isSuccess)
    }

    @Test fun operationIdentityAndHostCapabilityRespectTheSecureEnvironmentKeyBudget() {
        val environment = AgentInteractiveBrowserTools.secretEnvironment(
            mapOf("operation" to "fill", "value" to "\u4f60\u597d".repeat(5000)), "a".repeat(64), "b".repeat(64))
        assertTrue(environment.size <= 32)
        assertEquals("b".repeat(64), environment["GALAXYSSI_BROWSER_OPERATION_ID"])
        assertTrue(environment.values.all { it.toByteArray(Charsets.UTF_8).size <= 4096 })
    }

    @Test fun thrownRuntimeFailureKeepsTheOperationIdentityWithoutLeakingExceptionText() {
        val registry = registry { throw IllegalStateException("private-password-runtime-error") }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), context)
        assertEquals("browser_result_unobserved", result.error?.code)
        assertEquals(true, result.error?.details?.get("outcome_unknown"))
        assertEquals(AgentInteractiveBrowserTools.operationId(context), result.error?.details?.get("request_id"))
        assertFalse(result.toJson().contains("private-password"))
    }

    @Test fun explicitNativeCancellationRemainsCancellationRatherThanAModelRecoveryObservation() {
        val registry = registry { throw AgentNativeToolCancelledException() }
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), context)
        assertEquals(AgentNativeToolResultStatus.CANCELLED, result.status)
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
