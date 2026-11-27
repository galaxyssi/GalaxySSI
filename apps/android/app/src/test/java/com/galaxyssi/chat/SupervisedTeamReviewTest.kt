package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.After
import org.junit.Test

class SupervisedTeamReviewTest {
    private val chat = "fixture-chat"
    private val turn = java.util.UUID.randomUUID().toString()
    private val pin = GoalRoute("fixture-cloud", "fixture-model", "fingerprint", "example.invalid")
    private val answer = "Expand service under the stated assumptions."
    private val runtime = Any()
    private val response = AgentConnectorResponse(17L, pin.target, "control envelope", chat, turn)
    private val draft = TeamReviewDraft().apply { bind(revision, chat, turn, pin) }
    private val action = AgentAction("initial", AgentActionKind.CALL_CONNECTOR, pin.target, AgentRisk.LOW,
        AgentActionStatus.WAITING_RESPONSE, "Reason", mapOf(
            "connector_id" to pin.target, "manual_target_locked" to "true", "manual_model_id" to pin.model,
            "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, "supervised_iteration" to "0",
            INTERNAL_TASK_EXECUTION_MODE to AgentTaskExecutionMode.PLAN_ONLY.wireValue))
    private val pending = AgentActionResult(action.id, true, "Waiting", mapOf(
        "source_message_id" to "17", "awaiting_response" to "true"))
    private val finalResult = pending.copy(message = answer, metadata = pending.metadata + mapOf(
        "awaiting_response" to "false", "supervised_direct_response" to "true", "recovered_after_timeout" to "false"))

    private fun state(): AgentUiState {
        val screen = ScreenContext("fixture", pageTitle = "")
        val mode = PermissionMode.ASK_BEFORE_ACTION
        val context = AgentRuntimeContext("session", "", screen, mode, true, false, emptyList(),
            callableTargets = emptyList(), memories = emptyList(), knowledgeItems = emptyList(), knowledgeStats = AgentKnowledgeStats())
        return AgentUiState(AgentPhase.COMPLETED, "", screen, permissionMode = mode, highRiskGuard = true,
            callableTargets = emptyList(), runtimeContext = context, runningTaskCount = 0, steps = emptyList(),
            lastEvent = AgentEvent.GOAL_RECEIVED, sessionId = "session", lastActionResult = finalResult,
            plan = AgentPlan("", screen, emptyList(), listOf(action), plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE))
    }

    @After fun closeWindow() = draft.invalidate()

    private fun fresh(): SupervisedTeamReview {
        assertTrue(draft.arm(chat, turn, pin, answer, runtime))
        assertTrue(SupervisedTeamReview.markDelivery(response))
        return requireNotNull(draft.takeFresh(response, runtime))
    }

    @Test fun onlyOriginalFreshResponseAndPersistedBodyCanClaimTheOfferOnce() {
        assertFalse(draft.arm(chat, turn, pin.copy(endpointHash = "changed"), answer, runtime))
        assertTrue(draft.arm(chat, turn, pin, answer, runtime))
        assertFalse(draft.arm(chat, turn, pin, "replacement", runtime))
        assertFalse(draft.claim(chat, turn, pin))
        assertNull(draft.takeFresh(response, runtime))
        assertTrue(SupervisedTeamReview.hasPendingDelivery(turn))
        assertFalse(SupervisedTeamReview.markDelivery(response.copy(turnId = "other")))
        assertFalse(SupervisedTeamReview.markDelivery(response.copy(conversationId = "other")))
        assertFalse(SupervisedTeamReview.markDelivery(response.copy(resolvedContactId = "other")))
        assertFalse(SupervisedTeamReview.markDelivery(response.copy(success = false)))
        assertTrue(SupervisedTeamReview.markDelivery(response))
        assertFalse(SupervisedTeamReview.hasPendingDelivery(turn))
        assertNull(draft.takeFresh(response.copy(), runtime))
        val ticket = requireNotNull(draft.takeFresh(response, runtime))
        assertTrue(ticket.awaiting(AgentPhase.WAITING_RESPONSE, pending, action, 17L))
        assertTrue(ticket.completed(state(), 17L))
        assertFalse(draft.claim(chat, turn, pin, ticket))
        ticket.finalBody("other", turn, answer)
        assertFalse(ticket.persisted)
        ticket.finalBody(chat, "other", answer)
        assertFalse(ticket.persisted)
        ticket.finalBody(chat, turn, answer + " altered")
        assertFalse(ticket.persisted)
        ticket.finalBody(chat, turn, answer)
        assertTrue(draft.claim(chat, turn, pin, ticket))
        assertFalse(draft.claim(chat, turn, pin, ticket))
        assertFalse(SupervisedTeamReview.markDelivery(response))
    }

    @Test fun nullSnapshotsFailuresRecoveryAndUnsettledOrAlteredAnswersAreNotCompletion() {
        val ticket = fresh()
        val done = state()
        assertFalse(ticket.completed(null, 17L))
        assertFalse(ticket.completed(done.copy(lastActionResult = null), 17L))
        assertFalse(ticket.completed(done, 18L))
        for (phase in AgentPhase.values().filter { it != AgentPhase.COMPLETED }) {
            assertFalse(ticket.completed(done.copy(phase = phase), 17L))
        }
        for (result in listOf(finalResult.copy(success = false), finalResult.copy(message = response.content),
                finalResult.copy(metadata = finalResult.metadata - "supervised_direct_response"),
                finalResult.copy(metadata = finalResult.metadata + ("recovered_after_timeout" to "true")),
                finalResult.copy(metadata = finalResult.metadata + ("awaiting_response" to "true")),
                finalResult.copy(metadata = finalResult.metadata + ("rich_output" to "attachment")))) {
            assertFalse(ticket.completed(done.copy(lastActionResult = result), 17L))
        }
        assertFalse(ticket.persisted)
    }

