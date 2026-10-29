package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentSupervisedCompletionDeviceTest {
    private val answer = "\u6d4b\u8bd5\u7ed3\u679c\uff1a\u4e09\u9879\u68c0\u67e5\u5747\u901a\u8fc7\u3002\n\n[\u6765\u6e90](https://example.com/source)"

    @Test fun codexAndDeepSeekStyleCompletionAliasesFinishWithoutRepairOrProviderDispatch() {
        for (kind in listOf("task-complete", "TASK_COMPLETE")) {
            val fixture = fixture()
            val response = JSONObject().put("execution_location", "phone").put("actions", JSONArray()
                .put(JSONObject().put("kind", kind).put("description", answer).put("completes_goal", true)
                    .put("parameters", JSONObject())))
            assertCompleted(fixture.agent.acceptSupervisedProjectPlan(fixture.plan, fixture.connector, response.toString()))
        }
    }

    @Test fun aRespondEnvelopeAfterFormatRepairDeliversTheAnswerWithNoExtraModelRound() {
        val fixture = fixture()
        val repair = fixture.agent.acceptSupervisedProjectPlan(fixture.plan, fixture.connector,
            """{"execution_location":"phone","actions":[{"kind":"UNKNOWN_ACTION","description":"invalid"}]}""")
        assertEquals(AgentSupervisedProjectPlanDisposition.REPAIR, repair.disposition)
        val plan = requireNotNull(repair.plan)
        val retry = plan.actions.single()
        assertEquals("true", retry.parameters["manual_target_locked"])
        assertEquals("fixture-model", retry.parameters["model"])
        assertEquals(fixture.connector.parameters["connector_id"], retry.parameters["connector_id"])
        assertCompleted(fixture.agent.acceptSupervisedProjectPlan(plan, retry, respond()))
    }

    @Test fun repairedCompletionDoesNotDropUnfulfilledPublicationRequirements() {
        val required = AgentCompletionRequirements(AgentPublicationRequirement.PULL_REQUEST, true)
        val fixture = fixture(required = required)
        val connector = fixture.connector.copy(parameters = fixture.connector.parameters + mapOf(
            SUPERVISED_PROJECT_REPAIR_KIND_PARAMETER to "format", "supervised_iteration" to "1"))
        val plan = fixture.plan.copy(actions = listOf(connector))
        val decision = fixture.agent.acceptSupervisedProjectPlan(plan, connector, respond())
        assertEquals(AgentSupervisedProjectPlanDisposition.REPAIR, decision.disposition)
        assertEquals(required, decision.plan!!.completionRequirements)
        assertEquals("", decision.finalResponse)
    }

    @Test fun repairedProseCannotClaimAnUnexecutedPhoneTimerSucceeded() {
        val fixture = fixture(goal = "\u8bbe\u7f6e1\u5206\u949f\u5012\u8ba1\u65f6")
        val connector = fixture.connector.copy(parameters = fixture.connector.parameters + mapOf(
            SUPERVISED_PROJECT_REPAIR_KIND_PARAMETER to "format", "supervised_iteration" to "1"))
        val decision = fixture.agent.acceptSupervisedProjectPlan(fixture.plan.copy(actions = listOf(connector)), connector,
            JSONObject().put("disposition", "respond").put("final_response", "\u5df2\u542f\u52a8\u5012\u8ba1\u65f6").toString())
        assertEquals(AgentSupervisedProjectPlanDisposition.REPAIR, decision.disposition)
        assertEquals("", decision.finalResponse)
    }

    private fun respond() = JSONObject().put("disposition", "respond").put("final_response", answer).toString()

    private fun assertCompleted(decision: AgentSupervisedProjectPlanDecision) {
        assertEquals(decision.plan?.actions?.firstOrNull()?.parameters?.get("prompt").orEmpty().takeLast(1600),
            AgentSupervisedProjectPlanDisposition.FINAL_RESPONSE, decision.disposition)
        assertEquals(answer, decision.finalResponse)
        assertNull(decision.plan)
    }

    @Test fun initialAndContinuedAnswersShareTheSameCompletionChecks() {
        for (iteration in listOf("0", "1")) {
            val fixture = fixture()
            val connector = fixture.connector.copy(parameters = fixture.connector.parameters +
                ("supervised_iteration" to iteration))
            assertCompleted(fixture.agent.acceptSupervisedProjectPlan(fixture.plan.copy(actions = listOf(connector)),
                connector, respond()))
        }
    }

    @Test fun initialAnswerCannotBypassPreviouslyDeclaredPublicationRequirements() {
        val required = AgentCompletionRequirements(AgentPublicationRequirement.PULL_REQUEST, true)
        val fixture = fixture(required = required)
        val decision = fixture.agent.acceptSupervisedProjectPlan(fixture.plan, fixture.connector, respond())
        assertEquals(AgentSupervisedProjectPlanDisposition.REPAIR, decision.disposition)
        assertEquals(required, decision.plan!!.completionRequirements)
    }

    @Test fun missingRequirementsCannotHideAnUnknownToolEffect() {
        val fixture = fixture()
        val connector = fixture.connector.copy(parameters = fixture.connector.parameters + ("supervised_iteration" to "1"))
        val effect = AgentAction("unknown-effect", AgentActionKind.CALL_NATIVE_TOOL, "fixture-write", AgentRisk.LOW,
            AgentActionStatus.COMPLETED, "Write", parameters = connector.parameters.filterKeys {
                it in setOf(INTERNAL_CONVERSATION_ID, INTERNAL_TURN_ID)
            } + ("tool_id" to "fixture-write"))
        val plan = fixture.plan.copy(actions = listOf(connector), actionHistory = listOf(effect))
        val decision = fixture.agent.acceptSupervisedProjectPlan(plan, connector, respond())
        assertEquals(AgentSupervisedProjectPlanDisposition.REPAIR, decision.disposition)
        assertEquals("", decision.finalResponse)
    }

    private data class Fixture(val agent: MobileNativeAgent, val plan: AgentPlan, val connector: AgentAction)

    private fun fixture(goal: String = "\u8bf7\u8bf4\u660e\u6d4b\u8bd5\u7ed3\u679c",
        required: AgentCompletionRequirements? = null): Fixture {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scope = "completion-format-${UUID.randomUUID()}"
        val screen = ScreenContext("Fixture", pageTitle = "Completion protocol")
        val target = AgentCallableTarget("fixture-cloud", "Fixture cloud", AgentConnectorKind.MODEL,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT, AgentCapability.REASONING))
        val agent = MobileNativeAgent(context, sessionStore = InMemoryAgentSessionStore(),
            memoryStore = InMemoryAgentMemoryStore(), screenObservationOverride = false,
            nativeToolRegistryProvider = { AgentNativeToolRegistry() }, connectorRegistry = object : AgentConnectorRegistry {
                override fun availableTargets() = listOf(target)
            }, actionExecutor = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult =
                    error("A completed answer must not dispatch to a phone tool or provider")
            }).apply {
                sessionId = scope
                currentGoal = goal
                currentScreen = screen
                activeConversationContext = AgentConversationContext(scope, "", emptyList(), true)
                activeConversationTurnId = scope
                activeRunRuntimeContext = AgentRuntimeContextBuilder.build(scope, goal, screen,
                    PermissionMode.FULL_ACCESS, false, false, listOf(target), emptyList())
            }
        val connector = AgentAction("provider", AgentActionKind.CALL_CONNECTOR, target.title,
            AgentRisk.LOW, AgentActionStatus.COMPLETED, "Reason", parameters = mapOf(
                "connector_id" to target.id, "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                "supervised_iteration" to "0", "manual_target_locked" to "true", "model" to "fixture-model",
                INTERNAL_CONVERSATION_ID to scope, INTERNAL_TURN_ID to scope))
        return Fixture(agent, AgentPlan(goal, screen, emptyList(), listOf(connector),
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE, completionRequirements = required), connector)
    }
}
