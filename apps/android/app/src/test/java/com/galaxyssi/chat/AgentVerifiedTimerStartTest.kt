package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentVerifiedTimerStartTest {
    private val tool = AgentVerifiedTimerStart.toolId
    private val timer = AgentAction("start", AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.MEDIUM,
        AgentActionStatus.COMPLETED, "Start timer", parameters = mapOf("tool_id" to tool,
            "input_json" to """{"target":"timer","parameters":{"timer_operation":"start","timer_seconds":60}}"""))
    private val reviewer = timer.copy(id = "review", kind = AgentActionKind.CALL_CONNECTOR,
        status = AgentActionStatus.WAITING_RESPONSE, parameters = mapOf(
            "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
            "depends_on" to timer.id, "use_outputs_from" to timer.id))
    private val local = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false)
    private val output = """{"success":true,"message":"Timer started","metadata":{"execution_authority":"galaxyssi-phone","goal_status":"verified","operation_id":"fixture-timer","timer_state":"running","duration_seconds":"60","business_success_verified":"true"}}"""
    private val receipt = AgentActionResult(timer.id, true, "", mapOf("native_tool_id" to tool,
        "native_tool_status" to "succeeded", "invocation_id" to "fixture-invocation", "native_tool_output" to output))

    private fun evaluate(goal: String = "1 minute", action: AgentAction = timer, result: AgentActionResult = receipt,
        active: List<AgentAction> = listOf(action.copy(evidence = output), reviewer),
        requirements: AgentCompletionRequirements = local) =
        AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome(goal, active, action, result, requirements, active)

    @Test fun verifiedDurationReplyClosesDespitePendingReviewOrEarlierRejectedAttempt() {
        for (goal in listOf("1 minute", "1\u5206\u949f", "\u8bbe\u7f6e1\u5206\u949f\u5012\u8ba1\u65f6")) {
            val active = listOf(timer.copy(evidence = output), reviewer)
            val rejected = timer.copy(id = "first", status = AgentActionStatus.FAILED,
                evidence = """{"status":"rejected","error":{"code":"schema_validation_failed"}}""")
            val result = AgentSupervisedProjectCompletionPolicy.verifiedTerminalOutcome(goal,
                listOf(rejected) + active, timer, receipt, local, active)
            assertEquals("Timer started", result?.message)
        }
    }

    @Test fun dispatchUnknownPausedAndMismatchedReceiptsCannotClose() {
        for ((key, badValue) in listOf("goal_status" to "dispatched", "timer_state" to "paused",
            "duration_seconds" to "120", "operation_id" to "", "business_success_verified" to "false",
            "execution_authority" to "desktop")) {
            val raw = JSONObject(output).apply { getJSONObject("metadata").put(key, badValue) }.toString()
            assertNull(key, evaluate(result = receipt.copy(metadata = receipt.metadata + ("native_tool_output" to raw))))
        }
        assertNull(evaluate(result = receipt.copy(actionId = "another-node")))
        assertNull(evaluate(result = receipt.copy(success = false)))
        assertNull(evaluate(result = receipt.copy(metadata = receipt.metadata - "invocation_id")))
        assertNull(evaluate(goal = "2 minutes"))
        val input = JSONObject(timer.parameters.getValue("input_json"))
        input.getJSONObject("parameters").put("operation_id", "another-timer")
        assertNull(evaluate(action = timer.copy(parameters = timer.parameters + ("input_json" to input.toString()))))
    }

    @Test fun doNotFinishOtherWorkOrConfuseInspectWithStart() {
        assertNull(evaluate(goal = "Start a one-minute timer and tell me when it finishes"))
        assertNull(evaluate(active = listOf(timer, reviewer, timer.copy(id = "notify", status = AgentActionStatus.PROPOSED))))
        assertNull(evaluate(requirements = local.copy(results = listOf(AgentGoalResultRequirement("answer", "Explain")))))
        for (operation in listOf("inspect", "pause", "replace", "cancel", "resume")) {
            assertNull(operation, evaluate(action = timer.copy(parameters = timer.parameters +
                ("input_json" to timer.parameters.getValue("input_json").replace("start", operation)))))
        }
    }

    @Test fun legacyReviewMustDependOnlyOnThisCompletedTimer() {
        assertEquals(timer, AgentVerifiedTimerStart.waitingStart(listOf(timer, reviewer), reviewer.id))
        assertNull(AgentVerifiedTimerStart.waitingStart(listOf(timer, reviewer), "another-review"))
        assertNull(AgentVerifiedTimerStart.waitingStart(listOf(timer, reviewer, timer.copy(id = "another")), reviewer.id))
        assertNull(AgentVerifiedTimerStart.waitingStart(listOf(timer, reviewer.copy(parameters =
            reviewer.parameters + ("use_outputs_from" to "other"))), reviewer.id))
        assertNull(AgentVerifiedTimerStart.waitingStart(listOf(timer.copy(status = AgentActionStatus.FAILED), reviewer), reviewer.id))
    }

    @Test fun duplicateReceiptDoesNotCreateNewWorkOrOverrideNewerFailures() {
        val active = listOf(timer.copy(evidence = output))
        assertNull(AgentVerifiedTimerStart.waitingStart(active, reviewer.id))
        assertEquals("Timer started", evaluate(active = active)?.message)
        assertNull(evaluate(active = listOf(timer.copy(status = AgentActionStatus.FAILED))))
        assertNull(evaluate(active = listOf(timer, reviewer.copy(status = AgentActionStatus.FAILED))))
    }
}