    @Test fun repairedActionsOtherSourcesAndNonwaitingLoopsDoNotJoin() {
        val ticket = fresh()
        assertFalse(ticket.awaiting(AgentPhase.CANCELLED, pending, action, 17L))
        assertFalse(ticket.awaiting(AgentPhase.WAITING_RESPONSE, pending, action, 18L))
        for (changed in listOf(action.copy(id = "different"), action.copy(parameters = emptyMap()),
                action.copy(parameters = action.parameters + ("manual_model_id" to "different")),
                action.copy(parameters = action.parameters + ("supervised_iteration" to "1")),
                action.copy(parameters = action.parameters + (SUPERVISED_PROJECT_REPAIR_KIND_PARAMETER to "format")))) {
            assertFalse(ticket.awaiting(AgentPhase.WAITING_RESPONSE, pending, changed, 17L))
        }
    }

    @Test fun executableAnswerJoinsOnlyItsCompletedMarkerAndFinalSavedBody() {
        val ticket = fresh()
        val before = state()
        val original = requireNotNull(before.plan)
        val connector = action.copy(status = AgentActionStatus.COMPLETED)
        val marker = AgentAction("sp2-final", AgentActionKind.DRAFT_PLAN, "task-complete", AgentRisk.LOW,
            AgentActionStatus.COMPLETED, answer, result = answer)
        val plan = original.copy(actions = listOf(marker), actionHistory = listOf(connector), revision = original.revision + 1)
        val localResult = AgentActionResult(marker.id, true, answer, mapOf("execution_location" to "phone"))
        val done = before.copy(plan = plan, lastActionResult = localResult)
        assertFalse(ticket.completed(done, 17L))
        assertTrue(ticket.awaiting(AgentPhase.WAITING_RESPONSE, pending, action, 17L))
        assertTrue(ticket.completed(done, 17L))
        assertFalse(ticket.completed(done, 18L))
        assertTrue(ticket.finalized(original, done, done.copy(), 17L))
        assertFalse(ticket.finalized(original, null, done, 17L))
        assertFalse(ticket.finalized(original, done.copy(phase = AgentPhase.WAITING_CONFIRMATION), done, 17L))
        assertFalse(ticket.finalized(original, done, done.copy(phase = AgentPhase.CANCELLED), 17L))
        assertFalse(ticket.finalized(original, done, done.copy(sessionId = "restored"), 17L))
        assertFalse(ticket.finalized(original, done, done.copy(plan = plan.copy(planId = "other")), 17L))
        assertFalse(ticket.finalized(original.copy(revision = plan.revision), done, done, 17L))

        for (invalid in listOf(
            plan.copy(actions = listOf(marker, action)),
            plan.copy(actions = listOf(marker.copy(target = "other"))),
            plan.copy(actions = listOf(marker.copy(status = AgentActionStatus.RUNNING))),
            plan.copy(actions = listOf(marker.copy(description = "different"))),
            plan.copy(actions = listOf(marker.copy(result = "different"))),
            plan.copy(actionHistory = listOf(connector.copy(id = "other"))),
            plan.copy(actionHistory = listOf(connector.copy(status = AgentActionStatus.FAILED))),
            plan.copy(actionHistory = listOf(connector, connector.copy(id = "retry"))),
            plan.copy(actionHistory = listOf(connector.copy(parameters = connector.parameters +
                (SUPERVISED_PROJECT_REPAIR_KIND_PARAMETER to "format")))),
            plan.copy(artifactRichOutputJson = "attachment")
        )) assertFalse(ticket.completed(done.copy(plan = invalid), 17L))
        for (invalid in listOf(localResult.copy(actionId = "other"), localResult.copy(message = "different"),
            localResult.copy(success = false), localResult.copy(metadata = mapOf("action_effect_replayed" to "true")))) {
            assertFalse(ticket.completed(done.copy(lastActionResult = invalid), 17L))
        }
        assertFalse(draft.claim(chat, turn, pin, ticket))
        ticket.finalBody(chat, turn, "different")
        assertFalse(draft.claim(chat, turn, pin, ticket))
        ticket.finalBody(chat, turn, answer)
        assertTrue(draft.claim(chat, turn, pin, ticket))
    }

    @Test fun restoredRuntimeCannotConsumeEvenTheOriginalDelivery() {
        assertTrue(draft.arm(chat, turn, pin, answer, runtime))
        assertTrue(SupervisedTeamReview.markDelivery(response))
        assertNull(draft.takeFresh(response, Any()))
        assertNull(draft.takeFresh(response, runtime))
        assertFalse(draft.claim(chat, turn, pin))
    }

    @Test fun invalidationBetweenPersistenceAndPresentationCannotOfferIntoReboundWindow() {
        val ticket = fresh()
        ticket.finalBody(chat, turn, answer)
        draft.invalidate()
        draft.bind(draft.revision, chat, turn, pin)
        assertFalse(draft.claim(chat, turn, pin, ticket))
        assertTrue(draft.claim(chat, turn, pin))
    }

    @Test fun windowInvalidatedBeforePublishDropsItsDeliveryRegistration() {
        assertTrue(draft.arm(chat, turn, pin, answer, runtime))
        draft.invalidate()
        assertFalse(SupervisedTeamReview.hasPendingDelivery(turn))
        assertFalse(SupervisedTeamReview.markDelivery(response))
    }
}
