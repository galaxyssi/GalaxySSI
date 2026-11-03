package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentNativeActionObservationTest {
    private val action = AgentAction("observe", AgentActionKind.CALL_NATIVE_TOOL, "Public fixture", AgentRisk.LOW,
        AgentActionStatus.RUNNING, "Inspect runtime", mapOf("tool_id" to "public.inspect"))
    private fun result(error: AgentNativeToolError? = AgentNativeToolError("dependency_missing", "Browser driver is absent",
        true, mapOf("component" to "browser", "installed" to false))) = AgentNativeToolResult(
        AgentNativeToolResultStatus.FAILED, mapOf("state" to "missing"), "Execution failed", emptyMap(), error, null,
        AgentNativeToolReceipt("public-invocation", null, 10, 20, 10, AgentNativeToolResultStatus.FAILED, "input", "output"),
        AgentNativeToolProvenance("public.inspect", "1", AgentNativeToolLocation.PHONE, "public-fixture", "1"))
    private fun observation(result: AgentNativeToolResult = result()) = JSONObject(requireNotNull(AgentNativeActionObservation.from(result)))

    @Test fun `generic message does not hide actionable error details`() {
        val evidence = observation()
        assertEquals("Execution failed", evidence.getString("message"))
        assertEquals("dependency_missing", evidence.getJSONObject("error").getString("code"))
        assertTrue(evidence.getJSONObject("error").getBoolean("retryable"))
        assertFalse(evidence.getJSONObject("error").getJSONObject("details").getBoolean("installed"))
        assertEquals("public-invocation", evidence.getString("invocation_id"))
        assertEquals("missing", evidence.getJSONObject("output").getString("state"))
    }

    @Test fun `success retains existing output shape and no failure envelope`() {
        val native = result(null).copy(status = AgentNativeToolResultStatus.SUCCEEDED)
        assertNull(AgentNativeActionObservation.from(native))
        val success = AgentActionResult(action.id, true, "Ready", mapOf("native_tool_output" to "{\"ready\":true}"))
        assertEquals("{\"ready\":true}", AgentNativeActionObservation.evidence(success, 12_000))
    }

    @Test fun `every terminal failure status remains distinct`() {
        AgentNativeToolResultStatus.entries.filterNot { it == AgentNativeToolResultStatus.SUCCEEDED }.forEach { status ->
            assertEquals(status.wireValue, observation(result().copy(status = status)).getString("status"))
        }
    }

    @Test fun `verification failure without execution error remains inspectable`() {
        val evidence = observation(result(null).copy(status = AgentNativeToolResultStatus.VERIFICATION_FAILED,
            verification = AgentNativeToolVerification(AgentNativeVerificationStatus.FAILED,
                "Expected navigation was not observed", mapOf("url" to "https://example.org/login"))))
        assertTrue(evidence.isNull("error"))
        assertEquals("failed", evidence.getJSONObject("verification").getString("status"))
        assertEquals("https://example.org/login", evidence.getJSONObject("verification").getJSONObject("evidence").getString("url"))
    }

    @Test fun `secrets are removed before persistence and truncation`() {
        val secret = "private-fixture-credential"
        val native = result(AgentNativeToolError("authentication_required", "password=$secret", false,
            mapOf("password" to secret, "nested" to mapOf("access_token" to secret), "log" to "Bearer $secret")))
            .copy(output = mapOf("authorization" to secret))
        val evidence = requireNotNull(AgentNativeActionObservation.from(native))
        assertFalse(evidence.contains(secret))
        assertTrue(evidence.contains("[redacted]"))
        assertEquals("authentication_required", JSONObject(evidence).getJSONObject("error").getString("code"))
    }

    @Test fun `large diagnostics keep valid bounded json and explicit truncation`() {
        val log = "BEGIN " + "\"\\\n".repeat(30_000) + " FAILURE_TAIL"
        val native = result(AgentNativeToolError("operation_outcome_unknown", log, false, mapOf("stderr" to log)))
            .copy(message = log, output = mapOf("stdout" to log), verification = AgentNativeToolVerification(
                AgentNativeVerificationStatus.FAILED, log, mapOf("diagnostic" to log)))
        val text = requireNotNull(AgentNativeActionObservation.from(native))
        assertTrue("Observation length: ${text.length}", text.length < 12_000)
        val evidence = JSONObject(text)
        assertEquals("operation_outcome_unknown", evidence.getJSONObject("error").getString("code"))
        assertTrue(evidence.getJSONObject("error").getJSONObject("details").getBoolean("truncated"))
        assertTrue(evidence.getJSONObject("output").getString("excerpt").contains("FAILURE_TAIL"))
        assertTrue(evidence.getJSONObject("error").getJSONObject("details").getString("sha256").matches(Regex("[a-f0-9]{64}")))
    }

    @Test fun `action history and supervising provider receive the error not only empty output`() {
        val observation = requireNotNull(AgentNativeActionObservation.from(result()))
        val receipt = AgentActionResult(action.id, false, "Execution failed", mapOf(
            "native_tool_output" to "{}", AgentNativeActionObservation.KEY to observation))
        val screen = ScreenContext("Public fixture", pageTitle = "Public failure observation")
        val plan = AgentPlan("Public goal", screen, emptyList(), listOf(action))
            .markAction(action.id, AgentActionStatus.FAILED, receipt)
        val failed = plan.actions.first()
        assertEquals(AgentActionStatus.FAILED, failed.status)
        assertEquals(observation, failed.evidence)
        assertTrue(requireNotNull(AgentPlannerObservation.from(failed, 4_000)).contains("dependency_missing"))
        val prompt = AgentSupervisedProjectLoop.recoveryPrompt(AgentRequest(plan.goal, screen, targets = emptyList(),
            memories = emptyList(), runtimeContext = AgentRuntimeContextBuilder.build("public-session", plan.goal, screen,
                PermissionMode.FULL_ACCESS, false, false, emptyList(), emptyList()),
            executionHistory = listOf(failed)), failed, "Execution failed")
        assertTrue(prompt.contains("dependency_missing"))
        assertTrue(prompt.contains("Browser driver is absent"))
    }

    @Test fun `predispatch errors state that no tool started and do not invent receipts`() {
        val failure = AgentNativeActionObservation.beforeDispatch(action, "tool_not_registered", "Native tool is not registered")
        assertFalse(failure.success)
        assertFalse(failure.metadata.containsKey("invocation_id"))
        val evidence = JSONObject(failure.metadata.getValue(AgentNativeActionObservation.KEY))
        assertFalse(evidence.getBoolean("execution_started"))
        assertEquals("tool_not_registered", evidence.getJSONObject("error").getString("code"))
    }

    @Test fun `explicit unknown outcomes survive compaction without inference from error names`() {
        val unknown = result(AgentNativeToolError("operation_failed", "Observe external state", false,
            mapOf("outcome_unknown" to true, "log" to "x".repeat(40_000))))
        assertEquals("unknown", observation(unknown).getString("outcome_state"))
        assertFalse(observation(result(AgentNativeToolError("operation_outcome_unknown", "Name alone is not evidence")))
            .has("outcome_state"))
    }
}
