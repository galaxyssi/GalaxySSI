package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentDeviceStatusShortcutCoverageTest {
    @Test fun completeSingleReadsKeepTheFastPath() {
        listOf(
            "Read the current battery level on this phone.", "Check battery saver status",
            "Check available RAM on this phone", "Show free storage", "Check network status",
            "Read audio status", "Check Bluetooth status", "Check wifi status", "Read NFC status",
            "\u67e5\u770b\u624b\u673a\u7535\u91cf", "\u8bfb\u53d6\u8fd9\u53f0\u624b\u673a\u7684\u5f53\u524d\u7535\u91cf\uff0c\u7b80\u77ed\u56de\u7b54\u3002",
            "\u8fd9\u53f0\u624b\u673a\u8fd8\u6709\u591a\u5c11\u8fd0\u884c\u5185\u5b58\uff1f", "\u67e5\u770b\u7701\u7535\u6a21\u5f0f",
            "\u67e5\u770b\u624b\u673a\u5b58\u50a8", "\u67e5\u770b\u624b\u673a\u7f51\u7edc\u72b6\u6001", "\u67e5\u770b\u624b\u6a5f\u96fb\u91cf"
        ).forEach { assertFalse(it, AgentDeviceStatusShortcutCoverage.requiresReasoning(it)) }
    }

    @Test fun compositeQueriesDoNotDependOnOneSpecificConjunction() {
        listOf(
            "Check battery status and remaining storage", "Read battery status, free RAM, network status",
            "Read storage status. Also explain how much space a backup would need.",
            "\u67e5\u4e00\u4e0b\u8fd9\u90e8\u624b\u673a\u5f53\u524d\u7684\u7535\u91cf\u767e\u5206\u6bd4\uff0c\u4ee5\u53ca\u5185\u90e8\u5b58\u50a8\u5269\u4f59\u53ef\u7528\u7a7a\u95f4\u3002\u53ea\u8bfb\u53d6\uff0c\u4e0d\u8981\u4fee\u6539\u4efb\u4f55\u8bbe\u7f6e\u6216\u6587\u4ef6\u3002\u4e24\u884c\u7b80\u77ed\u56de\u590d\u3002",
            "\u67e5\u770b\u96fb\u91cf\u548c\u5269\u9918\u5132\u5b58\u7a7a\u9593", "\u7535\u91cf\u3001\u5185\u5b58",
            "Read wifi status and Bluetooth status"
        ).forEach { assertTrue(it, AgentDeviceStatusShortcutCoverage.requiresReasoning(it)) }
    }

    @Test fun sameToolAdditionalFieldsAndNegativeConstraintsStillNeedCoverage() {
        listOf("Read battery percentage and temperature", "Don't read battery status; read storage only",
            "Read battery status and save it to battery.txt", "Read battery status and then turn on the flashlight",
            "If the battery is below 20%, show a warning", "Explain why battery status is wrong")
            .forEach { assertTrue(it, AgentDeviceStatusShortcutCoverage.requiresReasoning(it)) }
    }

    @Test fun ordinaryDiscussionAndCompleteMutationsAreNotReclassified() {
        listOf("Explain battery chemistry", "How do memory cells work?", "What is cloud storage?",
            "Set media volume 30", "Turn on the flashlight", "Open wifi settings", "hello",
            "Check this program for errors", "Show the diagram", "Read this paragraph")
            .forEach { assertFalse(it, AgentDeviceStatusShortcutCoverage.requiresReasoning(it)) }
    }

    @Test fun discussingSeveralStatusSubjectsIsNotADeviceQuery() {
        listOf("Explain memory and storage architecture", "Compare battery chemistry and memory technology",
            "\u8bb2\u89e3\u5185\u5b58\u548c\u5b58\u50a8\u7684\u5de5\u4f5c\u539f\u7406")
            .forEach { assertFalse(it, AgentDeviceStatusShortcutCoverage.requiresReasoning(it)) }
    }

    @Test fun statusMentionsDoNotOverrideProjectOrDesktopExecution() {
        for (goal in listOf("Audit this repository, inspect available memory, Git, builds, tests, and replan from the evidence.",
            "Read battery status and available storage on my computer",
            "\u67e5\u770b\u7535\u8111\u7535\u91cf\u548c\u5269\u4f59\u5b58\u50a8\u7a7a\u95f4")) {
            val request = request(goal)
            assertFalse(goal, AgentSupervisedProjectRoutingPolicy.isPhoneControl(goal, request.conversationContext))
            assertTrue(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
        }
    }

    @Test fun rejectedShortcutUsesPhoneReasoningWithTheWholeGoal() {
        val planner = RuleBasedAgentPlanner()
        for (goal in listOf("Check battery status and remaining storage",
            "\u67e5\u4e00\u4e0b\u624b\u673a\u7535\u91cf\u4ee5\u53ca\u5185\u90e8\u5b58\u50a8\u5269\u4f59\u53ef\u7528\u7a7a\u95f4",
            "Read battery percentage and temperature")) {
            val request = request(goal)
            assertNull(goal, planner.deterministicLocalAction(request))
            assertNull(goal, planner.androidSystemNativeToolAction(request))
            assertTrue(goal, AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal))
            assertTrue(goal, AgentSupervisedProjectRoutingPolicy.isPhoneControl(goal, request.conversationContext))
            val action = planner.plan(request).actions.single()
            assertTrue(goal, action.isSupervisedProjectConnector())
            assertEquals("selected-provider", action.parameters["connector_id"])
            assertTrue(action.parameters.getValue("prompt").contains(goal))
            assertTrue(action.parameters.getValue("prompt").contains("Plan a task on the user's Android phone"))
        }
    }

    @Test fun unavailableProviderCannotDowngradeToPartialSuccess() {
        val action = RuleBasedAgentPlanner().plan(request("Check battery status and free storage", false)).actions.single()
        assertEquals(AgentActionKind.CALL_CONNECTOR, action.kind)
        assertEquals(UNAVAILABLE_REASONING_CONNECTOR_ID, action.parameters["connector_id"])
    }

    @Test fun singleBatteryRequestStillExecutesWithoutAModel() {
        val action = RuleBasedAgentPlanner().deterministicLocalAction(request("Read the current battery level on this phone", false))
        assertNotNull(action)
        assertEquals(AgentHardwareNativeTools.BATTERY_STATUS, action!!.parameters["tool_id"])
    }

    private fun request(goal: String, withProvider: Boolean = true): AgentRequest {
        val targets = if (withProvider) listOf(AgentCallableTarget("selected-provider", "Selected model",
            AgentConnectorKind.MODEL, AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.REASONING))) else emptyList()
        val screen = ScreenContext("com.galaxyssi.chat", pageTitle = "Agent")
        val tools = listOf(AgentHardwareNativeTools.BATTERY_STATUS, AgentHardwareNativeTools.STORAGE_STATUS)
            .map { AgentNativeToolDescriptor(it, "1.0.0", it, it, AgentNativeToolLocation.PHONE,
                AgentNativeJsonSchema(mapOf("type" to "object")), AgentNativeJsonSchema(mapOf("type" to "object")),
                AgentNativeToolRisk.LOW) }
        return AgentRequest(goal, screen, targets, memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "status-coverage-test", goal = goal, screen = screen,
                permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
                callableTargets = targets, memories = emptyList(), nativeTools = tools))
    }
}
