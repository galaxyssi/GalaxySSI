package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class CloudSupervisedControlDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun providerMarkupRepairsThenExecutesOnPhoneBeforePublishingAnAnswer() {
        val scope = "control-loop-${UUID.randomUUID()}"
        val goal = "\u4ecb\u7ecd\u4e00\u4e0b\u73e0\u6d77\u5cad\u5357\u4e16\u5bb6\u8fd9\u4e2a\u5c0f\u533a"
        val screen = ScreenContext("Fixture", pageTitle = "Control loop")
        val toolId = AgentWebIntelligenceNativeTools.SEARCH
        var executions = 0
        val descriptor = AgentNativeToolDescriptor(toolId, "1.0.0", "Search", "Fixture search",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(),
            AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY,
            effect = AgentNativeToolEffect.READ_ONLY)
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor,
            AgentNativeToolExecutor { invocation ->
                executions++
                assertEquals(scope, invocation.context.conversationId)
                assertEquals(scope, invocation.context.turnId)
                assertEquals(goal, invocation.input["query"])
                AgentNativeToolExecutionResult.success(mapOf("results" to listOf(mapOf(
                    "title" to "PUBLIC_FIXTURE_EVIDENCE", "url" to "https://example.com/source"))))
            }))
        val target = AgentCallableTarget("fixture-cloud", "Fixture cloud", AgentConnectorKind.MODEL,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT, AgentCapability.REASONING))
        val agent = MobileNativeAgent(context, sessionStore = InMemoryAgentSessionStore(),
            memoryStore = InMemoryAgentMemoryStore(), screenObservationOverride = false,
            nativeToolRegistryProvider = { registry }, connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = listOf(target)
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult =
                    error("The test must not dispatch to Desktop or a real provider")
            }).apply {
                sessionId = scope
                currentGoal = goal
                currentScreen = screen
                activeConversationContext = AgentConversationContext(scope, "", emptyList(), true)
                activeConversationTurnId = scope
                activeRunRuntimeContext = AgentRuntimeContextBuilder.build(scope, goal, screen,
                    PermissionMode.FULL_ACCESS, false, false, listOf(target), emptyList(), nativeTools = listOf(descriptor))
            }
        val connector = AgentAction("provider", AgentActionKind.CALL_CONNECTOR, target.title,
            AgentRisk.LOW, AgentActionStatus.COMPLETED, "Reason", parameters = mapOf(
                "connector_id" to target.id, "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                "supervised_iteration" to "0", "manual_target_locked" to "true", "model" to "fixture-model",
                INTERNAL_CONVERSATION_ID to scope, INTERNAL_TURN_ID to scope))
        val plan = AgentPlan(goal, screen, emptyList(), listOf(connector),
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE)
        val raw = "<\uFF5C\uFF5CDSML\uFF5C\uFF5C calls><\uFF5C\uFF5CDSML\uFF5C\uFF5C invoke name=\"$toolId\">" +
            "<\uFF5C\uFF5CDSML\uFF5C\uFF5C parameter name=\"query\" string=\"true\">$goal" +
            "</\uFF5C\uFF5CDSML\uFF5C\uFF5C parameter></\uFF5C\uFF5CDSML\uFF5C\uFF5C invoke></\uFF5C\uFF5CDSML\uFF5C\uFF5C calls>"
        val received = stream(raw, supervised = true).filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text }
        val repair = agent.acceptSupervisedProjectPlan(plan, connector, received)
        assertEquals(AgentSupervisedProjectPlanDisposition.REPAIR, repair.disposition)
        assertFalse(repair.semanticallyAccepted)
        assertEquals("", repair.finalResponse)
        assertEquals("", AgentSupervisedProjectControlPayload.visibleModelOutput(received))
        assertEquals(0, executions)
        val repairPlan = requireNotNull(repair.plan)
        val retry = repairPlan.actions.single()
        assertEquals("true", retry.parameters["manual_target_locked"])
        assertEquals(target.id, retry.parameters["connector_id"])
        assertEquals("fixture-model", retry.parameters["model"])
        assertTrue(retry.parameters["prompt"].orEmpty().contains("No tool in that response has run"))
        assertEquals(AgentSupervisedProjectPlanDisposition.REPAIR,
            agent.acceptSupervisedProjectPlan(repairPlan, retry, "Already searched and finished").disposition)

        val fixed = JSONObject().put("execution_location", "phone").put("summary", "\u5148\u67e5\u8be2\u6765\u6e90")
            .put("completion_requirements", JSONObject().put("publication", "none").put("phone_linux", false))
            .put("actions", JSONArray().put(JSONObject().put("kind", "CALL_NATIVE_TOOL").put("target", toolId)
                .put("description", "Search source").put("parameters", JSONObject().put("tool_id", toolId)
                    .put("arguments", JSONObject().put("query", goal)))))
        val accepted = agent.acceptSupervisedProjectPlan(repairPlan, retry, fixed.toString())
        assertEquals(AgentSupervisedProjectPlanDisposition.EXECUTABLE, accepted.disposition)
        val executable = requireNotNull(accepted.plan)
        agent.currentPlan = executable
        val native = executable.actions.first { it.kind == AgentActionKind.CALL_NATIVE_TOOL }
        val receipt = agent.executeAction(native, screen, userConfirmed = true)
        assertTrue(receipt.message, receipt.success)
        assertEquals(1, executions)
        val observed = native.copy(status = AgentActionStatus.COMPLETED, result = receipt.message,
            evidence = receipt.metadata["native_tool_output"].orEmpty())
        val observedPlan = executable.copy(actions = executable.actions.map { if (it.id == native.id) observed else it })
        val reviewer = observedPlan.actions.last { it.isSupervisedProjectConnector() }
        val request = agent.supervisedProjectRequest(observedPlan, continuation = true)
        assertTrue(AgentSupervisedProjectLoop.continuationPrompt(request).contains("PUBLIC_FIXTURE_EVIDENCE"))
        val answer = "\u5df2\u6839\u636e\u6765\u6e90\u5b8c\u6210\u67e5\u8be2\u3002[\u6765\u6e90](https://example.com/source)"
        val finalPlan = JSONObject().put("execution_location", "phone")
            .put("completion_requirements", fixed.getJSONObject("completion_requirements"))
            .put("actions", JSONArray().put(JSONObject().put("kind", "DRAFT_PLAN").put("target", "task-complete")
                .put("description", answer).put("parameters", JSONObject())))
        val done = agent.acceptSupervisedProjectPlan(observedPlan, reviewer, finalPlan.toString())
        assertEquals(done.plan?.actions?.firstOrNull()?.parameters?.get("prompt").orEmpty().takeLast(1800),
            AgentSupervisedProjectPlanDisposition.EXECUTABLE, done.disposition)
        assertEquals(answer, done.plan!!.actions.single().description)
        assertTrue(done.plan.actions.single().isTaskCompleteMarker())
        assertFalse(AgentSupervisedControlContent.isProtocol(answer))
    }

    @Test fun supervisedPayloadReachesThePlanParserExactlyOnceIncludingProtocolLikeText() {
        val payload = """{"execution_location":"phone","summary":"Inspect <tool_calls> evidence","actions":[]}"""
        val events = stream(payload, supervised = true)
        assertEquals(payload, events.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text })
        assertEquals(1, events.filterIsInstance<ModelStreamEvent.TextDelta>().size)
        assertEquals(1, events.filterIsInstance<ModelStreamEvent.Completed>().size)
        assertTrue(events.none { it is ModelStreamEvent.Failed || it is ModelStreamEvent.CitationPreview })
    }

    @Test fun malformedControlIsPreservedForRepairButOrdinaryChatStillHidesToolProtocol() {
        val payload = "<DSML><invoke name=\"web_search\">query</invoke></DSML>"
        val supervised = stream(payload, supervised = true)
        assertEquals(payload, supervised.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text })
        assertEquals("", stream(payload, supervised = false).filterIsInstance<ModelStreamEvent.TextDelta>()
            .joinToString("") { it.text })
    }

    @Test fun aControlPlanIsNotRejectedByTheFinalAnswerLiveDataHeuristic() {
        val executor = AndroidAgentActionExecutor(context)
        val action = AgentAction("control", AgentActionKind.CALL_CONNECTOR, "Cloud", AgentRisk.LOW,
            AgentActionStatus.RUNNING, "Plan", parameters = mapOf(
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                "routing_requires_live_data" to "true"))
        val response = """{"summary":"No real-time data yet; search next","execution_location":"phone","actions":[]}"""
        assertTrue(executor.replySatisfiesRoute(action, response))
        assertFalse(executor.replySatisfiesRoute(action, ""))
        assertFalse(executor.replySatisfiesRoute(action.copy(parameters = mapOf("routing_requires_live_data" to "true")), response))
    }

    private fun stream(payload: String, supervised: Boolean): List<ModelStreamEvent> = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val delta = JSONObject().put("choices", JSONArray().put(JSONObject().put("index", 0)
                .put("delta", JSONObject().put("content", payload)).put("finish_reason", "stop")))
            server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream")
                .setBody("data: $delta\n\ndata: [DONE]\n\n"))
            val id = "supervised-control-${UUID.randomUUID()}"
            val contact = JSONObject().put("id", id).put("cloud_provider", "custom")
                .put("cloud_model", "fixture-model").put("cloud_api_key", "fixture-only-key")
                .put("cloud_endpoint", server.url("/v1/chat/completions").toString())
            val events = mutableListOf<ModelStreamEvent>()
            withTimeout(20_000) {
                CloudConversationStreamEngine.streamConversation(context, contact,
                    listOf(ChatMessage(0L, "Return a JSON phone plan", true, Contact(id, "Test", ""))), id,
                    allowExternalTools = false, supervisedControl = supervised,
                    onToolEvent = { error("Control response must not execute a tool in the transport") })
                    .collect { events += it }
            }
            assertEquals(1, server.requestCount)
            val request = JSONObject(server.takeRequest().body.readUtf8())
            assertFalse(request.has("tools"))
            events
        }
    }
}
