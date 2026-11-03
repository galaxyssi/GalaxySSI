package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentDeviceShortcutIntentTest {
    @Test fun completeCommandsPreserveTheirParameters() {
        assertEquals(mapOf("enabled" to true), parse("Please turn on the flashlight.").input)
        assertEquals(mapOf("enabled" to false), parse("\u8bf7\u5173\u95ed\u624b\u7535\u7b52").input)
        assertEquals(mapOf("enabled" to true), parse("\u6253\u958b\u624b\u96fb\u7b52").input)
        assertEquals(mapOf("stream" to "music", "percent" to 30), parse("Set media volume 30").input)
        assertEquals(mapOf("stream" to "ring", "percent" to 50), parse("Change ring volume to 50%").input)
        assertEquals(mapOf("stream" to "music", "percent" to 50), parse("\u628a\u97f3\u91cf\u8bbe\u7f6e\u4e3a50").input)
        assertEquals(mapOf("stream" to "notification", "percent" to 0), parse("Set notification volume to 0").input)
        assertEquals(mapOf("facing" to "back"), parse("\u6253\u5f00\u76f8\u673a\u62cd\u7167").input)
        assertEquals(mapOf("max_duration_seconds" to 8), parse("\u5f55\u97f3 8 \u79d2").input)
        assertEquals(mapOf("max_duration_seconds" to 5), parse("Record audio for five seconds").input)
        assertEquals(mapOf("max_duration_seconds" to 30), parse("\u9304\u97f3\u534a\u5206\u9418").input)
    }

    @Test fun negationQuestionsAndConditionsNeverBecomeImmediateMutations() {
        reasoningOnly(
            "Do not turn on the flashlight", "Why does turn on the flashlight fail?",
            "If it is dark, turn on the flashlight", "\u4e0d\u8981\u6253\u5f00\u624b\u7535\u7b52",
            "\u7535\u91cf\u4f4e\u4e8e20%\u65f6\u5173\u95ed\u624b\u7535\u7b52",
            "Don't set volume to 50", "Explain how to set volume to 50",
            "\u4e0d\u8981\u62cd\u7167", "\u4e0d\u8981\u5f55\u97f3"
        )
    }

    @Test fun additionalConstraintsAreNotDiscarded() {
        reasoningOnly(
            "Turn on the flashlight for 10 seconds", "Set volume from 20 to 50",
            "\u628a\u97f3\u91cf\u4ece20\u8c03\u523050", "Set volume 20 and notification volume 50",
            "Open camera and take three photos", "\u6253\u5f00\u524d\u7f6e\u6444\u50cf\u5934\u62cd\u7167",
            "\u5f55\u97f310\u79d2\u540e\u518d\u8f6c\u6587\u5b57", "Record audio for 5 seconds at 16 kHz"
        )
    }

    @Test fun unsupportedOrMissingValuesAreNotClampedOrInvented() {
        reasoningOnly("Record audio", "\u5f55\u97f3\u4e00\u5206\u949f", "Record audio for zero seconds",
            "Record audio for 31 seconds", "Set volume to 150", "Set volume to -20",
            "Set volume to 0.5", "Set volume to fifty", "\u628a\u97f3\u91cf\u8c03\u5927\u4e00\u70b9")
    }

    @Test fun durationParserConsumesTheWholeExpression() {
        assertEquals(25, AgentDeviceIntent.completeDurationSeconds("20 seconds and 5 seconds"))
        assertNull(AgentDeviceIntent.completeDurationSeconds("5 seconds after the signal"))
        assertNull(AgentDeviceIntent.completeDurationSeconds("5 seconds, then 10 seconds"))
        assertNull(AgentDeviceIntent.completeDurationSeconds("for 5 seconds"))
    }

    @Test fun rejectedShortcutCannotFallThroughToAnotherLocalAction() {
        for (goal in listOf("\u6253\u5f00\u76f8\u673a\u540e\u62cd\u4e09\u5f20\u7167\u7247",
            "Don't turn on the flashlight", "Set media volume from 20 to 50", "Record audio for 60 seconds",
            "Turn on the flashlight and then read the current battery level")) {
            val request = request(goal)
            val planner = RuleBasedAgentPlanner()
            assertNull(goal, planner.deterministicLocalAction(request))
            assertNull(goal, planner.androidSystemNativeToolAction(request))
            assertNull(goal, AgentSystemToolPlanner.actionFor(request))
            assertTrue(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
            val action = planner.plan(request).actions.single()
            assertTrue(goal, action.isSupervisedProjectConnector())
            assertEquals("test-provider", action.parameters["connector_id"])
            assertTrue(action.parameters.getValue("prompt").contains(goal))
        }
    }

    @Test fun absentProviderDoesNotRunAnIncompleteShortcut() {
        val request = request("Record audio for 60 seconds", withProvider = false)
        val action = RuleBasedAgentPlanner().plan(request).actions.single()
        assertEquals(AgentActionKind.CALL_CONNECTOR, action.kind)
        assertEquals(UNAVAILABLE_REASONING_CONNECTOR_ID, action.parameters["connector_id"])
    }

    @Test fun unresolvedAppNamesUseSelectedReasoningWithoutAnEmptyPackageLaunch() {
        for (goal in listOf("Open Calculatr on my phone", "Launch Calculator app on this device")) {
            val planner = RuleBasedAgentPlanner()
            assertNull(planner.deterministicLocalAction(request(goal)))
            val action = planner.plan(request(goal)).actions.single()
            assertTrue(goal, action.isSupervisedProjectConnector())
            assertEquals("test-provider", action.parameters["connector_id"])
            assertTrue(action.parameters.getValue("prompt").contains(goal))
            val unavailable = planner.plan(request(goal, withProvider = false)).actions.single()
            assertEquals(AgentActionKind.CALL_CONNECTOR, unavailable.kind)
            assertEquals(UNAVAILABLE_REASONING_CONNECTOR_ID, unavailable.parameters["connector_id"])
        }
    }

    @Test fun ordinaryDiscussionWithoutAnActionIsNotForcedIntoPhoneExecution() {
        listOf("Explain camera sensors", "What is audio?", "How do microphones work?", "hello").forEach {
            assertFalse(it, AgentDeviceShortcutIntent.requiresReasoning(it))
            assertNull(AgentDeviceShortcutIntent.parse(it))
        }
    }

    private fun parse(goal: String) = requireNotNull(AgentDeviceShortcutIntent.parse(goal)) { goal }

    private fun reasoningOnly(vararg goals: String) = goals.forEach {
        assertNull(it, AgentDeviceShortcutIntent.parse(it))
        assertTrue(it, AgentDeviceShortcutIntent.requiresReasoning(it))
    }

    private fun request(goal: String, withProvider: Boolean = true): AgentRequest {
        val targets = if (withProvider) listOf(AgentCallableTarget("test-provider", "Selected model",
            AgentConnectorKind.MODEL, AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.REASONING))) else emptyList()
        val screen = ScreenContext("com.galaxyssi.chat", pageTitle = "Agent")
        val descriptors = listOf(AgentHardwareNativeTools.FLASHLIGHT_SET, AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET)
            .map { AgentNativeToolDescriptor(it, "1.0.0", it, it, AgentNativeToolLocation.PHONE,
                AgentNativeJsonSchema(mapOf("type" to "object")), AgentNativeJsonSchema(mapOf("type" to "object")),
                AgentNativeToolRisk.MEDIUM) }
        return AgentRequest(goal, screen, targets, memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "shortcut-test", goal = goal, screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
                callableTargets = targets, memories = emptyList(), nativeTools = descriptors))
    }
}
