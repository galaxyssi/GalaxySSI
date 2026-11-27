package com.galaxyssi.chat

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
import java.util.UUID

class PinnedCloudTeamOfferDeviceTest {
    private val body = "A fixed fare limits uncertainty; a metered fare can cost less."
    private data class Result(val text: String, val invitations: Int, val errors: List<String>, val advertised: Boolean)

    @Test fun nativeFinalAnswerCanOfferReviewWithoutStartingWorkers() {
        val result = singleReply(native = true, valid = true, eligible = true)
        assertTrue(result.advertised)
        assertEquals(emptyList<String>(), result.errors)
        assertEquals(body, result.text)
        assertEquals(1, result.invitations)
    }

    @Test fun malformedArgumentsNeverInviteOrTriggerAnotherRequest() {
        val result = singleReply(native = true, valid = false, eligible = true)
        assertTrue(result.advertised)
        assertEquals("", result.text)
        assertEquals(listOf(PinnedCloudTeamOffer.INVALID), result.errors)
        assertEquals(0, result.invitations)
    }

    @Test fun ordinaryTextNeverCreatesAnOfferEvenWhenAdvertised() {
        for (eligible in listOf(true, false)) {
            val result = singleReply(native = false, valid = true, eligible = eligible)
            assertEquals(eligible, result.advertised)
            assertEquals(emptyList<String>(), result.errors)
            assertEquals(body, result.text)
            assertEquals(0, result.invitations)
        }
    }

    @Test fun ordinaryPhonePlannerStillOwnsTheFinalResponseWhenTheModelOffersReview() {
        val result = singleReply(native = true, valid = true, eligible = true, supervised = true)
        assertEquals(emptyList<String>(), result.errors)
        assertTrue(result.advertised)
        assertEquals(body, AgentSupervisedProjectDirectResponseCodec.parse(result.text))
        val plan = JSONObject(AgentSupervisedProjectDirectResponseCodec.completionPlan(result.text)!!)
        assertEquals("phone", plan.getString("execution_location"))
        val actions = plan.getJSONArray("actions")
        assertEquals(1, actions.length())
        assertEquals("task-complete", actions.getJSONObject(0).getString("target"))
        assertEquals(1, result.invitations)
        verifyAcceptedPhoneTurn(result.text)
    }

