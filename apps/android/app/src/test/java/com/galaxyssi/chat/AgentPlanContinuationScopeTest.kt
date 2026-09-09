package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentPlanContinuationScopeTest {
    @Test fun persistedActionsRestoreScopeWithoutInMemoryContext() {
        assertEquals(AgentPlanContinuationScope("conversation", "turn"), resolve(plan(action())))
    }

    @Test fun activeScopeIsKeptForLegacyUnscopedActions() {
        val actual = AgentPlanContinuationScope.resolve(plan(action().copy(parameters = emptyMap())),
            "conversation", "turn", "runtime")
        assertEquals(AgentPlanContinuationScope("conversation", "turn"), actual)
    }

    @Test fun runtimeIsOnlyTheLegacyFallbackNotAReplacementForConversation() {
        assertEquals(AgentPlanContinuationScope("runtime", ""), resolve(plan(action().copy(parameters = emptyMap()))))
    }

    @Test fun conflictingConversationsDoNotReachThePlanner() {
        assertNull(AgentPlanContinuationScope.resolve(plan(action()), "other-conversation", "turn", "runtime"))
    }

    @Test fun newControlMessageTurnDoesNotRebindTheRunningTask() {
        assertEquals(AgentPlanContinuationScope("conversation", "turn"),
            AgentPlanContinuationScope.resolve(plan(action()), "conversation", "control-message-turn", "runtime"))
    }

    @Test fun mixedPersistedTurnsAreRejected() {
        assertNull(resolve(plan(action(), action().copy(parameters = mapOf(
            INTERNAL_CONVERSATION_ID to "conversation", INTERNAL_TURN_ID to "other-turn")))))
    }

    @Test fun mixedPersistedScopesAreNotGuessed() {
        assertNull(resolve(plan(action(), action().copy(parameters = mapOf(INTERNAL_CONVERSATION_ID to "other")))))
    }

    @Test fun previousHistoryCannotSupplyCurrentScope() {
        val plan = plan().copy(actionHistory = listOf(action()))
        assertEquals(AgentPlanContinuationScope("runtime", ""), resolve(plan))
    }

    @Test fun scopeRejectsExplicitForeignObservationsButAcceptsLegacyTaskActions() {
        val scope = AgentPlanContinuationScope("conversation", "turn")
        assertTrue(scope.owns(action()))
        assertTrue(scope.owns(action().copy(parameters = emptyMap())))
        assertFalse(scope.owns(action().copy(parameters = mapOf(INTERNAL_CONVERSATION_ID to "other"))))
        assertFalse(scope.owns(action().copy(parameters = mapOf(INTERNAL_TURN_ID to "other"))))
    }

    @Test fun modelCannotRebindTheNextActionToAnotherConversation() {
        val bound = AgentPlanContinuationScope("conversation", "turn").bind(action().copy(parameters = mapOf(
            INTERNAL_CONVERSATION_ID to "model-invented", INTERNAL_TURN_ID to "wrong", "tool_id" to "test.read")))
        assertEquals("conversation", bound.parameters[INTERNAL_CONVERSATION_ID])
        assertEquals("turn", bound.parameters[INTERNAL_TURN_ID])
        assertEquals("test.read", bound.parameters["tool_id"])
    }

    @Test fun scopeContextDoesNotNewlyExportMemoryOrConversationText() {
        val result = AgentPlanContinuationScope("conversation", "turn").context(
            AgentConversationContext("conversation", "PRIVATE SUMMARY", emptyList(), true,
                globalContext = "PRIVATE MEMORY", trackingPaused = true))
        assertTrue(result.privateMode)
        assertTrue(result.trackingPaused)
        assertEquals("", result.summary)
        assertEquals("", result.globalContext)
        assertTrue(result.turns.isEmpty())
    }

    private fun resolve(plan: AgentPlan) = AgentPlanContinuationScope.resolve(plan, "", "", "runtime")
    private fun plan(vararg actions: AgentAction) = AgentPlan("Task", ScreenContext("Test", pageTitle = "Test"),
        emptyList(), actions.toList())
    private fun action() = AgentAction("node", AgentActionKind.CALL_NATIVE_TOOL, "test.read", AgentRisk.LOW,
        AgentActionStatus.COMPLETED, "Read", mapOf(INTERNAL_CONVERSATION_ID to "conversation", INTERNAL_TURN_ID to "turn"))
}
