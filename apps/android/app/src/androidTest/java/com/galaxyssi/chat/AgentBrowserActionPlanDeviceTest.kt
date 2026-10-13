package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.util.AtomicFile
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated dispatch fixture; does not submit a user goal, call a provider, log in or open a website. */
@RunWith(AndroidJUnit4::class)
class AgentBrowserActionPlanDeviceTest {
    @Test fun nativePlanWaitsAndReopensThenAsksOriginalProviderWithoutReplayingBrowserAction() {
        exercise(interrupted = false, receiptPersisted = true)
    }

    @Test fun interruptionBeforeNativeReceiptStillBecomesAnObservationNotARepeatedBrowserMutation() {
        exercise(interrupted = true, receiptPersisted = false)
    }

    @Test fun receiptCommittedBeforeWaitingStateCanResumeWithoutRepeatingTheHandoff() {
        exercise(interrupted = false, receiptPersisted = true, pauseAfterReceipt = false)
    }

    @Test fun persistedContinuationBeforeHostMarkerIsReusedInsteadOfAppendedAgain() {
        exercise(interrupted = false, receiptPersisted = true, continuationBeforeMarker = true)
    }

    private fun exercise(interrupted: Boolean, receiptPersisted: Boolean, pauseAfterReceipt: Boolean = true,
        continuationBeforeMarker: Boolean = false) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val id = UUID.randomUUID().toString()
        val sessionId = "public-action-plan-session-$id"
        val conversation = "public-action-plan-conversation-$id"
        val turn = "public-action-plan-turn-$id"
        val screen = ScreenContext("Public fixture", pageTitle = "公开框架测试")
        val handoff = AgentAction("public-handoff-$id", AgentActionKind.CALL_NATIVE_TOOL, "Public browser",
            AgentRisk.LOW, AgentActionStatus.RUNNING, "公开框架测试：等待用户归还浏览器控制", mapOf(
                "tool_id" to AgentInteractiveBrowserTools.ACT, "input_json" to
                    """{"operation":"request_user_control","session_id":"public-browser","page_id":"public-page"}""",
                INTERNAL_CONVERSATION_ID to conversation, INTERNAL_TURN_ID to turn))
        val connector = AgentAction("public-provider-$id", AgentActionKind.CALL_CONNECTOR, "Public provider fixture",
            AgentRisk.LOW, AgentActionStatus.COMPLETED, "Public reasoning fixture", mapOf(
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, "connector_id" to "public-fixture",
                "manual_target_locked" to "true", "model" to "public-configured-model", "reasoning_effort" to "high"))
        val plan = AgentPlan("公开框架测试：等待浏览器事件后继续观察", screen, emptyList(), listOf(handoff),
            planId = "public-plan-$id", plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE,
            actionHistory = listOf(connector)).addCheckpoint(AgentExecutionContinuity.checkpointBefore(handoff, screen, 1))
        val sessionStore = SharedPreferencesAgentSessionStore(context, "public-browser-action-plan-$id")
        val requests = AgentBrowserUserRequestStore(context)
        val key = requireNotNull(AgentPlanNodeKey.from(sessionId, plan, handoff))
        val toolContext = AgentNativeToolInvocationContext(sessionId = sessionId, conversationId = conversation, turnId = turn,
            callerId = AgentBrowserActionPlanPolicy.CALLER, attributes = mapOf("task_id" to turn,
                "workspace_id" to AgentWorkspaceScope.id(conversation, sessionId)))
        val scope = AgentInteractiveBrowserTools.scope(toolContext)
        val attributes = AgentBrowserActionPlanPolicy.attributes(sessionId, plan, handoff)
        val record = AgentBrowserUserRequest(AgentBrowserUserRequest.key(scope, "public-browser"), id, scope,
            sessionId, conversation, turn, toolContext.callerId, toolContext.attributes.getValue("workspace_id"),
            "public-browser", "public-page", "public-handoff", "active", taskId = turn,
            runWorkspaceId = "public-run-$id", runSessionId = "public-owner-$id", hostProcessId = AgentProcessIdentity.instanceId,
            actionPlanId = plan.planId, actionPlanRevision = plan.revision, actionId = handoff.id,
            actionPlanBinding = attributes.getValue("action_plan_binding"))
        var toolCalls = 0
        var providerCalls = 0
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(AgentNativeToolDescriptor(
            AgentInteractiveBrowserTools.ACT, "1.0.0", "Public fixture", "Public fixture", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW),
            AgentNativeToolExecutor {
                toolCalls++
                assertEquals(turn, it.context.attributes["task_id"])
                assertNotEquals(plan.planId, it.context.attributes["task_id"])
                assertEquals(record.actionPlanBinding, it.context.attributes["action_plan_binding"])
                AgentNativeToolExecutionResult.success(mapOf("durable_resume_available" to true,
                    "host_wait_key" to record.key, "host_wait_generation" to record.generation))
            }))
        val taskStore = object : AgentTaskStore {
            private val rows = mutableMapOf<String, AgentTaskRecord>()
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
        fun runtime() = MobileNativeAgent(context, sessionStore = sessionStore, taskStore = taskStore,
            safetySettingsStore = settings, memoryStore = InMemoryAgentMemoryStore(),
            nativeToolRegistryProvider = { registry }, connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = listOf(AgentCallableTarget("public-fixture", "Public provider fixture",
                    AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE,
                    listOf(AgentCapability.CHAT, AgentCapability.REASONING)))
            }, perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    assertTrue(action.isSupervisedProjectConnector())
                    assertEquals("public-configured-model", action.parameters["model"])
                    assertEquals("high", action.parameters["reasoning_effort"])
                    val prompt = action.parameters["prompt"].orEmpty()
                    assertTrue(prompt.contains(if (interrupted) "browser_control_interrupted" else "browser_control_returned"))
                    assertTrue(prompt.contains("authentication_verified"))
                    providerCalls++
                    return AgentActionResult(action.id, true, "Public reasoning fixture accepted", mapOf("awaiting_response" to "true"))
                }
            }).also {
                it.activeConversationContext = AgentConversationContext(conversation, "", emptyList(), true)
                it.activeConversationTurnId = turn
                it.activeRunRuntimeContext = AgentRuntimeContextBuilder.build(sessionId, plan.goal, screen,
                    PermissionMode.FULL_ACCESS, false, false, emptyList(), emptyList(), nativeTools = registry.descriptors())
            }
        try {
            val first = runtime().also {
                it.sessionId = sessionId
                it.currentGoal = plan.goal
                it.currentScreen = screen
                it.currentPlan = plan
                it.phase = AgentPhase.EXECUTING
                it.executionLoop.start(turn, AgentExecutionLoopBudget())
                it.executionLoop.transition(AgentExecutionLoopPhase.ACT, "Public native dispatch fixture", handoff.id)
                it.persistSession()
            }
            requests.save(record)
            val receipt = if (receiptPersisted) first.executeJournaledPlanAction(key) {
                first.executeAction(handoff, screen, userConfirmed = true)
            } else null
            if (receipt != null && pauseAfterReceipt) {
                first.lastActionResult = receipt
                assertTrue(first.waitForBrowserAction(handoff, receipt))
                assertEquals(AgentPhase.PAUSED, first.phase)
                repeat(3) {
                    assertEquals(AgentPhase.PAUSED, runtime().resumeCurrentTask().phase)
                    assertEquals(0, providerCalls)
                }
            }
            val settled = if (interrupted) record.copy(state = "interrupted", interruptionCode = "browser_host_restarted")
                else record.copy(state = "returned")
            requests.save(settled)
            if (continuationBeforeMarker) {
                val preparing = runtime()
                val savedPlan = requireNotNull(preparing.currentPlan)
                val observed = AgentBrowserActionPlanPolicy.observe(settled, savedPlan.actions.single())
                preparing.currentPlan = AgentBrowserActionPlanPolicy.continuation(savedPlan, settled, observed,
                    preparing.supervisedProjectRequest(savedPlan, continuation = true))
                preparing.phase = AgentPhase.PAUSED
                preparing.lastActionResult = AgentActionResult("agent-browser-event", true, observed.result)
                preparing.persistSession()
                assertFalse(requests.current(record.key, record.generation).modelObservationCommitted)
            }
            val reopened = runtime()
            reopened.activeConversationContext = AgentConversationContext("", "", emptyList(), false)
            reopened.activeConversationTurnId = ""
            val resumedPhases = mutableListOf<AgentExecutionLoopPhase>()
            reopened.bindExecutionLoopEventSink(AgentExecutionLoopEventSink { resumedPhases += it.phase })
            assertEquals(AgentPhase.WAITING_RESPONSE, reopened.resumeBrowserActionPlan(settled).phase)
            assertTrue(resumedPhases.indexOf(AgentExecutionLoopPhase.OBSERVE) >= 0)
            assertTrue(resumedPhases.indexOf(AgentExecutionLoopPhase.OBSERVE) < resumedPhases.indexOf(AgentExecutionLoopPhase.REPLAN))
            assertEquals(conversation, reopened.activeConversationContext.conversationId)
            assertEquals(turn, reopened.activeConversationTurnId)
            assertTrue(reopened.activeConversationContext.privateMode)
            assertEquals(1, providerCalls)
            assertEquals(2, reopened.currentPlan!!.revision)
            assertEquals(if (receiptPersisted) 1 else 0, toolCalls)
            assertTrue(requests.current(record.key, record.generation).modelObservationCommitted)
            if (receipt != null) assertEquals(receipt, first.planNodeJournal.read(key)?.result)
            val committedPhaseCount = resumedPhases.size
            assertEquals(AgentPhase.WAITING_RESPONSE, reopened.resumeBrowserActionPlan(settled).phase)
            assertEquals(1, providerCalls)
            assertEquals(committedPhaseCount, resumedPhases.size)
            assertTrue(requests.acknowledgeObservedRunWake(settled))
            println("PUBLIC_BROWSER_ACTION_PLAN interrupted=$interrupted receipt_persisted=$receiptPersisted pause_after_receipt=$pauseAfterReceipt continuation_before_marker=$continuationBeforeMarker provider_calls=$providerCalls tool_calls=$toolCalls")
        } finally {
            sessionStore.clear()
            AtomicFile(File(context.filesDir, "browser-user-requests/${record.key}.enc")).delete()
        }
    }
}
