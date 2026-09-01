package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentFutureRoutingPolicyTest {
    @Test
    fun detectsRestrictedChineseIdentityAndPaymentGoals() {
        val identity = AgentTaskRequirementAnalyzer.analyze("\u8bf7\u8bfb\u53d6\u6211\u7684\u8eab\u4efd\u8bc1\u5e76\u5b8c\u6210\u652f\u4ed8")

        assertEquals(AgentDataSensitivity.RESTRICTED, identity.dataSensitivity)
    }

    @Test
    fun detectsChineseBackgroundAndLongRunningGoals() {
        val background = AgentTaskRequirementAnalyzer.analyze("\u5728\u540e\u53f0\u76d1\u63a7\u4efb\u52a1\u72b6\u6001")
        val longRunning = AgentTaskRequirementAnalyzer.analyze("\u6301\u7eed\u8fd0\u884c\u76f4\u5230\u5b8c\u6210")

        assertEquals(AgentExecutionHorizon.BACKGROUND, background.executionHorizon)
        assertEquals(AgentExecutionHorizon.LONG_RUNNING, longRunning.executionHorizon)
    }

    @Test
    fun keepsOfflineGoalsInsidePrivateMode() {
        val requirements = AgentTaskRequirementAnalyzer.analyze("Keep this offline and local only")

        assertEquals(AgentRoutingMode.PRIVATE, requirements.mode)
        assertTrue(requirements.localOnly)
        assertEquals(AgentDataSensitivity.CONFIDENTIAL, requirements.dataSensitivity)
    }

    @Test
    fun codexAdvertisesWebCapabilityWithoutHostClassifyingThePrompt() {
        val codex = StaticAgentConnectorRegistry().availableTargets().first { it.id == "codex" }
        val requirements = AgentTaskRequirementAnalyzer.analyze("What is the current weather in Shanghai today?")

        assertTrue(AgentCapability.CHAT in codex.capabilities)
        assertTrue(AgentCapability.RESEARCH in codex.capabilities)
        assertTrue(AgentCapability.LIVE_DATA in codex.capabilities)
        assertTrue(requirements.capabilities.all { it in codex.capabilities })
        assertFalse(requirements.liveDataRequired)
        assertFalse(AgentCapability.LIVE_DATA in requirements.capabilities)
    }

    @Test
    fun ordinaryTemporalWordsDoNotForceAProjectTaskOntoTheWeb() {
        listOf(
            "Improve the current Android project",
            "Fix the current request now",
            "\u4eca\u5929\u4fee\u590d\u5f53\u524d Android \u9879\u76ee"
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)

            assertFalse(goal, requirements.liveDataRequired)
            assertFalse(goal, AgentCapability.LIVE_DATA in requirements.capabilities)
        }
    }

    @Test
    fun currentInformationWordsNeverPreemptTheModelsWebDecision() {
        listOf(
            "What is the current weather in Shanghai?",
            "Show me the latest news",
            "Search the web for Android release notes",
            "\u8054\u7f51\u641c\u7d22 SignalASI \u6700\u65b0\u7248\u672c"
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)

            assertFalse(goal, requirements.liveDataRequired)
            assertFalse(goal, AgentCapability.LIVE_DATA in requirements.capabilities)
        }
    }

    @Test
    fun codeDiscussionDoesNotClaimPhoneExecution() {
        listOf(
            "What is an Android project?",
            "Explain what Codex does",
            "How does Python code work?",
            "Explain the Python runtime",
            "Discuss our commitment to code quality",
            "\u8bf7\u89e3\u91ca Android \u9879\u76ee\u7684\u7ed3\u6784"
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)

            assertTrue(goal, AgentCapability.CODE in requirements.capabilities)
            assertFalse(goal, AgentCapability.TASK_EXECUTION in requirements.capabilities)
            assertFalse(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun testDesignDiscussionDoesNotStartAProjectExecutionLoop() {
        listOf(
            "\u4e3a\u51fd\u6570 clamp(value, min, max)\u5217\u51fa\u4e09\u4e2a\u5173\u952e\u5355\u5143\u6d4b\u8bd5\u573a\u666f\u3002",
            "\u7ed9\u51fa\u767b\u5f55\u51fd\u6570\u7684\u6d4b\u8bd5\u7528\u4f8b\u3002",
            "List three unit test scenarios for a parser.",
            "Suggest test cases for an empty input."
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)

            assertTrue(goal, AgentCapability.CODE in requirements.capabilities)
            assertFalse(goal, AgentCapability.TASK_EXECUTION in requirements.capabilities)
            assertFalse(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun concreteTestImplementationStillUsesTheProjectExecutionLoop() {
        listOf(
            "Write unit tests for the parser and run them.",
            "Create these test cases in the project.",
            "\u7f16\u5199\u8be5\u51fd\u6570\u7684\u5355\u5143\u6d4b\u8bd5\u5e76\u8fd0\u884c\u3002",
            "\u5217\u51fa\u6d4b\u8bd5\u573a\u666f\u5e76\u5b9e\u73b0\u8fd9\u4e9b\u6d4b\u8bd5\u3002"
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)

            assertTrue(goal, AgentCapability.CODE in requirements.capabilities)
            assertTrue(goal, AgentCapability.TASK_EXECUTION in requirements.capabilities)
            assertTrue(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun concreteDevelopmentWorkStillUsesThePhoneExecutionLoop() {
        listOf(
            "Fix the bug in this Android project",
            "Build the APK and run its tests",
            "Clone the repository and create a pull request",
            "\u4fee\u6539\u5f53\u524d Android \u9879\u76ee\u5e76\u63d0\u4ea4 PR"
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)

            assertTrue(goal, AgentCapability.CODE in requirements.capabilities)
            assertTrue(goal, AgentCapability.TASK_EXECUTION in requirements.capabilities)
            assertTrue(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }
}
