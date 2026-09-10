package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentDagWaitingDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val screen = ScreenContext("Test", pageTitle = "DAG waiting")

    @Test fun remoteDependencyWaitSurvivesEncryptedReopenWithoutBlocking() = isolated { name, store, agent ->
        val upstream = action("upstream", AgentActionStatus.WAITING_RESPONSE)
        val downstream = action("downstream", AgentActionStatus.PROPOSED, "upstream")
        val plan = AgentPlan("Wait for the upstream observation", screen, emptyList(),
            listOf(upstream, downstream), planId = name, confirmationRequired = false)
        agent.currentPlan = plan
        agent.lastActionResult = AgentActionResult("upstream", true, "Awaiting remote reply",
            mapOf("awaiting_response" to "true"))
        assertTrue(plan.runnableActions().isEmpty())
        val state = agent.noRunnableActionState(plan)
        assertEquals(AgentPhase.WAITING_RESPONSE, state.phase)
        assertEquals("upstream", agent.lastActionResult!!.actionId)
        val restored = requireNotNull(SharedPreferencesAgentSessionStore(context, name).load())
        assertEquals(AgentPhase.WAITING_RESPONSE, restored.phase)
        assertEquals(plan.actions, restored.currentPlan!!.actions)
        assertTrue(restored.currentPlan.runnableActions().isEmpty())
        val observed = restored.currentPlan.copy(actions = listOf(
            upstream.copy(status = AgentActionStatus.COMPLETED), downstream))
        assertEquals(listOf("downstream"), observed.runnableActions().map { it.id })
        assertEquals(AgentPhase.WAITING_RESPONSE, store.load()!!.phase)
    }

    @Test fun runningDependencyRemainsExecutingRatherThanBlocked() = isolated { name, _, agent ->
        val plan = AgentPlan("Wait for the running action", screen, emptyList(), listOf(
            action("upstream", AgentActionStatus.RUNNING),
            action("downstream", AgentActionStatus.PROPOSED, "upstream")),
            planId = name, confirmationRequired = false)
        agent.currentPlan = plan
        assertEquals(AgentPhase.EXECUTING, agent.noRunnableActionState(plan).phase)
        assertEquals(plan.actions, agent.currentPlan!!.actions)
    }

    @Test fun missingDependencyWithoutAnOwnerIsStillBlocked() = isolated { name, _, agent ->
        val plan = AgentPlan("Invalid graph fixture", screen, emptyList(),
            listOf(action("downstream", AgentActionStatus.PROPOSED, "missing")),
            planId = name, confirmationRequired = false)
        agent.currentPlan = plan
        assertEquals(AgentPhase.BLOCKED, agent.noRunnableActionState(plan).phase)
        assertEquals("agent-tool-graph-blocked", agent.lastActionResult!!.actionId)
    }

    @Test fun normalDispatchKeepsWaitingAndDoesNotInvokeTheExecutor() = isolated { name, _, agent ->
        val plan = AgentPlan("Wait through normal dispatch", screen, emptyList(), listOf(
            action("upstream", AgentActionStatus.WAITING_RESPONSE),
            action("downstream", AgentActionStatus.PROPOSED, "upstream")),
            planId = name, confirmationRequired = false)
        agent.currentPlan = plan
        assertEquals(AgentPhase.WAITING_RESPONSE, agent.executeFirstPendingAction().phase)
        assertEquals(plan.actions.map { it.status }, agent.currentPlan!!.actions.map { it.status })
    }

    @Test fun aSingleWaitingNodeDoesNotRemainInPlanning() = isolated { name, _, agent ->
        val plan = AgentPlan("Wait for the only node", screen, emptyList(),
            listOf(action("upstream", AgentActionStatus.WAITING_RESPONSE)),
            planId = name, confirmationRequired = false)
        agent.currentPlan = plan
        assertEquals(AgentPhase.WAITING_RESPONSE, agent.noRunnableActionState(plan).phase)
    }

    private fun action(id: String, status: AgentActionStatus, dependency: String = "") = AgentAction(
        id, AgentActionKind.CALL_NATIVE_TOOL, AgentHardwareNativeTools.MEMORY_STATUS,
        AgentRisk.LOW, status, "Observe test node",
        mapOf("tool_id" to AgentHardwareNativeTools.MEMORY_STATUS, "input_json" to "{}",
            "depends_on" to dependency), requiresConfirmation = false)

    private fun isolated(block: (String, AgentSessionStore, MobileNativeAgent) -> Unit) {
        val name = "test-dag-waiting-${UUID.randomUUID()}"
        val store = SharedPreferencesAgentSessionStore(context, name)
        val agent = MobileNativeAgent(context, sessionStore = store,
            memoryStore = InMemoryAgentMemoryStore(), screenObservationOverride = false,
            safetyPolicy = UnrestrictedAgentSafetyPolicy(),
            perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            }, connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = emptyList<AgentCallableTarget>()
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult =
                    error("Waiting must never dispatch an executor")
            })
        try {
            agent.sessionId = name
            agent.currentGoal = "Wait for the existing task, without resubmitting"
            agent.phase = AgentPhase.PLANNING
            block(name, store, agent)
        } finally { store.clear() }
    }
}
