package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real MobileNativeAgent lifecycle with an injected provider, never a live user request. */
@RunWith(AndroidJUnit4::class)
class AgentConnectorFallbackRuntimeDeviceTest {
    @Test fun immediateSuccessIsObservedAndCompleted() {
        val state = exercise(success = true, awaiting = false)
        assertEquals(AgentPhase.COMPLETED, state.phase)
        assertEquals("test-success", state.lastActionResult?.message)
        assertEquals(AgentActionStatus.COMPLETED, state.plan?.actions?.single()?.status)
    }

    @Test fun asynchronousDispatchIsPersistedOnTheSelectedAgent() {
        val state = exercise(success = true, awaiting = true)
        assertEquals(AgentPhase.WAITING_RESPONSE, state.phase)
        assertEquals("test-codex", state.plan?.actions?.single()?.parameters?.get("connector_id"))
        assertEquals("902", state.lastActionResult?.metadata?.get("source_message_id"))
        assertEquals("Codex test", state.plan?.selectedAgentOrModel)
    }

    @Test fun immediateFailureRetainsTheActualFallbackError() {
        val state = exercise(success = false, awaiting = false)
        assertEquals(AgentPhase.FAILED, state.phase)
        assertEquals("test-permanent-error", state.lastActionResult?.message)
    }

    private fun exercise(success: Boolean, awaiting: Boolean): AgentUiState {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent")
        val session = InMemoryAgentSessionStore()
        val records = linkedMapOf<String, AgentTaskRecord>()
        val target = AgentCallableTarget("test-codex", "Codex test", AgentConnectorKind.AGENT,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT), "test-desktop", adapterType = "desktop-agent")
        var dispatches = 0
        val agent = MobileNativeAgent(
            context,
            perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            },
            planner = object : AgentPlanner {
                override fun plan(request: AgentRequest): AgentPlan = error("Unexpected replan")
            },
            actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    dispatches++
                    assertEquals("test-codex", action.parameters["connector_id"])
                    assertEquals("desktop-agent", action.parameters["connector_adapter_type"])
                    assertEquals("test-codex", session.load()?.currentPlan?.actions?.single()?.parameters?.get("connector_id"))
                    return AgentActionResult(action.id, success, if (success) "test-success" else "test-permanent-error",
                        AgentConnectorFallbackAction.resultMetadata(action) + mapOf(
                            "awaiting_response" to awaiting.toString(), "non_retriable" to (!success).toString(),
                            "source_message_id" to "902", "contact_id" to "test-codex", "resource_id" to "test-codex"
                        ))
                }
            },
            memoryStore = InMemoryAgentMemoryStore(),
            taskStore = object : AgentTaskStore {
                override fun upsert(record: AgentTaskRecord) { records[record.taskId] = record }
                override fun recent(limit: Int) = records.values.take(limit)
                override fun forSession(sessionId: String, limit: Int) = recent(limit).filter { it.sessionId == sessionId }
                override fun find(taskId: String) = records[taskId]
                override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
                override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
                override fun delete(taskIds: Set<String>) { taskIds.forEach(records::remove) }
                override fun clear() { records.clear() }
            },
            connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = listOf(target)
            },
            sessionStore = session,
            screenObservationOverride = false
        )
        val action = AgentAction("test-dispatch", AgentActionKind.CALL_CONNECTOR, "Hermes test", AgentRisk.LOW,
            AgentActionStatus.WAITING_RESPONSE, "Test reply", mapOf("connector_id" to "test-hermes", "prompt" to "Test reply"),
            requiresConfirmation = false)
        val plan = AgentPlan("Test reply", screen, emptyList(), listOf(action), confirmationRequired = false)
        agent.currentGoal = "Test reply"
        agent.currentPlan = plan
        agent.phase = AgentPhase.WAITING_RESPONSE
        val state = requireNotNull(agent.continueWithConnectorFallback(plan, AgentActionResult(
            action.id, false, "test-old-failure", mapOf("resource_id" to "test-hermes",
                "remaining_fallback_ids" to "test-codex", "timeout_stage" to "NOT_RUNNING",
                "failure_domain" to "test-desktop", "awaiting_response" to "false")
        )))
        assertEquals(1, dispatches)
        assertEquals(state.phase, session.load()?.phase)
        return state
    }
}
