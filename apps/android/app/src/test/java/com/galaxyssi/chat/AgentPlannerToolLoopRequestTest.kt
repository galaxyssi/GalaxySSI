package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentPlannerToolLoopRequestTest {
    @Test fun samePlanningRevisionRetainsItsIdentityAcrossFreshContextSnapshots() {
        val first = create(request())
        val original = request()
        val refreshed = create(original.copy(runtimeContext = original.runtimeContext.copy(createdAtMillis = 999999)))
        assertEquals(first.loopId, refreshed.loopId)
        assertEquals(first.recoveryInputIdentity, refreshed.recoveryInputIdentity)
        assertNotEquals(first.loopId, create(original.copy(planningRevision = 2)).loopId)
        assertNotEquals(first.loopId, create(original.copy(goal = "Different goal")).loopId)
    }
    @Test fun planningKeepsTheExecutionAndConversationIdentity() {
        val loop = create(request())
        assertEquals("session", loop.sessionId)
        assertEquals("conversation", loop.conversationId)
        assertEquals("turn", loop.turnId)
        assertEquals("turn", loop.taskId)
        assertEquals(AgentWorkspaceScope.id("conversation", "session"), loop.workspaceId)
    }

    @Test fun replansHaveOneWorkspaceButDistinctLoopAttempts() {
        val first = create(request())
        val second = create(request().copy(replanReason = "Observed tool output"))
        assertEquals(first.workspaceId, second.workspaceId)
        assertEquals(first.taskId, second.taskId)
        assertEquals(first.turnId, second.turnId)
        assertNotEquals(first.loopId, second.loopId)
    }

    @Test fun sameConversationSurvivesAnotherRuntimeSessionAndTurn() {
        val first = create(request())
        val next = create(request(session = "restarted-session", turn = "later-turn"))
        assertEquals(first.workspaceId, next.workspaceId)
        assertNotEquals(first.taskId, next.taskId)
        assertNotEquals(first.sessionId, next.sessionId)
    }

    @Test fun differentConversationsCannotShareAWorkspace() {
        assertNotEquals(create(request()).workspaceId, create(request(conversation = "other")).workspaceId)
    }

    @Test fun legacyMissingConversationAndTurnUseTheRuntimeSession() {
        val loop = create(request(conversation = "", turn = ""))
        assertEquals("session", loop.conversationId)
        assertEquals("session", loop.taskId)
        assertEquals("session", loop.turnId)
        assertEquals(AgentWorkspaceScope.id("", "session"), loop.workspaceId)
    }

    @Test fun copyingARequestPreservesItsLoopIdentityForResume() {
        val loop = create(request())
        assertEquals(loop.loopId, loop.copy(messages = listOf(AgentModelMessage.user("Resume"))).loopId)
        assertThrows(IllegalArgumentException::class.java) { loop.copy(loopId = " ") }
    }

    @Test fun eventSinkAndProgressBudgetAreNotLostByTheFactory() {
        val sink = AgentModelToolLoopEventSink { }
        val messages = listOf(AgentModelMessage.system("System"), AgentModelMessage.user("Goal"))
        val loop = AgentPlannerToolLoopRequest.create(request(), AgentModelPlannerSettings(noProgressTimeoutSeconds = 90),
            messages, emptyList(), eventSink = sink)
        assertSame(sink, loop.eventSink)
        assertEquals(messages, loop.messages)
        assertFalse(loop.budget.enforceCountLimits)
        assertEquals(90_000L, loop.budget.maxDurationMillis)
    }

    private fun create(request: AgentRequest) = AgentPlannerToolLoopRequest.create(request,
        AgentModelPlannerSettings(), listOf(AgentModelMessage.user("Continue")), emptyList())

    private fun request(conversation: String = "conversation", turn: String = "turn", session: String = "session"): AgentRequest {
        val screen = ScreenContext("Test", pageTitle = "Test")
        return AgentRequest("Continue", screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = session, goal = "Continue", screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList(), nativeTools = emptyList()),
            conversationContext = AgentConversationContext(conversation, "", emptyList(), false), executionTurnId = turn)
    }
}
