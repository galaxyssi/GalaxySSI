package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentPhoneExecutionBoundaryTest {
    private val target = AgentCallableTarget(
        id = "codex", title = "Codex", kind = AgentConnectorKind.AGENT,
        status = AgentConnectorStatus.AVAILABLE, capabilities = listOf(AgentCapability.CHAT)
    )
    private val screen = ScreenContext("com.galaxyssi.chat", pageTitle = "GalaxySSI")

    private fun request(goal: String): AgentRequest = AgentRequest(
        goal, screen, listOf(target), memories = emptyList(),
        runtimeContext = AgentRuntimeContextBuilder.build(
            sessionId = "boundary", goal = goal, screen = screen,
            permissionMode = PermissionMode.FULL_ACCESS, highRiskGuard = false,
            memoryCapture = false, callableTargets = listOf(target), memories = emptyList()
        )
    )

    @Test fun allProviderRequestsKeepPhoneOwnershipWithoutRecognizingCommandWords() {
        for (goal in listOf("\u5b9a\u65f61\u5206\u949f", "60 seconds please", "hello",
                "Find current weather", "Make it quieter", "Do that again")) {
            val request = request(goal)
            val action = requireNotNull(RuleBasedAgentPlanner().supervisedProjectActions(request)).single()
            assertTrue(goal, action.isSupervisedProjectConnector())
            assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue, action.parameters[INTERNAL_TASK_EXECUTION_MODE])
            assertTrue(goal, AgentPhoneAgentLoopRoutingPolicy.shouldUseSupervisedLoop(
                goal, request.conversationContext, action.copy(parameters = mapOf("connector_id" to target.id))))
            val prompt = action.parameters.getValue("prompt")
            assertTrue(prompt.contains("Initial response option:"))
            assertTrue(prompt.contains("not an exact command phrase"))
            assertFalse(prompt.contains("Persistent phone Linux uses Debian"))
        }
    }

    @Test fun deterministicPhoneActionsDoNotAcquireAnExtraModelRoundTrip() {
        val request = request("hello")
        val native = AgentDeviceIntent.action(60)
        assertFalse(AgentPhoneAgentLoopRoutingPolicy.shouldUseSupervisedLoop(
            request.goal, request.conversationContext, native))
    }

    @Test fun generalToolValidationAcceptsPhoneActionsButNotRemoteExecution() {
        val site = AgentExecutionSiteDecision(AgentRequestedExecutionSite.PHONE)
        for (id in PhoneAssistantToolPolicy.directActionToolIds + AgentPhoneUiNativeTools.INSPECT) {
            val action = AgentDeviceIntent.action(60).copy(kind = AgentActionKind.CALL_NATIVE_TOOL,
                parameters = mapOf("tool_id" to id))
            assertTrue(id, AgentExecutionSiteDecisionCodec.acceptsActions(site, listOf(action)))
            assertFalse(AgentExecutionSiteDecisionCodec.acceptsActions(site, listOf(
                action.copy(kind = AgentActionKind.CALL_CONNECTOR))))
        }
        assertFalse(PhoneAssistantToolPolicy.allowsGeneralPhoneTool("desktop.shell.execute"))
    }

    @Test fun fallbackAndRepairKeepTheSamePhoneExecutionContract() {
        val action = RuleBasedAgentPlanner().supervisedProjectActions(request("\u5b9a\u65f61\u5206\u949f"))!!.single()
        val cloud = target.copy(id = "cloud", title = "Cloud", kind = AgentConnectorKind.MODEL)
        val repair = AgentSupervisedProjectRepairRoutingPolicy.select(
            action.copy(parameters = action.parameters + mapOf(
                "routing_fallback_ids" to cloud.id, "manual_target_locked" to "false")),
            listOf(target, cloud), attempt = 2, rotateAfter = 2)
        assertTrue(repair.rotated)
        assertTrue(repair.connector.isSupervisedProjectConnector())
        assertEquals(action.parameters["prompt"], repair.connector.parameters["prompt"])
        assertEquals(AgentTaskExecutionMode.PLAN_ONLY.wireValue,
            repair.connector.parameters[INTERNAL_TASK_EXECUTION_MODE])
    }
}
