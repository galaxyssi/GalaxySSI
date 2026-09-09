package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentContinuousReplanningDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val screen = ScreenContext("Test", pageTitle = "Test")
    private val enabled = AgentModelPlannerSettings(enabled = true, dynamicReplanning = true, maxReplans = 1)

    @Test fun ordinaryFailuresKeepReplanningAcrossEncryptedReopen() = continuous("guarded-model:test", 64)

    @Test fun specializedRecoveryHasNoEightRevisionLifetimeLimit() = continuous("specialized-adapter:test", 24)

    private fun continuous(profile: String, count: Int) = isolated { name, sessions ->
        var assessments = 0
        val planner = object : AgentPlanner {
            override fun plan(request: AgentRequest): AgentPlan {
                assessments++
                assertEquals(name, request.conversationContext.conversationId)
                assertEquals("turn-$name", request.executionTurnId)
                assertTrue(request.executionHistory.any { it.status == AgentActionStatus.FAILED })
                val prompt = AgentModelPlanningPrompt.build(request, enabled,
                    AgentTaskRequirementAnalyzer.analyze(request.goal))
                assertTrue(prompt.contains("fixture_failure"))
                return plan(name, profile).copy(actions = listOf(action(name, "next")))
            }
        }
        var agent = runtime(sessions, planner)
        agent.sessionId = name
        agent.currentGoal = "\u6839\u636e\u89c2\u5bdf\u5230\u7684\u9519\u8bef\u7ee7\u7eed\u4fee\u6539\u8ba1\u5212"
        agent.currentPlan = plan(name, profile).copy(replanCount = 8_192, revision = 8_193)
        agent.phase = AgentPhase.PLANNING
        repeat(count) { index ->
            val current = requireNotNull(agent.currentPlan)
            val failed = current.markAction(current.actions.single().id, AgentActionStatus.FAILED,
                AgentActionResult(current.actions.single().id, false, "fixture_failure_$index",
                    metadata = mapOf("native_tool_output" to "{\"error\":\"fixture_failure_$index\"}")))
            val next = agent.replanFromCurrentState(failed, "action_failed", settings = enabled)
            assertNotNull("Lifetime count must not prevent observation $index", next)
            assertEquals(current.replanCount + 1, next!!.replanCount)
            assertEquals(current.planId, next.planId)
            assertEquals(name, next.actions.single().parameters[INTERNAL_CONVERSATION_ID])
            assertEquals("turn-$name", next.actions.single().parameters[INTERNAL_TURN_ID])
            agent.currentPlan = next
            agent.persistSession()
            if (index % 8 == 7) {
                agent = runtime(SharedPreferencesAgentSessionStore(context, name), planner)
                assertEquals(next.replanCount, requireNotNull(agent.currentPlan).replanCount)
            }
        }
        assertEquals(count, assessments)
        assertEquals(8_192 + count, requireNotNull(agent.currentPlan).replanCount)
    }

    @Test fun phoneRepairStillReachesThePlannerAfterTwoFailures() = isolated { name, sessions ->
        var observed = false
        val agent = runtime(sessions, object : AgentPlanner {
            override fun plan(request: AgentRequest): AgentPlan {
                observed = true
                assertEquals(PHONE_DEVELOPMENT_REPLAN_REASON, request.replanReason)
                return plan(name, PHONE_DEVELOPMENT_PLANNER_PROFILE)
            }
        })
        val source = plan(name, PHONE_DEVELOPMENT_PLANNER_PROFILE).copy(replanCount = 200,
            actions = listOf(action(name, "repair").copy(parameters = action(name, "repair").parameters + mapOf(
                "tool_id" to AgentOnDeviceRuntimeTools.EXECUTE, PHONE_DEVELOPMENT_MANIFEST_PARAMETER to "true"))))
        assertNotNull(agent.replanFromCurrentState(source, PHONE_DEVELOPMENT_REPLAN_REASON,
            settings = AgentModelPlannerSettings()))
        assertTrue(observed)
    }

    @Test fun disablingDynamicReplanningStillPreventsAutomaticModelCalls() = isolated { name, sessions ->
        val agent = runtime(sessions, object : AgentPlanner {
            override fun plan(request: AgentRequest): AgentPlan = error("Disabled planner must not be called")
        })
        val source = plan(name, "guarded-model:test").copy(replanCount = 8_192)
        assertNull(agent.replanFromCurrentState(source, "action_failed", settings = enabled.copy(enabled = false)))
        assertNull(agent.replanFromCurrentState(source, "action_failed", settings = enabled.copy(dynamicReplanning = false)))
    }

    @Test fun conflictingConversationStillPreventsModelDisclosure() = isolated { name, sessions ->
        val agent = runtime(sessions, object : AgentPlanner {
            override fun plan(request: AgentRequest): AgentPlan = error("Conflicting scope must not reach model")
        })
        agent.activeConversationContext = AgentConversationContext("other", "", emptyList(), false)
        assertNull(agent.replanFromCurrentState(plan(name, "guarded-model:test"), "action_failed", settings = enabled))
    }

    private fun action(name: String, id: String) = AgentAction(id, AgentActionKind.CALL_NATIVE_TOOL,
        AgentHardwareNativeTools.MEMORY_STATUS, AgentRisk.LOW, AgentActionStatus.PROPOSED, "Read memory",
        mapOf("tool_id" to AgentHardwareNativeTools.MEMORY_STATUS, "input_json" to "{}",
            INTERNAL_CONVERSATION_ID to name, INTERNAL_TURN_ID to "turn-$name"), requiresConfirmation = false)

    private fun plan(name: String, profile: String) = AgentPlan("Review observed failure", screen, emptyList(),
        listOf(action(name, "first")), planId = name, confirmationRequired = false, plannerProfile = profile)

    private fun runtime(sessions: AgentSessionStore, planner: AgentPlanner) = MobileNativeAgent(context,
        sessionStore = sessions, planner = planner, memoryStore = InMemoryAgentMemoryStore(),
        screenObservationOverride = false, safetyPolicy = UnrestrictedAgentSafetyPolicy(),
        perceptionProvider = object : ScreenPerceptionProvider {
            override fun capture() = screen
            override fun capture(foregroundApp: String, pageTitle: String) = screen
        },
        connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
        actionExecutor = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult = error("Admission test must not execute effects")
        })

    private fun isolated(block: (String, AgentSessionStore) -> Unit) {
        val name = "test-continuous-replanning-${UUID.randomUUID()}"
        val sessions = SharedPreferencesAgentSessionStore(context, name)
        try { block(name, sessions) } finally { sessions.clear() }
    }
}
