package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentRecordedExecutionEvidenceTest {
    private val scope = AgentPlanContinuationScope("conversation", "turn")
    private fun action(status: AgentActionStatus, id: String = "read", evidence: String = "") = scope.bind(
        AgentAction(id, AgentActionKind.CALL_NATIVE_TOOL, "device.read", AgentRisk.LOW, status, "Read device",
            parameters = mapOf("tool_id" to "device.read", "input_json" to "{}"),
            result = "Observed state", evidence = evidence))
    private fun plan(current: List<AgentAction>, history: List<AgentAction> = emptyList()) =
        AgentPlan("Read state", ScreenContext("Test", pageTitle = "Test"), emptyList(), current, actionHistory = history)
    private fun calls(current: List<AgentAction>, history: List<AgentAction> = emptyList(), result: AgentActionResult? = null) =
        AgentRecordedExecutionEvidence.calls(AgentRecordedExecutionEvidence.actions(plan(current, history), scope), result)
    private fun event(type: AgentRunControlEventType, step: String = "read", invocation: String = "invocation",
        tool: String = "device.read", at: Long = 20L, status: String = "succeeded") = AgentRunControlEvent(
            eventId = "event", conversationId = "conversation", messageId = "turn", taskId = "turn", runId = "run",
            agentId = "mobile", deviceId = "device", type = type, sequence = 1, timestampMillis = at,
            stepId = step, toolCallId = invocation, payload = mapOf("tool_id" to tool, "status" to status))

    @Test fun repairedActionReplacesItsEarlierFailure() {
        val earlier = action(AgentActionStatus.FAILED, evidence = "{\"error\":\"offline\"}")
        val latest = earlier.copy(status = AgentActionStatus.COMPLETED, evidence = "{\"value\":7}")
        val call = calls(listOf(latest), listOf(earlier)).single()
        assertEquals(AgentToolCallStatus.SUCCEEDED, call.status)
        assertEquals(7, JSONObject(call.resultJson).getInt("value"))
        assertFalse(call.resultJson.contains("offline"))
    }

    @Test fun newerFailureCannotBorrowEarlierSuccess() {
        val earlier = action(AgentActionStatus.COMPLETED, evidence = "{\"verified\":true}")
        val failed = earlier.copy(status = AgentActionStatus.FAILED, evidence = "{\"error\":\"unavailable\"}")
        val call = calls(listOf(failed), listOf(earlier), AgentActionResult("read", true, "Old success")).single()
        assertEquals(AgentToolCallStatus.FAILED, call.status)
        assertFalse(call.resultJson.contains("verified"))
        assertEquals("unavailable", JSONObject(call.resultJson).getString("error"))
    }

    @Test fun earlierNativeObservationsRemainStructuredAfterFinalReply() {
        val first = action(AgentActionStatus.COMPLETED, "first", "{\"delivery_verified\":false,\"message_id\":\"m1\"}")
        val second = action(AgentActionStatus.COMPLETED, "second", "{\"battery\":82}")
        val final = AgentActionResult("final", true, "Summary")
        val records = calls(listOf(second), listOf(first), final)
        assertFalse(JSONObject(records.first().resultJson).getBoolean("delivery_verified"))
        assertEquals("m1", JSONObject(records.first().resultJson).getString("message_id"))
        assertEquals(82, JSONObject(records.last().resultJson).getInt("battery"))
    }

    @Test fun finalProseCannotOverwriteAnObservedFailure() {
        val failed = action(AgentActionStatus.FAILED, evidence = "{\"status\":\"rejected\",\"error\":{\"code\":\"wrong_path\"}}")
        val result = AgentActionResult("read", true, "Complete", mapOf("native_tool_output" to "{\"verified\":true}"))
        val recorded = calls(listOf(failed), result = result).single()
        assertEquals(AgentToolCallStatus.FAILED, recorded.status)
        assertEquals("wrong_path", JSONObject(recorded.resultJson).getJSONObject("error").getString("code"))
    }

    @Test fun matchingUntruncatedNativeReceiptCanRestoreTheFullObservation() {
        val output = "{\"value\":7,\"state_verified\":false}"
        val current = action(AgentActionStatus.COMPLETED, evidence = output.take(12))
        val result = AgentActionResult("read", true, "Accepted", mapOf("native_tool_output" to output))
        assertFalse(JSONObject(calls(listOf(current), result = result).single().resultJson).getBoolean("state_verified"))
    }

    @Test fun truncatedAndNonJsonEvidenceSurvivesAsDataWithoutInventedVerification() {
        for (evidence in listOf("{\"state_verified\":", "executor_failure", "[1,2]")) {
            val json = JSONObject(calls(listOf(action(AgentActionStatus.FAILED, evidence = evidence))).single().resultJson)
            assertEquals(evidence, json.getString("evidence"))
            assertFalse(json.has("state_verified"))
        }
    }

    @Test fun invalidArgumentsAndOutputCannotBreakRunSerialization() {
        val current = action(AgentActionStatus.FAILED).copy(parameters = mapOf("tool_id" to "device.read", "input_json" to "{bad"))
        val result = AgentActionResult("read", false, "Invalid input", mapOf("native_tool_output" to "{truncated"))
        val recorded = calls(listOf(current), result = result).single()
        assertEquals("{bad", JSONObject(recorded.argumentsJson).getString("raw_input"))
        assertEquals("{truncated", JSONObject(recorded.resultJson).getString("evidence"))
    }

    @Test fun pendingAndRunningActionsAreNotFailuresEvenWhenTheRunEnds() {
        for (status in listOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION,
            AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE)) {
            val recorded = calls(listOf(action(status)), result = AgentActionResult("read", true, "Accepted")).single()
            assertEquals(if (status in listOf(AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE))
                AgentToolCallStatus.RUNNING else AgentToolCallStatus.PENDING, recorded.status)
            assertEquals("", recorded.errorMessage)
            assertFalse(AgentRecordedExecutionEvidence.lifecycle(recorded).contains(AgentRunControlEventType.TOOL_COMPLETED))
        }
    }

    @Test fun recordsKeepLogicalIdentityAndDoNotMixForeignTurnsOrConversations() {
        val owned = action(AgentActionStatus.COMPLETED)
        val foreignTurn = AgentPlanContinuationScope("conversation", "other").bind(owned.copy(id = "other-turn"))
        val foreignConversation = AgentPlanContinuationScope("foreign", "turn").bind(owned.copy(id = "other-conversation"))
        val result = AgentActionResult("read", true, "Read", mapOf("invocation_id" to "receipt-uuid"))
        assertEquals(listOf("read"), calls(listOf(owned, foreignTurn, foreignConversation), result = result).map { it.id })
    }

    @Test fun foreignLatestSnapshotCannotResurrectAnEarlierOwnedAction() {
        val old = action(AgentActionStatus.COMPLETED, evidence = "{\"value\":1}")
        val foreign = AgentPlanContinuationScope("other", "other").bind(old)
        assertTrue(calls(listOf(foreign), listOf(old)).isEmpty())
    }

    @Test fun nonNativeActionsAreNotInventedAsNativeCalls() {
        assertTrue(calls(listOf(action(AgentActionStatus.COMPLETED).copy(kind = AgentActionKind.CALL_CONNECTOR))).isEmpty())
    }

    @Test fun pendingHasNoLifecycleAndRunningHasNoCompletion() {
        val call = calls(listOf(action(AgentActionStatus.COMPLETED))).single()
        assertEquals(emptyList<AgentRunControlEventType>(), AgentRecordedExecutionEvidence.lifecycle(call.copy(status = AgentToolCallStatus.PENDING)))
        assertEquals(listOf(AgentRunControlEventType.TOOL_STARTED), AgentRecordedExecutionEvidence.lifecycle(call.copy(status = AgentToolCallStatus.RUNNING)))
        for (status in listOf(AgentToolCallStatus.SUCCEEDED, AgentToolCallStatus.FAILED, AgentToolCallStatus.CANCELLED)) {
            assertEquals(listOf(AgentRunControlEventType.TOOL_STARTED, AgentRunControlEventType.TOOL_COMPLETED),
                AgentRecordedExecutionEvidence.lifecycle(call.copy(status = status)))
        }
    }

    @Test fun preDispatchRejectionDoesNotInventAnExecutionStart() {
        val rejected = action(AgentActionStatus.BLOCKED, evidence = "{\"execution_started\":false,\"error\":\"denied\"}")
        assertEquals(listOf(AgentRunControlEventType.TOOL_COMPLETED), AgentRecordedExecutionEvidence.lifecycle(calls(listOf(rejected)).single()))
    }

    @Test fun nativeLifecycleWithInvocationIdIsNotDuplicatedUnderActionId() {
        val call = calls(listOf(action(AgentActionStatus.COMPLETED))).single()
        for (type in AgentRecordedExecutionEvidence.lifecycle(call)) {
            assertTrue(AgentRecordedExecutionEvidence.matches(call, event(type), type))
            assertTrue(AgentRecordedExecutionEvidence.matches(call, event(type, invocation = call.id), type))
            assertFalse(AgentRecordedExecutionEvidence.matches(call, event(type, step = "other"), type))
            assertFalse(AgentRecordedExecutionEvidence.matches(call, event(type, tool = "other"), type))
        }
    }

    @Test fun previousAttemptOrDifferentLifecycleStageCannotSuppressTheCurrentEvent() {
        val call = calls(listOf(action(AgentActionStatus.COMPLETED))).single().copy(startedAtMillis = 30)
        val type = AgentRunControlEventType.TOOL_COMPLETED
        assertFalse(AgentRecordedExecutionEvidence.matches(call, event(type, at = 20), type))
        assertTrue(AgentRecordedExecutionEvidence.matches(call, event(type, at = 40), type))
        assertFalse(AgentRecordedExecutionEvidence.matches(call, event(AgentRunControlEventType.TOOL_STARTED, at = 40), type))
    }

    @Test fun oldFailureCannotSuppressARepairedCompletionOrViceVersa() {
        val succeeded = calls(listOf(action(AgentActionStatus.COMPLETED))).single()
        val failed = succeeded.copy(status = AgentToolCallStatus.FAILED)
        val type = AgentRunControlEventType.TOOL_COMPLETED
        assertFalse(AgentRecordedExecutionEvidence.matches(succeeded, event(type, status = "failed"), type))
        assertFalse(AgentRecordedExecutionEvidence.matches(failed, event(type, status = "succeeded"), type))
        for (status in listOf("failed", "rejected", "unavailable", "verification_failed", "timed_out")) {
            assertTrue(AgentRecordedExecutionEvidence.matches(failed, event(type, status = status), type))
        }
        assertFalse(AgentRecordedExecutionEvidence.matches(succeeded, event(type, status = ""), type))
        assertFalse(AgentRecordedExecutionEvidence.matches(succeeded.copy(status = AgentToolCallStatus.PENDING), event(type), type))
    }

    @Test fun explicitNativeCancellationRemainsCancellationNotFailureOrSuccess() {
        val current = action(AgentActionStatus.FAILED, evidence = "{\"status\":\"cancelled\",\"message\":\"Stopped\"}")
        val recorded = calls(listOf(current)).single()
        assertEquals(AgentToolCallStatus.CANCELLED, recorded.status)
        val type = AgentRunControlEventType.TOOL_COMPLETED
        assertTrue(AgentRecordedExecutionEvidence.matches(recorded, event(type, status = "cancelled"), type))
        assertFalse(AgentRecordedExecutionEvidence.matches(recorded, event(type, status = "failed"), type))
    }
}
