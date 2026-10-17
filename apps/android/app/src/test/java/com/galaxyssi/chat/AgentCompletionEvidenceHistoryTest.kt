package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentCompletionEvidenceHistoryTest {
    private val scope = AgentPlanContinuationScope("conversation", "turn")
    private val read = AgentInteractiveBrowserTools.OBSERVE
    private val act = AgentInteractiveBrowserTools.ACT
    private val requirements = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false,
        outcomes = listOf(AgentObservedOutcome("location", read, mapOf("/page_id" to "page"),
            mapOf("/title" to "Verified location"), afterToolId = act)))
    private val browserDescriptors = AgentInteractiveBrowserTools.definitions(execute = { error("Must not execute") })
        .associate { it.descriptor.id to it.descriptor }
    private val receipt = """{"page_id":"page","title":"Verified location","url":"https://example.test/location","text":"The address is 10 Test Street."}"""

    @Test fun oversizedPlannerRequestsCannotEvictTheNewestSourceObservation() {
        val observed = action("source", read)
        val history = listOf(action("old-failure", read).copy(status = AgentActionStatus.FAILED),
            action("navigate", act, "navigate"), observed, connector())
        // This is the former failure: the planning request alone exhausts the 24k history budget.
        assertFalse(AgentProjectHistoryRetentionPolicy.retain(history).any { it.id == observed.id })
        val projected = plan(history).historyForReplan()
        assertTrue(projected.any { it.id == observed.id })
        assertEquals(setOf("connector_task_mode", INTERNAL_CONVERSATION_ID, INTERNAL_TURN_ID),
            projected.single(AgentAction::isSupervisedProjectConnector).parameters.keys)
        assertTrue(AgentSupervisedProjectProgressPolicy.promptBlock(projected)!!.contains("10 Test Street"))
    }

    @Test fun completionUsesExecutionEvidenceEvenWhenPromptBudgetDropsTheRequiredSource() {
        val source = action("source", read)
        val filler = (1..80).map { action("unrelated-$it", "galaxyssi.fixture.inspect")
            .copy(result = "Unrelated public observation. ".repeat(80), evidence = "") }
        val plan = plan(listOf(action("navigate", act, "navigate"), source) + filler + connector())
        assertFalse(plan.historyForReplan().any { it.id == source.id })
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements,
            AgentCompletionEvidenceHistory.resolve(plan, scope)).isEmpty())
    }

    @Test fun latestFailureOrPendingObservationCannotBeHiddenByOldSuccess() {
        for (status in listOf(AgentActionStatus.FAILED, AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE)) {
            val original = action("source", read)
            val plan = plan(listOf(action("navigate", act, "navigate"), original),
                listOf(original.copy(status = status)))
            val history = AgentCompletionEvidenceHistory.resolve(plan, scope)
            assertEquals(1, history.count { it.id == "source" })
            assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, history).isEmpty())
        }
    }

    @Test fun currentActionsOverrideHistoryWithoutReorderingIndependentEvidence() {
        val source = action("source", read).copy(status = AgentActionStatus.RUNNING)
        val plan = plan(listOf(action("navigate", act, "navigate"), source),
            listOf(source.copy(status = AgentActionStatus.COMPLETED)))
        assertEquals(listOf("navigate", "source"), AgentCompletionEvidenceHistory.resolve(plan, scope).map { it.id })
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements,
            AgentCompletionEvidenceHistory.resolve(plan, scope)).isEmpty())
    }

    @Test fun evidenceCannotCrossConversationOrTurnEvenWithTheSameActionId() {
        for (foreign in listOf(AgentPlanContinuationScope("other", "turn"), AgentPlanContinuationScope("conversation", "other"))) {
            val source = foreign.bind(action("source", read))
            val history = AgentCompletionEvidenceHistory.resolve(plan(listOf(action("navigate", act, "navigate"), source)), scope)
            assertFalse(history.any { it.id == "source" })
            assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, history).isEmpty())
            val own = action("source", read)
            assertEquals(own, AgentCompletionEvidenceHistory.resolve(plan(listOf(own, source)), scope).single())
        }
    }

    @Test fun newNavigationStillInvalidatesAnOlderObservation() {
        val history = AgentCompletionEvidenceHistory.resolve(plan(listOf(action("navigate", act, "navigate"),
            action("source", read), action("new-navigation", act, "navigate"))), scope)
        assertEquals("observation_stale", AgentObservedOutcomeEvidence.diagnose(requirements.outcomes.single(), history)!!.getString("code"))
    }

    @Test fun browserNavigationDoesNotDemandAnExternalBusinessPostcondition() {
        for (operation in listOf("create", "navigate", "back", "close")) {
            val navigation = action("navigation", act, operation)
            assertTrue(browserDescriptors.getValue(act).requiresEffectClaim)
            assertFalse(operation, needsPostcondition(listOf(navigation, action("source", read))))
        }
    }

    @Test fun potentiallyEffectfulBrowserOperationsStillRequireVerification() {
        for (operation in listOf("click", "fill", "select", "dialog", "request_user_control", "unknown", "")) {
            assertTrue(operation, needsPostcondition(listOf(action("effect", act, operation))))
        }
        assertTrue(needsPostcondition(listOf(action("effect", act).copy(parameters = mapOf("tool_id" to act, "input_json" to "{broken")))))
    }

    @Test fun navigationWithAnUnknownOrUnfinishedOutcomeCannotBypassVerification() {
        for (status in listOf(AgentActionStatus.FAILED, AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE,
            AgentActionStatus.ROLLED_BACK)) {
            assertTrue(needsPostcondition(listOf(action("navigation", act, "navigate").copy(status = status))))
        }
        assertTrue(needsPostcondition(listOf(action("navigation", act, "navigate")
            .copy(evidence = """{"state_verified":false}"""))))
    }

    @Test fun neverDispatchedOrBlockedEffectsDoNotCreatePhantomVerificationWork() {
        for (status in listOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION, AgentActionStatus.BLOCKED)) {
            val action = action("effect", act, "click").copy(status = status)
            assertFalse(needsPostcondition(listOf(action)))
            if (status != AgentActionStatus.BLOCKED) assertFalse(needsPostcondition(listOf(action.supersededByPlanRevision(1, 2))))
        }
        for (status in listOf(AgentActionStatus.FAILED, AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE, AgentActionStatus.ROLLED_BACK)) {
            assertTrue(needsPostcondition(listOf(action("effect", act, "click").copy(status = status))))
        }
    }

    @Test fun sendingMessagesRemainsEffectfulEvenIfItUsesANavigateParameter() {
        val tool = "galaxyssi.fixture.message.send"
        assertTrue(AgentCompletionEvidenceHistory.needsBusinessPostcondition(requirements.copy(outcomes = emptyList()),
            listOf(action("send", tool, "navigate"))) { browserDescriptors.getValue(act).copy(id = tool) })
    }

    @Test fun explicitOutcomeRequirementsRemainEnforcedForNavigation() {
        val history = listOf(action("navigation", act, "navigate"), action("source", read))
        assertFalse(AgentCompletionEvidenceHistory.needsBusinessPostcondition(requirements, history) { browserDescriptors[it] })
        val mismatched = requirements.copy(outcomes = listOf(requirements.outcomes.single().copy(checks = mapOf("/title" to "Not observed"))))
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(mismatched, history).isEmpty())
    }

    @Test fun fullSourceEvidenceSurvivesColdRestoreWithoutRequeryingTheWebsite() {
        val storage = MemoryStorage()
        val source = action("source", read).copy(evidence = JSONObject(receipt).put("text", "x".repeat(12000) + " 10 Test Street").toString())
        val original = plan(listOf(action("navigate", act, "navigate"), source, connector()))
        SharedPreferencesAgentSessionStore(storage).save(AgentSessionSnapshot("session", AgentPhase.WAITING_RESPONSE,
            original.goal, original.screen, original, emptyList(), null, updatedAtMillis = 1000))
        val restored = SharedPreferencesAgentSessionStore(storage).load()!!.currentPlan!!
        val history = AgentCompletionEvidenceHistory.resolve(restored, scope)
        assertEquals(source.evidence, history.single { it.id == "source" }.evidence)
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, history).isEmpty())
        assertTrue(restored.historyForReplan().single(AgentAction::isSupervisedProjectConnector).evidence.isEmpty())
    }

    @Test fun firstSuccessfulResultAfter55RecoveryRoundsCanFinishWithoutAnotherBrowserAction() {
        val attempts = (1..55).flatMap { round -> listOf(
            action("failed-$round", read).copy(status = AgentActionStatus.FAILED,
                evidence = """{"error":{"code":"session_lost"}}"""),
            connector().copy(id = "planner-$round")) }
        val source = action("source", read)
        val plan = plan(attempts + action("navigate", act, "navigate") + source, listOf(connector()))
        val history = AgentCompletionEvidenceHistory.resolve(plan, scope)
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(requirements, history,
            finalAnswer = "The address is 10 Test Street.").isEmpty())
        assertFalse(AgentCompletionEvidenceHistory.needsBusinessPostcondition(requirements, history) { browserDescriptors[it] })
        assertNull(AgentGoalEvidence.pendingReceipt(history))
        assertEquals(source, plan.historyForReplan().last { !it.isSupervisedProjectConnector() })
        assertEquals(56, plan.historyForReplan().count(AgentAction::isSupervisedProjectConnector))
    }

    @Test fun compactPlannerMarkersPreserveRecoveryRoutingAndIterationWithoutPromptBodies() {
        val control = connector().copy(parameters = connector().parameters + mapOf(
            AgentUnverifiedOutcomeRecovery.PHONE_CONTROL to "true",
            AgentUnverifiedOutcomeRecovery.ORIGIN_ACTION to "effect",
            "supervised_iteration" to "55", "prompt" to "sensitive context"), result = "old model answer")
        val history = plan(listOf(control, action("source", read))).historyForReplan()
        val marker = history.single(AgentAction::isSupervisedProjectConnector)
        assertEquals("55", marker.parameters["supervised_iteration"])
        assertEquals("effect", marker.parameters[AgentUnverifiedOutcomeRecovery.ORIGIN_ACTION])
        assertEquals("true", marker.parameters[AgentUnverifiedOutcomeRecovery.PHONE_CONTROL])
        assertEquals(scope.turnId, marker.parameters[INTERNAL_TURN_ID])
        assertFalse(marker.parameters.containsKey("prompt"))
        assertTrue(marker.result.isEmpty())
    }

    @Test fun compactControlMarkersDoNotHideTheActualProviderFailureFromRecovery() {
        val failed = connector().copy(status = AgentActionStatus.FAILED,
            evidence = "Provider connection closed before response", result = "Request failed")
        val foreign = AgentPlanContinuationScope("other", "turn").bind(failed.copy(id = "foreign"))
        val plan = plan(listOf(failed, foreign))
        assertEquals(failed, AgentCompletionEvidenceHistory.latestFailure(plan, scope))
        val request = AgentRequest(plan.goal, plan.screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build("runtime", plan.goal, plan.screen,
                PermissionMode.FULL_ACCESS, false, false, emptyList(), emptyList()),
            executionHistory = plan.historyForReplan().filter(scope::owns))
        val prompt = AgentSupervisedProjectLoop.recoveryPrompt(request, failed, "Provider failed")
        assertTrue(prompt.contains(failed.evidence))
        assertFalse(prompt.contains("context-30"))
        assertNull(AgentCompletionEvidenceHistory.latestFailure(plan.copy(actions = listOf(
            failed.copy(status = AgentActionStatus.COMPLETED))), scope))
    }

    private fun needsPostcondition(history: List<AgentAction>) = AgentCompletionEvidenceHistory.needsBusinessPostcondition(
        requirements.copy(outcomes = emptyList()), history) { browserDescriptors[it] }

    private fun action(id: String, tool: String, operation: String = "observe") = scope.bind(AgentAction(id,
        AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW, AgentActionStatus.COMPLETED, "Inspect source",
        mapOf("tool_id" to tool, "input_json" to JSONObject().put("operation", operation).toString()), evidence = receipt))

    private fun connector() = scope.bind(AgentAction("planner", AgentActionKind.CALL_CONNECTOR, "Codex",
        AgentRisk.LOW, AgentActionStatus.COMPLETED, "Reason about the source",
        (1..30).associate { "context-$it" to "x".repeat(1200) } +
            ("connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE)))

    private fun plan(history: List<AgentAction>, current: List<AgentAction> = emptyList()) = AgentPlan(
        "Find a location", ScreenContext(foregroundApp = "Test", pageTitle = "Test"), emptyList(), current,
        planId = "plan", plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE, actionHistory = history,
        completionRequirements = requirements)

    private class MemoryStorage : AgentSessionCheckpointStorage {
        private val values = linkedMapOf<String, String>()
        override fun encodedValueLength(key: String) = values[key]?.length ?: 0
        override fun readString(key: String, defaultValue: String) = values[key] ?: defaultValue
        override fun writeString(key: String, value: String) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
        override fun keys() = values.keys.toSet()
    }
}