    private fun verifyAcceptedPhoneTurn(envelope: String) {
        val scope = "review-kernel-${UUID.randomUUID()}"
        val source = Long.MAX_VALUE - 711L
        val screen = ScreenContext("Fixture", pageTitle = "Chat")
        val goal = "Compare two hypothetical fare models."
        val pin = GoalRoute("fixture-cloud", "fixture", "fixture-hash", "example.invalid")
        val target = AgentCallableTarget(pin.target, "Fixture", AgentConnectorKind.MODEL,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT, AgentCapability.REASONING))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val action = AgentAction("provider", AgentActionKind.CALL_CONNECTOR, target.title, AgentRisk.LOW,
            AgentActionStatus.WAITING_RESPONSE, "Reason", parameters = mapOf("connector_id" to pin.target,
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE, "supervised_iteration" to "0",
                "manual_target_locked" to "true", "manual_model_id" to pin.model, "model" to pin.model,
                INTERNAL_TASK_EXECUTION_MODE to AgentTaskExecutionMode.PLAN_ONLY.wireValue,
                INTERNAL_CONVERSATION_ID to scope, INTERNAL_TURN_ID to scope))
        val agent = MobileNativeAgent(context, sessionStore = InMemoryAgentSessionStore(),
            memoryStore = InMemoryAgentMemoryStore(), screenObservationOverride = false,
            nativeToolRegistryProvider = { AgentNativeToolRegistry() }, connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = listOf(target)
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    check(action.isTaskCompleteMarker()) { "Fixture must not dispatch a new request or phone tool" }
                    return AndroidAgentActionExecutor(context).execute(action, screen)
                }
            }).apply {
                sessionId = scope
                currentGoal = goal
                currentScreen = screen
                activeConversationContext = AgentConversationContext(scope, "", emptyList(), true)
                activeConversationTurnId = scope
                activeRunRuntimeContext = AgentRuntimeContextBuilder.build(scope, goal, screen,
                    PermissionMode.FULL_ACCESS, false, false, listOf(target), emptyList())
                currentPlan = AgentPlan(goal, screen, emptyList(), listOf(action),
                    plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE)
                lastActionResult = AgentActionResult(action.id, true, "Waiting", mapOf(
                    "source_message_id" to source.toString(), "contact_id" to pin.target, "awaiting_response" to "true",
                    "conversation_id" to scope, "turn_id" to scope, "remote_task_id" to scope))
                phase = AgentPhase.WAITING_RESPONSE
                check(startExecutionLoop(scope))
                check(advanceExecutionLoop(AgentExecutionLoopPhase.ACT, "Synthetic dispatch", action.id))
                check(advanceExecutionLoop(AgentExecutionLoopPhase.WAITING_RESPONSE, "Synthetic wait", action.id))
            }
        val draft = TeamReviewDraft().apply { bind(revision, scope, scope, pin) }
        assertTrue(draft.arm(scope, scope, pin, body, agent))
        val delivery = AgentConnectorResponse(source, pin.target, envelope, scope, scope, scope)
        assertTrue(SupervisedTeamReview.markDelivery(delivery))
        assertFalse(SupervisedTeamReview.markDelivery(delivery))
        val ticket = requireNotNull(draft.takeFresh(delivery, agent))
        assertTrue(ticket.awaiting(agent.phase, agent.lastActionResult, action, source))
        val original = requireNotNull(agent.currentPlan)
        val accepted = requireNotNull(agent.acceptConnectorOutcome(delivery))
        assertEquals(AgentPhase.COMPLETED, accepted.phase)
        assertTrue("The real terminal plan must match the proposed answer", ticket.completed(accepted, source))
        assertTrue("Only the originating plan revision may present", ticket.finalized(original, accepted, agent.snapshot(), source))
        assertFalse(draft.claim(scope, scope, pin, ticket))
        ticket.finalBody(scope, scope, requireNotNull(accepted.lastActionResult).message)
        assertTrue(draft.claim(scope, scope, pin, ticket))
    }

    private fun singleReply(native: Boolean, valid: Boolean, eligible: Boolean, supervised: Boolean = false): Result = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val id = "review-fixture-${UUID.randomUUID()}"
            val delta = if (native) {
                val args = JSONObject().put("answer", body).put("propose_team_review", valid)
                val fn = JSONObject().put("name", PinnedCloudTeamOffer.NAME).put("arguments", args.toString())
                val call = JSONObject().put("id", "fixture-call").put("index", 0).put("type", "function").put("function", fn)
                JSONObject().put("tool_calls", JSONArray().put(call))
            } else JSONObject().put("content", body)
            val frame = JSONObject().put("choices", JSONArray().put(JSONObject().put("index", 0).put("delta", delta)
                .put("finish_reason", if (native) "tool_calls" else "stop")))
            server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream")
                .setBody("data: $frame\n\ndata: [DONE]\n\n"))
            val contact = JSONObject().put("id", id).put("cloud_provider", "custom")
                .put("cloud_model", "fixture").put("cloud_api_key", "fixture-only")
                .put("cloud_endpoint", server.url("/v1/chat/completions").toString())
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            var offers = 0
            val onOffer: ((String) -> Unit)? = if (eligible) ({ text -> assertEquals(body, text); offers++ }) else null
            val events = mutableListOf<ModelStreamEvent>()
            val stages = mutableListOf<Pair<String, String>>()
            withTimeout(20_000) {
                CloudConversationStreamEngine.streamConversation(context, contact,
                    listOf(ChatMessage(0L, "Compare two hypothetical fare models.", true, Contact(id, "Fixture", ""))),
                    id, allowExternalTools = true, onToolEvent = {
                        stages += it.tool to it.stage
                        check(it.tool == "research" && it.stage == "planning") { "Unexpected tool execution" }
                    },
                    onTeamReviewAnswer = onOffer, supervisedControl = supervised).collect { events.add(it) }
            }
            assertEquals(listOf("research" to "planning"), stages)
            assertEquals(events.filterIsInstance<ModelStreamEvent.Failed>().map { it.error.code }.toString(),
                1, server.requestCount)
            val tools = JSONObject(server.takeRequest().body.readUtf8()).getJSONArray("tools")
            val names = (0 until tools.length()).map { tools.getJSONObject(it).getJSONObject("function").getString("name") }
            Result(events.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text }, offers,
                events.filterIsInstance<ModelStreamEvent.Failed>().map { it.error.code }, PinnedCloudTeamOffer.NAME in names)
        }
    }
}
