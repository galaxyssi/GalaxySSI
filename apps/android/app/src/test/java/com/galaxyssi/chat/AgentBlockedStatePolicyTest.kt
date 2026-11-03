package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentBlockedStatePolicyTest {
    private val scope = AgentPlanContinuationScope("conversation", "turn")
    private val action = scope.bind(AgentAction("effect", AgentActionKind.CALL_NATIVE_TOOL, "write", AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Accepted", mapOf("tool_id" to "write"),
        evidence = """{"state_verified":false,"message":"Read the affected state before retrying"}"""))
    private val plan = AgentPlan("Verify the changed state", ScreenContext("Test", pageTitle = "Test"), emptyList(),
        listOf(action), planId = "plan")
    private val token = AgentRuntimeOutcomeContinuation.forPlan("session", scope, plan)!!
    private val result = token.bind(AgentOutcomeCompletion.blockedResult(AgentActionResult("effect", true, "Accepted"),
        AgentOutcomeCompletion.pending(AgentPhase.COMPLETED, plan, scope) { null }))
    private val loop = AgentExecutionLoopSnapshot("turn", AgentExecutionLoopPhase.BLOCKED,
        AgentExecutionLoopBudget(), AgentExecutionLoopUsage(), revision = 5, startedAtMillis = 1,
        updatedAtMillis = 1_000, lastProgressAtMillis = 100)
    private fun state() = AgentRecoveryTranscript.state(AgentSessionSnapshot("session", AgentPhase.BLOCKED,
        plan.goal, plan.screen, plan, emptyList(), result, executionLoopSnapshot = loop, updatedAtMillis = 1_000))
    private fun event(state: AgentUiState = state()) =
        AgentBlockedStatePolicy.outcomeWaitEvent(state, "run", "conversation", "turn", "device")

    @Test fun exactBusinessReasonSurvivesAnEmptyOrInformationalSafetyReview() {
        assertEquals(result.message, AgentBlockedStatePolicy.reason(state()))
        assertEquals(result.message, AgentBlockedStatePolicy.reason(state().copy(plan =
            plan.copy(safetyReview = AgentSafetyReview(blocked = false, reason = "Execution allowed")))))
    }

    @Test fun actualPolicyDenialTakesPrecedenceAndCannotOfferOutcomeResume() {
        val denied = state().copy(plan = plan.copy(safetyReview = AgentSafetyReview(blocked = true, reason = "Access denied")))
        assertEquals("Access denied", AgentBlockedStatePolicy.reason(denied))
        assertNull(AgentRuntimeOutcomeContinuation.forControls(denied))
        assertEquals(listOf(AgentExecutionLoopTimelineAction.CANCEL), AgentExecutionLoopTimelinePolicy.actionsForState(denied))
    }

    @Test fun successfulOrMissingReceiptsNeverMasqueradeAsBlockReasons() {
        val successful = state().copy(lastActionResult = AgentActionResult("read", true, "Everything succeeded"))
        assertEquals("Fallback", AgentBlockedStatePolicy.reason(successful, "Fallback"))
        assertEquals("Fallback", AgentBlockedStatePolicy.reason(state().copy(lastActionResult = null), "Fallback"))
        assertEquals("Fallback", AgentBlockedStatePolicy.reason(state().copy(lastActionResult = result.copy(message = "  ")), "Fallback"))
        for (phase in AgentPhase.entries.filter { it != AgentPhase.BLOCKED }) {
            assertEquals("", AgentBlockedStatePolicy.reason(state().copy(phase = phase)))
        }
    }

    @Test fun ownedUnknownOutcomeOffersResumeAndCancelInsteadOfBlindRetryOrReplan() {
        assertEquals(token, AgentRuntimeOutcomeContinuation.forControls(state()))
        assertEquals(listOf(AgentExecutionLoopTimelineAction.RESUME, AgentExecutionLoopTimelineAction.CANCEL),
            AgentExecutionLoopTimelinePolicy.actionsForState(state()))
        assertTrue(AgentBlockedStatePolicy.retainsRun(state()))
    }

    @Test fun missingOrForeignBindingsCannotOfferExecutionControls() {
        val invalid = listOf(state().copy(lastActionResult = result.copy(metadata = result.metadata - AgentRuntimeOutcomeContinuation.KEY)),
            state().copy(sessionId = "other"), state().copy(plan = null), state().copy(plan = plan.copy(planId = "other")),
            state().copy(plan = plan.copy(revision = 2)), state().copy(plan = plan.copy(actions = listOf(
                action.copy(parameters = action.parameters + (INTERNAL_TURN_ID to "other"))))))
        for (value in invalid) {
            assertNull(AgentRuntimeOutcomeContinuation.forControls(value))
            assertEquals(listOf(AgentExecutionLoopTimelineAction.CANCEL), AgentExecutionLoopTimelinePolicy.actionsForState(value))
        }
    }

    @Test fun controlPresentationIsNotAuthorityToResumeAnAlteredReceipt() {
        val changed = plan.copy(actions = listOf(action.copy(evidence = "{}")))
        assertNotNull(AgentRuntimeOutcomeContinuation.forControls(state().copy(plan = changed)))
        assertFalse(token.matches("session", scope, changed))
        assertEquals(AgentActionStatus.COMPLETED, plan.actions.single().status)
    }

    @Test fun permissionWaitAndOrdinaryFailureKeepTheirExistingControls() {
        val permission = AgentRuntimePermissionContinuation("session", "conversation", "turn", "plan", 1,
            "effect", listOf("android.permission.READ_CALENDAR"))
        val pending = state().copy(plan = plan.copy(actions = listOf(action.copy(status = AgentActionStatus.PROPOSED))),
            lastActionResult = permission.result(false))
        assertTrue(AgentBlockedStatePolicy.retainsRun(pending))
        assertEquals(listOf(AgentExecutionLoopTimelineAction.PAUSE, AgentExecutionLoopTimelineAction.CANCEL),
            AgentExecutionLoopTimelinePolicy.actionsForState(pending))
        val failure = state().copy(lastActionResult = AgentActionResult("effect", false, "Denied"))
        assertFalse(AgentBlockedStatePolicy.retainsRun(failure))
        assertEquals(listOf(AgentExecutionLoopTimelineAction.REPLAN, AgentExecutionLoopTimelineAction.CANCEL),
            AgentExecutionLoopTimelinePolicy.actionsForState(failure))
        for (phase in listOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED)) {
            assertFalse(AgentBlockedStatePolicy.retainsRun(state().copy(phase = phase)))
        }
    }

    @Test fun backgroundWaitEventIsStableBoundedAndOwned() {
        val first = requireNotNull(event())
        assertEquals(first, event())
        assertEquals(first.eventId, first.idempotencyKey)
        assertTrue(first.eventId.length < 100)
        assertEquals(1_000L, first.timestampMillis)
        assertEquals(AgentRunControlEventType.WAITING_FOR_USER, first.type)
        assertEquals(result.message, first.payload["loop_reason"])
        val restored = requireNotNull(org.json.JSONObject(first.toJson().toString()).toRunEvent())
        AgentRunKernelContract.requireIdempotentReplay(restored, requireNotNull(event()))
        assertNull(event(state().copy(executionLoop = null)))
        assertNull(event(state().copy(executionLoop = loop.copy(taskId = "other"))))
        assertNull(event(state().copy(phase = AgentPhase.FAILED)))
        assertNull(AgentBlockedStatePolicy.outcomeWaitEvent(state(), "run", "other", "turn", "device"))
        assertNull(AgentBlockedStatePolicy.outcomeWaitEvent(state(), "run", "conversation", "other", "device"))
    }

    @Test fun newWaitGenerationCannotReuseAnEarlierEventIdentity() {
        val first = requireNotNull(event()).eventId
        assertNotEquals(first, event(state().copy(executionLoop = loop.copy(revision = 6)))!!.eventId)
        assertNotEquals(first, event(state().copy(plan = plan.copy(revision = 2)))!!.eventId)
        assertNotEquals(first, event(state().copy(lastActionResult = result.copy(message = "Observer unavailable")))!!.eventId)
        assertNotEquals(first, event(state().copy(sessionId = "different-session"))!!.eventId)
    }

    @Test fun unknownOutcomeWaitCanRecoverOrCancelWithoutAnInterveningFailure() {
        val runtime = AgentExecutionLoop.create { 1_000L }
        runtime.start("turn", AgentExecutionLoopBudget())
        runtime.transition(AgentExecutionLoopPhase.ACT, actionId = "effect", toolCall = true)
        runtime.transition(AgentExecutionLoopPhase.OBSERVE)
        val blocked = runtime.transition(AgentExecutionLoopPhase.BLOCKED, result.message)
        val waiting = AgentExecutionLoopTimelinePolicy.project(blocked, outcomeWait = true)
        assertEquals(AgentRunControlEventType.WAITING_FOR_USER, waiting.controlEventType)
        assertEquals("other", waiting.payload["timeline_kind"])
        val control = AgentRunEventStore.reduce(AgentRunControlState.RUNNING, waiting.controlEventType)
        assertEquals(AgentRunControlState.WAITING_FOR_USER, control)
        val resumed = AgentExecutionLoopTimelinePolicy.project(runtime.transition(AgentExecutionLoopPhase.PLAN, retry = true))
        assertEquals(AgentRunControlState.RUNNING, AgentRunEventStore.reduce(control, resumed.controlEventType))
        assertEquals(AgentRunControlState.CANCELLED, AgentRunEventStore.reduce(control, AgentRunControlEventType.RUN_CANCELLED))
        assertEquals(AgentRunControlEventType.RUN_FAILED, AgentExecutionLoopTimelinePolicy.project(blocked).controlEventType)
    }
}
