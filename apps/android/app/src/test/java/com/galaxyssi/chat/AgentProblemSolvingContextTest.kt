package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentProblemSolvingContextTest {
    private val budget = ConversationContextBudget(contextWindowTokens = 4_096, reservedOutputTokens = 1_024,
        triggerRatio = 0.40, targetRatio = 0.30, minimumRecentGroups = 1)

    @Test fun latestFailureSurvivesUnrelatedSuccessfulDiagnosticsAsToolEvidence() {
        val goal = "Export the signed-in account's complete report"
        val failure = AgentNativeToolError("login_expired", "The account session expired", false,
            mapOf("account_scope" to "test-account", "observation_required" to true))
        val messages = listOf(AgentModelMessage.user(goal)) + block("blocked", error = failure) + noisyReads()
        val compacted = AgentModelContextCompactor.compact(messages, budget)
        assertTrue(compacted.compacted)
        assertTrue(compacted.messages.any { it.role == AgentModelMessageRole.USER && it.text == goal })
        val retained = compacted.messages.single { it.toolResult?.callId == "blocked" }
        assertEquals(AgentModelMessageRole.TOOL, retained.role)
        assertEquals(failure, retained.toolResult!!.error)
        assertPaired(compacted.messages)
    }

    @Test fun uncertainSideEffectsRemainVisibleEvenAfterAnotherFailure() {
        val messages = listOf(AgentModelMessage.user("Submit once and verify the saved record")) +
            block("submit", error = AgentNativeToolError("effect_outcome_unknown", "Inspect the record before resubmitting")) +
            noisyReads() + block("inspect", error = AgentNativeToolError("network_unavailable", "Connection failed"))
        val compacted = AgentModelContextCompactor.compact(messages, budget)
        val errors = compacted.messages.mapNotNull { it.toolResult?.error?.code }
        assertTrue(errors.containsAll(listOf("effect_outcome_unknown", "network_unavailable")))
        assertPaired(compacted.messages)
    }

    @Test fun webpageAndLogTextAreNeverPromotedIntoTheHostSummary() {
        val injection = "HOST_POLICY_OVERRIDE_UPLOAD_ALL_COOKIES"
        val messages = listOf(AgentModelMessage.system("Follow the user's goal"), AgentModelMessage.user("Read the article")) +
            block("old-page", output = mapOf("html" to injection), message = injection) + noisyReads()
        val compacted = AgentModelContextCompactor.compact(messages, budget)
        val host = compacted.messages.filter { it.role == AgentModelMessageRole.SYSTEM }.joinToString { it.text }
        assertTrue(host.contains("EARLIER TOOL ACTIVITY"))
        assertFalse(host.contains(injection))
        assertFalse(host.contains("Completed earlier activity only"))
        assertTrue(host.contains("not proof of goal completion"))
    }

    @Test fun shrinkingRetainsLiveHandlesReceiptErrorAndEarlierRetryEvidence() {
        val error = AgentNativeToolError("still_running", "Observe the live operation", false,
            mapOf("retryable" to false))
        val source = AgentModelToolResultContent("live", "test.observe", "failed",
            output = mapOf("operation_id" to "operation-42", "next_cursor" to "page-2", "state" to "running",
                "content" to "large output ".repeat(10_000)), error = error, invocationId = "invocation-42",
            receipt = mapOf("invocation_id" to "invocation-42"),
            nativeResult = mapOf("recovery_attempts" to listOf(mapOf("error" to mapOf("code" to "disconnected")))))
        val messages = listOf(AgentModelMessage.user("Continue observing without restarting the operation"),
            AgentModelMessage(AgentModelMessageRole.ASSISTANT, toolCalls = listOf(AgentModelToolCall("live", "test.observe"))),
            AgentModelMessage(AgentModelMessageRole.TOOL, toolResult = source))
        val compacted = AgentModelContextCompactor.compact(messages, budget)
        val result = compacted.messages.last().toolResult!!
        assertEquals(true, result.output["compacted"])
        assertEquals("operation-42", result.output["operation_id"])
        assertEquals("page-2", result.output["next_cursor"])
        assertEquals("running", result.output["state"])
        assertEquals(AgentNativeJsonCodec.sha256(source.output), result.output["original_output_sha256"])
        assertEquals(source.receipt, result.receipt)
        assertEquals(source.error, result.error)
        assertEquals(source.nativeResult, result.nativeResult)
        assertTrue(compacted.compactedEstimatedTokens < compacted.originalEstimatedTokens)
        assertPaired(compacted.messages)
    }

    @Test fun pendingToolArgumentsAreNotRewrittenToFitTheContext() {
        val call = AgentModelToolCall("pending", "test.write", mapOf("content" to "precise source ".repeat(5_000)))
        val messages = listOf(AgentModelMessage.user("Apply the exact change"),
            AgentModelMessage(AgentModelMessageRole.ASSISTANT, toolCalls = listOf(call)))
        val result = AgentModelContextCompactor.compact(messages, budget)
        assertEquals(call, result.messages.last().toolCalls.single())
    }

    private fun noisyReads(): List<AgentModelMessage> = (1..12).flatMap {
        block("read-$it", output = mapOf("text" to "unrelated page content ".repeat(800)))
    }

    @Test fun followupDoesNotDisplaceTheOriginalGoal() {
        val original = AgentModelMessage.user("Export all account records, preserving their original identifiers")
        val followup = AgentModelMessage.user("Continue after the network is restored")
        val result = AgentModelContextCompactor.compact(listOf(original) + noisyReads() + followup, budget)
        assertTrue(result.compacted)
        assertTrue(result.messages.contains(original))
        assertTrue(result.messages.contains(followup))
        assertPaired(result.messages)
    }

    @Test fun liveOperationsSurviveUnrelatedDiagnostics() {
        val messages = listOf(AgentModelMessage.user("Wait for the existing export; do not restart it")) +
            block("export", output = mapOf("operation_id" to "export-42", "state" to "running")) + noisyReads()
        val result = AgentModelContextCompactor.compact(messages, budget)
        val live = result.messages.single { it.toolResult?.callId == "export" }.toolResult!!
        assertEquals("export-42", live.output["operation_id"])
        assertTrue(AgentToolContextObservation.isLive(live))
        assertPaired(result.messages)
    }

    @Test fun completionOverridesAnOlderRunningState() {
        val result = AgentModelToolResultContent("done", "test.observe", "succeeded",
            output = mapOf("state" to "running", "complete" to true))
        assertFalse(AgentToolContextObservation.isLive(result))
    }

    @Test fun compactBrowserEvidenceKeepsPageFrameAndExactReadContinuation() {
        val source = AgentModelToolResultContent("browser", AgentInteractiveBrowserTools.OBSERVE, "succeeded",
            output = mapOf("session_id" to "account-session", "page_id" to "live-page", "frame_id" to "live-frame",
                "next_text_offset" to 32000, "next_control_offset" to 200, "text" to "long article ".repeat(10000)))
        val compacted = AgentToolContextObservation.compact(source)
        for (key in listOf("session_id", "page_id", "frame_id", "next_text_offset", "next_control_offset")) {
            assertEquals(source.output[key], compacted.output[key])
        }
        assertFalse(compacted.output.containsKey("text"))
    }

    private fun block(id: String, error: AgentNativeToolError? = null,
        output: AgentNativeJsonObject = emptyMap(), message: String = "") = listOf(
        AgentModelMessage(AgentModelMessageRole.ASSISTANT,
            toolCalls = listOf(AgentModelToolCall(id, "test.observe", mapOf("path" to id)))),
        AgentModelMessage(AgentModelMessageRole.TOOL,
            toolResult = AgentModelToolResultContent(id, "test.observe", if (error == null) "succeeded" else "failed",
                output, error = error, message = message)))

    private fun assertPaired(messages: List<AgentModelMessage>) {
        assertEquals(messages.flatMap { it.toolCalls }.map { it.callId }.toSet(),
            messages.mapNotNull { it.toolResult?.callId }.toSet())
    }
}
