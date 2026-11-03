package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Public failure fixtures, without real goals, providers, browser operations or downloads. */
@RunWith(AndroidJUnit4::class)
class AgentNativeActionObservationDeviceTest {
    @Test fun missingDependencyReachesSupervisingProviderWithoutFrameworkRetry() = exercise("dependency_missing", true)
    @Test fun pageFailureReachesSupervisingProviderWithoutGenericErrorReplacement() = exercise("element_not_found", false)
    @Test fun uncertainOutcomeReachesSupervisingProviderWithoutReplayingMutation() = exercise("operation_outcome_unknown", false)

    private fun exercise(code: String, retryable: Boolean) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val id = UUID.randomUUID().toString()
        val conversation = "public-native-failure-conversation-$id"
        val turn = "public-native-failure-turn-$id"
        val screen = ScreenContext("Public fixture", pageTitle = "公开失败观察测试")
        val sessionStore = SharedPreferencesAgentSessionStore(context, "public-native-failure-$id")
        val action = AgentAction("public-failure-$id", AgentActionKind.CALL_NATIVE_TOOL, "Public inspection",
            AgentRisk.LOW, AgentActionStatus.PENDING_CONFIRMATION, "公开框架测试：观察工具错误", mapOf(
                "tool_id" to "public.failure_fixture", "input_json" to "{}",
                INTERNAL_CONVERSATION_ID to conversation, INTERNAL_TURN_ID to turn))
        val connector = AgentAction("public-provider-$id", AgentActionKind.CALL_CONNECTOR, "Public provider fixture",
            AgentRisk.LOW, AgentActionStatus.COMPLETED, "Public reasoning fixture", mapOf(
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, "connector_id" to "public-fixture",
                "model" to "public-configured-model", "reasoning_effort" to "high"))
        val plan = AgentPlan("公开框架测试：工具失败后观察原因并重新决策", screen, emptyList(), listOf(action),
            planId = "public-plan-$id", plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            actionHistory = listOf(connector))
        var toolCalls = 0
        var providerCalls = 0
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(AgentNativeToolDescriptor(
            "public.failure_fixture", "1.0.0", "Public fixture", "Public fixture", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW),
            AgentNativeToolExecutor {
                toolCalls++
                AgentNativeToolExecutionResult.failure(code, "公开诊断：当前操作需要重新观察", retryable,
                    mapOf("component" to "public-browser", "path" to "/public/fixture", "password" to "public-fixture-secret",
                        "outcome_unknown" to (code == "operation_outcome_unknown")))
            }))
        val rows = mutableMapOf<String, AgentTaskRecord>()
        val tasks = object : AgentTaskStore {
            override fun upsert(record: AgentTaskRecord) { rows[record.taskId] = record }
            override fun recent(limit: Int) = rows.values.take(limit)
            override fun forSession(sessionId: String, limit: Int) = rows.values.filter { it.sessionId == sessionId }.take(limit)
            override fun find(taskId: String) = rows[taskId]
            override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
            override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
            override fun delete(taskIds: Set<String>) { taskIds.forEach(rows::remove) }
            override fun clear() { rows.clear() }
        }
        val settings = object : AgentSafetySettingsStore {
            private var value = AgentSafetySettings(memoryCapture = false, screenObservationAllowed = false)
            override fun load() = value
            override fun save(settings: AgentSafetySettings) { value = settings }
        }
        fun runtime() = MobileNativeAgent(context, sessionStore = sessionStore, taskStore = tasks,
            safetySettingsStore = settings, memoryStore = InMemoryAgentMemoryStore(), nativeToolRegistryProvider = { registry },
            connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = listOf(AgentCallableTarget("public-fixture", "Public provider fixture",
                    AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE,
                    listOf(AgentCapability.CHAT, AgentCapability.REASONING)))
            }, perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    assertTrue(action.isSupervisedProjectConnector())
                    val prompt = action.parameters.getValue("prompt")
                    assertTrue("Missing error code $code", prompt.contains(code))
                    assertTrue(prompt.contains("public-browser"))
                    assertTrue("Observed path missing from prompt", prompt.replace("\\/", "/").contains("/public/fixture"))
                    assertFalse(prompt.contains("public-fixture-secret"))
                    if (code == "operation_outcome_unknown") assertTrue(prompt.contains("outcome is unknown"))
                    assertEquals("public-configured-model", action.parameters["model"])
                    providerCalls++
                    return AgentActionResult(action.id, true, "Public reasoning fixture accepted", mapOf("awaiting_response" to "true"))
                }
            }).also {
                it.activeConversationContext = AgentConversationContext(conversation, "", emptyList(), true)
                it.activeConversationTurnId = turn
                it.activeRunRuntimeContext = AgentRuntimeContextBuilder.build("public-session-$id", plan.goal, screen,
                    PermissionMode.FULL_ACCESS, false, false, emptyList(), emptyList(), nativeTools = registry.descriptors())
            }
        try {
            val first = runtime().also {
                it.sessionId = "public-session-$id"
                it.currentGoal = plan.goal
                it.currentScreen = screen
                it.currentPlan = plan
                it.phase = AgentPhase.PLANNING
                it.executionLoop.start(turn, AgentExecutionLoopBudget())
                it.persistSession()
            }
            assertEquals(AgentPhase.WAITING_RESPONSE, first.executeFirstPendingAction().phase)
            assertEquals(1, toolCalls)
            assertEquals(1, providerCalls)
            val reopened = runtime()
            val failed = requireNotNull(reopened.currentPlan).actionHistory.single { it.id == action.id }
            assertEquals(AgentActionStatus.FAILED, failed.status)
            assertTrue(failed.evidence.contains(code))
            assertFalse(failed.evidence.contains("public-fixture-secret"))
            assertEquals(AgentPhase.WAITING_RESPONSE, reopened.resumeCurrentTask().phase)
            assertEquals(1, toolCalls)
            assertEquals(1, providerCalls)
            println("PUBLIC_NATIVE_FAILURE code=$code tool_calls=$toolCalls provider_calls=$providerCalls persisted=true")
        } finally {
            sessionStore.clear()
        }
    }
}
