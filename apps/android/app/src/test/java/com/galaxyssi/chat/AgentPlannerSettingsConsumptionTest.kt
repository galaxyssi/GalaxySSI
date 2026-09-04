package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentPlannerSettingsConsumptionTest {
    @Test
    fun maximumActionsRejectsOversizedModelPlans() {
        val raw = planJson(
            actionJson("first", "READ_SCREEN"),
            actionJson("second", "BACK")
        )

        assertNull(AgentModelPlanParser.parse(request(), raw, AgentModelPlannerSettings(maxActions = 1)))
        assertNotNull(AgentModelPlanParser.parse(request(), raw, AgentModelPlannerSettings(maxActions = 2)))
    }

    @Test
    fun multiAgentCoordinationControlsDependencyGraphs() {
        val raw = planJson(
            actionJson("first", "READ_SCREEN"),
            actionJson("second", "BACK", dependsOn = listOf("first"))
        )

        assertNull(
            AgentModelPlanParser.parse(
                request(),
                raw,
                AgentModelPlannerSettings(multiAgentCoordination = false)
            )
        )
        assertNotNull(
            AgentModelPlanParser.parse(
                request(),
                raw,
                AgentModelPlannerSettings(multiAgentCoordination = true)
            )
        )
    }

    @Test
    fun maximumAgentHopsLimitsDependencyDepth() {
        val raw = planJson(
            actionJson("first", "READ_SCREEN"),
            actionJson("second", "BACK", dependsOn = listOf("first")),
            actionJson("third", "HOME", dependsOn = listOf("second"))
        )

        assertNull(AgentModelPlanParser.parse(request(), raw, AgentModelPlannerSettings(maxAgentHops = 1)))
        assertNotNull(AgentModelPlanParser.parse(request(), raw, AgentModelPlannerSettings(maxAgentHops = 3)))
    }

    @Test
    fun initialPlansRejectStandaloneDraftActions() {
        val raw = planJson(actionJson("draft", "DRAFT_PLAN", target = "local-agent-runtime"))

        assertNull(AgentModelPlanParser.parse(request(), raw, AgentModelPlannerSettings()))
    }

    @Test
    fun executablePlansRejectTrailingDraftActions() {
        val raw = planJson(
            actionJson("execute", "READ_SCREEN"),
            actionJson(
                ref = "draft",
                kind = "DRAFT_PLAN",
                dependsOn = listOf("execute"),
                target = "local-agent-runtime"
            )
        )

        assertNull(
            AgentModelPlanParser.parse(
                request(replanReason = "connector_response_received"),
                raw,
                AgentModelPlannerSettings()
            )
        )
    }

    @Test
    fun completedReplansAcceptOnlyTaskCompleteMarker() {
        val raw = planJson(actionJson("done", "DRAFT_PLAN", target = "task-complete"))

        val plan = AgentModelPlanParser.parse(
            request(replanReason = "connector_response_received"),
            raw,
            AgentModelPlannerSettings()
        )

        assertNotNull(plan)
        assertEquals("task-complete", plan?.actions?.single()?.target)
    }

    @Test
    fun rollingReplanPromptRequestsABoundedRevisableBatch() {
        val prompt = AgentModelPlanningPrompt.build(
            request = request(
                replanReason = "${AgentRollingPlanPolicy.REPLAN_REASON_PREFIX}revision=3"
            ),
            settings = AgentModelPlannerSettings(maxActions = 8),
            requirements = AgentTaskRequirementAnalyzer.analyze("Develop and verify a project")
        )

        assertTrue(prompt.contains("Plan only the next bounded execution batch"))
        assertTrue(prompt.contains("prefer 3 to 8 actionable steps"))
        assertTrue(prompt.contains("add, remove, reorder, or replace future actions"))
        assertTrue(prompt.contains("target task-complete"))
    }

    @Test
    fun modelTerminalOutcomeDecisionSurvivesNativeToolPlanParsing() {
        val base = request(replanReason = "continue_from_observation")
        val descriptor = AgentNativeToolDescriptor(
            id = AgentMobileProjectNativeTools.CREATE_PULL_REQUEST,
            version = "1.0.0",
            title = "Create pull request",
            description = "Create a verified pull request",
            location = AgentNativeToolLocation.APPLICATION,
            inputSchema = AgentNativeJsonSchema.objectSchema(emptyMap()),
            outputSchema = AgentNativeJsonSchema.objectSchema(emptyMap()),
            risk = AgentNativeToolRisk.HIGH
        )
        val request = base.copy(
            runtimeContext = AgentRuntimeContextBuilder.build(
                sessionId = "planner-terminal-test",
                goal = base.goal,
                screen = base.screen,
                permissionMode = PermissionMode.FULL_ACCESS,
                highRiskGuard = false,
                memoryCapture = false,
                callableTargets = emptyList(),
                memories = emptyList(),
                nativeTools = listOf(descriptor)
            )
        )
        val raw = """
            {"summary":"The verified branch is ready to publish.","actions":[
              {"ref":"publish","kind":"CALL_NATIVE_TOOL","target":"pull request",
               "description":"Create the verified pull request","completes_goal":true,
               "depends_on":[],"use_outputs_from":[],
               "parameters":{"tool_id":"${AgentMobileProjectNativeTools.CREATE_PULL_REQUEST}","arguments":{}}}
            ]}
        """.trimIndent()

        val plan = AgentModelPlanParser.parse(request, raw, AgentModelPlannerSettings(maxActions = 1))

        assertNotNull(plan)
        assertEquals(
            "true",
            plan?.actions?.single()?.parameters
                ?.get(AgentSupervisedProjectCompletionPolicy.MODEL_TERMINAL_OUTCOME_PARAMETER)
        )
    }

    @Test
    fun completedToolCallCountDoesNotStopForegroundAutonomousActions() {
        val completed = action("completed", AgentActionStatus.COMPLETED)
        val pending = action("pending", AgentActionStatus.PENDING_CONFIRMATION)
        val plan = AgentPlanFactory.actions(request(), listOf(pending)).copy(
            actionHistory = listOf(completed)
        )

        val decision = AgentAutonomyGuard.review(
            plan = plan,
            action = pending,
            settings = AgentModelPlannerSettings(maxToolCalls = 1)
        )

        assertTrue(decision.allowed)
        assertEquals(1, decision.completedToolCalls)
    }

    @Test
    fun supervisedPhoneProjectIsNotStoppedByLifetimeToolCallCount() {
        val completed = (1..40).map { index ->
            action("completed-$index", AgentActionStatus.COMPLETED).copy(
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = "galaxyssi.project.repository.inspect",
                parameters = mapOf("tool_id" to "galaxyssi.project.repository.inspect")
            )
        }
        val supervisor = AgentAction(
            id = "supervisor",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = "Codex",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.COMPLETED,
            description = "Choose the next phone action",
            parameters = mapOf(
                "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE
            ),
            requiresConfirmation = false
        )
        val pending = action("pending", AgentActionStatus.PENDING_CONFIRMATION).copy(
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "galaxyssi.project.repository.inspect",
            parameters = mapOf("tool_id" to "galaxyssi.project.repository.inspect")
        )
        val plan = AgentPlanFactory.actions(request(), listOf(pending)).copy(
            actionHistory = completed + supervisor,
            plannerProfile = PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
        )

        val decision = AgentAutonomyGuard.review(
            plan = plan,
            action = pending,
            settings = AgentModelPlannerSettings(maxToolCalls = 4)
        )

        assertTrue(decision.allowed)
        assertEquals(41, decision.completedToolCalls)
    }

    @Test
    fun repeatedConnectorReasoningIsLimitedByBudgetInsteadOfLoopSignature() {
        val completed = (1..2).map { index ->
            AgentAction(
                id = "connector-$index",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = "Codex",
                risk = AgentRisk.LOW,
                status = AgentActionStatus.COMPLETED,
                description = "Continue reasoning",
                parameters = mapOf("prompt" to "Continue from the latest observation"),
                requiresConfirmation = false
            )
        }
        val pending = completed.first().copy(
            id = "connector-next",
            status = AgentActionStatus.PROPOSED
        )
        val plan = AgentPlanFactory.actions(request(), listOf(pending)).copy(
            actionHistory = completed
        )

        val decision = AgentAutonomyGuard.review(
            plan = plan,
            action = pending,
            settings = AgentModelPlannerSettings(maxToolCalls = 8)
        )

        assertTrue(decision.allowed)
    }

    @Test
    fun consecutiveIdenticalDeviceActionsAreBlockedAsANoProgressLoop() {
        val repeated = (1..2).map { index ->
            action("open-$index", AgentActionStatus.COMPLETED).copy(
                kind = AgentActionKind.OPEN_APP,
                target = "com.example.app"
            )
        }
        val pending = repeated.last().copy(
            id = "open-next",
            status = AgentActionStatus.PENDING_CONFIRMATION
        )
        val plan = AgentPlanFactory.actions(request(), listOf(pending)).copy(
            actionHistory = repeated
        )

        val decision = AgentAutonomyGuard.review(plan, pending, AgentModelPlannerSettings())

        assertFalse(decision.allowed)
        assertEquals(2, decision.repeatedCalls)
    }

    @Test
    fun verifiedObservationResetsTheRepeatedDeviceActionGuard() {
        val open = action("open", AgentActionStatus.COMPLETED).copy(
            kind = AgentActionKind.OPEN_APP,
            target = "com.example.app"
        )
        val observation = action("observe", AgentActionStatus.COMPLETED).copy(
            kind = AgentActionKind.READ_SCREEN,
            target = "screen"
        )
        val pending = open.copy(
            id = "open-again",
            status = AgentActionStatus.PENDING_CONFIRMATION
        )
        val plan = AgentPlanFactory.actions(request(), listOf(pending)).copy(
            actionHistory = listOf(open, open.copy(id = "open-second"), observation)
        )

        val decision = AgentAutonomyGuard.review(plan, pending, AgentModelPlannerSettings())

        assertTrue(decision.allowed)
        assertEquals(0, decision.repeatedCalls)
    }

    private fun request(replanReason: String = ""): AgentRequest {
        val screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent")
        return AgentRequest(
            goal = "Test planning settings",
            screen = screen,
            targets = emptyList(),
            memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(
                sessionId = "planner-settings-test",
                goal = "Test planning settings",
                screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK,
                highRiskGuard = true,
                memoryCapture = false,
                callableTargets = emptyList(),
                memories = emptyList(),
                nativeTools = emptyList()
            ),
            replanReason = replanReason
        )
    }

    private fun action(id: String, status: AgentActionStatus) = AgentAction(
        id = id,
        kind = AgentActionKind.OPEN_APP,
        target = "com.galaxyssi.chat",
        risk = AgentRisk.LOW,
        status = status,
        description = id,
        parameters = mapOf("package" to "com.galaxyssi.chat")
    )

    private fun planJson(vararg actions: String): String =
        "{\"actions\":[${actions.joinToString(",")}] }"

    private fun actionJson(
        ref: String,
        kind: String,
        dependsOn: List<String> = emptyList(),
        target: String = ""
    ): String {
        val dependencies = dependsOn.joinToString(",") { "\"$it\"" }
        return "{\"ref\":\"$ref\",\"kind\":\"$kind\",\"target\":\"$target\",\"depends_on\":[$dependencies],\"parameters\":{}}"
    }
}
