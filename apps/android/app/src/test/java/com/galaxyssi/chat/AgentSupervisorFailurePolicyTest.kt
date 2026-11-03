package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentSupervisorFailurePolicyTest {
    private fun connector(id: String) = AgentAction(id, AgentActionKind.CALL_CONNECTOR, "DeepSeek", AgentRisk.LOW,
        AgentActionStatus.FAILED, "Reason", parameters = mapOf("connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE))

    @Test fun nonRetriableProviderFailureCannotBecomeAnotherSupervisorRequest() {
        val action = connector("a")
        assertNotNull(AgentSupervisorFailurePolicy.stopReason(listOf(action), action,
            AgentActionResult(action.id, false, "No provider", mapOf("non_retriable" to "true"))))
    }

    @Test fun twoFailedSupervisionsStopWithoutLimitingSuccessfulWork() {
        val first = connector("a")
        val second = connector("b")
        assertNull(AgentSupervisorFailurePolicy.stopReason(listOf(first), first, null))
        assertNotNull(AgentSupervisorFailurePolicy.stopReason(listOf(first, second), second, null))
        val progress = connector("progress").copy(kind = AgentActionKind.CALL_NATIVE_TOOL,
            status = AgentActionStatus.COMPLETED, evidence = "verified")
        assertNull(AgentSupervisorFailurePolicy.stopReason(listOf(first, progress, second), second, null))
        val longHistory = (1..1000).map { progress.copy(id = "tool-$it") } + second
        assertNull(AgentSupervisorFailurePolicy.stopReason(longHistory, second, null))
    }

    @Test fun unavailableNativeToolStillAllowsModelRepair() {
        val action = connector("a").copy(kind = AgentActionKind.CALL_NATIVE_TOOL)
        assertNull(AgentSupervisorFailurePolicy.stopReason(listOf(action), action,
            AgentActionResult(action.id, false, "Missing dependency", mapOf("non_retriable" to "true"))))
    }

    @Test fun exhaustedFormatRepairDoesNotRestartAsGenericRecovery() {
        val action = connector("a")
        assertNotNull(AgentSupervisorFailurePolicy.stopReason(listOf(action), action, AgentActionResult(action.id,
            false, "Invalid plan", mapOf("failure_kind" to "invalid_supervised_project_plan", "structured_repair_attempts" to "3"))))
    }

    @Test fun pendingReviewerDoesNotHideConsecutiveFailures() {
        val a = connector("a")
        val b = connector("b")
        assertNotNull(AgentSupervisorFailurePolicy.stopReason(listOf(a, b, connector("c").copy(
            status = AgentActionStatus.PROPOSED)), b, null))
    }

    @Test fun unrelatedResultCannotStopThisAction() {
        val action = connector("a")
        assertNull(AgentSupervisorFailurePolicy.stopReason(listOf(action), action,
            AgentActionResult("other", false, "Unavailable", mapOf("non_retriable" to "true"))))
    }
}
