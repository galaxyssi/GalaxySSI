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
    fun codexAdvertisesTheCapabilitiesRequiredForLiveInformation() {
        val codex = StaticAgentConnectorRegistry().availableTargets().first { it.id == "codex" }
        val requirements = AgentTaskRequirementAnalyzer.analyze("What is the current weather in Shanghai today?")

        assertTrue(AgentCapability.CHAT in codex.capabilities)
        assertTrue(AgentCapability.RESEARCH in codex.capabilities)
        assertTrue(AgentCapability.LIVE_DATA in codex.capabilities)
        assertTrue(requirements.capabilities.all { it in codex.capabilities })
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
    fun volatileInformationAndExplicitWebRequestsStillRequireLiveData() {
        listOf(
            "What is the current weather in Shanghai?",
            "Show me the latest news",
            "Search the web for Android release notes",
            "\u8054\u7f51\u641c\u7d22 SignalASI \u6700\u65b0\u7248\u672c"
        ).forEach { goal ->
            val requirements = AgentTaskRequirementAnalyzer.analyze(goal)

            assertTrue(goal, requirements.liveDataRequired)
            assertTrue(goal, AgentCapability.LIVE_DATA in requirements.capabilities)
        }
    }
}
