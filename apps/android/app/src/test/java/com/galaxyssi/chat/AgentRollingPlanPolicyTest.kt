package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRollingPlanPolicyTest {
    @Test
    fun completedGuardedModelBatchRequestsAnotherModelDecision() {
        assertTrue(
            AgentRollingPlanPolicy.shouldRequestNextBatch(
                plan = plan(action(status = AgentActionStatus.COMPLETED)),
                result = result(success = true)
            )
        )
    }

    @Test
    fun pendingFailedAndAwaitingBatchesDoNotRequestSuccessfulContinuation() {
        assertFalse(
            AgentRollingPlanPolicy.shouldRequestNextBatch(
                plan(action(status = AgentActionStatus.PENDING_CONFIRMATION)),
                result(success = true)
            )
        )
        assertFalse(
            AgentRollingPlanPolicy.shouldRequestNextBatch(
                plan(action(status = AgentActionStatus.FAILED)),
                result(success = false)
            )
        )
        assertFalse(
            AgentRollingPlanPolicy.shouldRequestNextBatch(
                plan(action(status = AgentActionStatus.WAITING_RESPONSE)),
                result(success = true, awaitingResponse = true)
            )
        )
    }

    @Test
    fun terminalMarkerAndNonModelPlansKeepTheirExistingCompletionPath() {
        assertFalse(
            AgentRollingPlanPolicy.shouldRequestNextBatch(
                plan(action(status = AgentActionStatus.COMPLETED).copy(
                    kind = AgentActionKind.DRAFT_PLAN,
                    target = "task-complete"
                )),
                result(success = true)
            )
        )
        assertFalse(
            AgentRollingPlanPolicy.shouldRequestNextBatch(
                plan(action(status = AgentActionStatus.COMPLETED)).copy(
                    plannerProfile = "rule-based-information-route"
                ),
                result(success = true)
            )
        )
        assertFalse(
            AgentRollingPlanPolicy.shouldRequestNextBatch(
                plan(
                    action(status = AgentActionStatus.COMPLETED).copy(
                        kind = AgentActionKind.CALL_CONNECTOR,
                        parameters = mapOf(
                            "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE
                        )
                    )
                ),
                result(success = true)
            )
        )
    }

    @Test
    fun batchReasonIsStableAndRecognizable() {
        val plan = plan(action(status = AgentActionStatus.COMPLETED)).copy(revision = 7)
        val reason = AgentRollingPlanPolicy.reason(plan, result(success = true))

        assertTrue(AgentRollingPlanPolicy.isBatchBoundaryReason(reason))
        assertTrue(reason.contains("revision=7"))
        assertTrue(reason.contains("last_action=action"))
    }

    private fun plan(action: AgentAction) = AgentPlan(
        goal = "Complete a long-running project",
        screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent"),
        steps = emptyList(),
        actions = listOf(action),
        confirmationRequired = false,
        plannerProfile = "guarded-model:test"
    )

    private fun action(status: AgentActionStatus) = AgentAction(
        id = "action",
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = "tool",
        risk = AgentRisk.LOW,
        status = status,
        description = "Inspect evidence",
        requiresConfirmation = false
    )

    private fun result(
        success: Boolean,
        awaitingResponse: Boolean = false
    ) = AgentActionResult(
        actionId = "action",
        success = success,
        message = "observed",
        metadata = if (awaitingResponse) mapOf("awaiting_response" to "true") else emptyMap()
    )
}
