package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentSupervisorFailureDeviceTest {
    @Test fun actualReplanningBoundaryHonorsNonRetriableProviderFailure() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val id = "supervisor-failure-${UUID.randomUUID()}"
        val screen = ScreenContext("Fixture", pageTitle = "Recovery")
        val action = AgentAction("failed-provider", AgentActionKind.CALL_CONNECTOR, "DeepSeek", AgentRisk.LOW,
            AgentActionStatus.FAILED, "Reason", parameters = mapOf(
                "connector_id" to "reasoning-provider-unavailable", "manual_target_locked" to "true",
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                INTERNAL_CONVERSATION_ID to id, INTERNAL_TURN_ID to id))
        val plan = AgentPlan("Public lookup", screen, emptyList(), listOf(action),
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE)
        val agent = MobileNativeAgent(context, sessionStore = InMemoryAgentSessionStore(),
            memoryStore = InMemoryAgentMemoryStore(), screenObservationOverride = false,
            connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets(): List<AgentCallableTarget> = error("Must stop before routing")
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult =
                    error("Unavailable provider must not be redispatched")
            }).apply {
                sessionId = id
                currentGoal = plan.goal
                currentScreen = screen
                currentPlan = plan
                activeConversationContext = AgentConversationContext(id, "", emptyList(), true)
                activeConversationTurnId = id
                lastActionResult = AgentActionResult(action.id, false, "No provider is available",
                    mapOf("non_retriable" to "true"))
            }
        assertNull(agent.replanFromCurrentState(plan, PHONE_SUPERVISED_PROJECT_REPLAN_REASON))
        assertEquals("No provider is available", agent.lastActionResult?.message)
    }
}
