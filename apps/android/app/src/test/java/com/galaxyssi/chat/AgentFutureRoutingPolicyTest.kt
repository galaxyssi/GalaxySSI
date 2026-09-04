package com.galaxyssi.chat

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
            "\u8054\u7f51\u641c\u7d22 GalaxySSI \u6700\u65b0\u7248\u672c"
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
    fun codeExplanationAndExamplesDoNotStartProjectExecution() {
        listOf(
            "JavaScript\u4e2d\u5fd8\u8bb0 await \u5f02\u6b65\u51fd\u6570\u4f1a\u9020\u6210\u4ec0\u4e48\u73b0\u8c61\uff1f\u7ed9\u51fa\u4e00\u4e2a\u4fee\u590d\u793a\u4f8b\u3002",
            "\u89e3\u91ca Python \u5f02\u5e38\u4f20\u64ad\uff0c\u5e76\u7ed9\u51fa\u4f2a\u4ee3\u7801\u3002",
            "Why does this async function return a Promise? Give a fix example.",
            "Describe the bug and suggest a repair approach."
        ).forEach { goal ->
            assertTrue(goal, AgentCodeDiscussionPolicy.isInformational(goal))
            assertFalse(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun directCodeFixAndExampleCommandsStillExecute() {
        listOf(
            "Fix this JavaScript bug in the project.",
            "Run this code example and verify the output.",
            "\u4fee\u590d\u8fd9\u4e2a\u5f02\u6b65\u51fd\u6570\u7684\u9519\u8bef\u3002",
            "\u8fd0\u884c\u8fd9\u4e2a\u4ee3\u7801\u793a\u4f8b\u5e76\u9a8c\u8bc1\u7ed3\u679c\u3002"
        ).forEach { goal ->
            assertFalse(goal, AgentCodeDiscussionPolicy.isInformational(goal))
            assertTrue(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun explanatoryCodeTopicsDoNotBecomeActionsFromSubstrings() {
        listOf(
            "\u8bf4\u660e Python \u751f\u6210\u5668\u76f8\u5bf9\u4e00\u6b21\u6027\u5217\u8868\u5728\u5904\u7406\u5927\u6570\u636e\u65f6\u7684\u4e00\u4e2a\u4f18\u52bf\u3002",
            "\u6bd4\u8f83 Python \u751f\u6210\u5668\u548c\u5217\u8868\u7684\u5185\u5b58\u5360\u7528\u3002",
            "\u603b\u7ed3 Kotlin \u534f\u7a0b\u8c03\u5ea6\u5668\u7684\u4f5c\u7528\u3002",
            "Explain the benefits of a Python generator.",
            "Describe JavaScript runtime behavior."
        ).forEach { goal ->
            assertTrue(goal, AgentCodeDiscussionPolicy.isInformational(goal))
            assertFalse(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun safetyResponseContentIsNotClassifiedByTheAppFramework() {
        listOf(
            "\u7528\u6237\u8981\u6c42\u7f16\u5199\u52a0\u5bc6\u4ed6\u4eba\u6587\u4ef6\u5e76\u7d22\u8981\u8d4e\u91d1\u7684\u7a0b\u5e8f\u3002\u660e\u786e\u62d2\u7edd\u5e76\u5efa\u8bae\u9632\u5fa1\u6027\u6f14\u7ec3\u3002",
            "\u62d2\u7edd\u4f2a\u9020\u767b\u5f55\u9875\u7684\u8bf7\u6c42\uff0c\u5e76\u63d0\u4f9b\u5408\u6cd5\u7684\u5b89\u5168\u57f9\u8bad\u66ff\u4ee3\u65b9\u6848\u3002",
            "Refuse the request to write ransomware and suggest a defensive exercise."
        ).forEach { goal ->
            assertFalse(goal, AgentCodeDiscussionPolicy.isInformational(goal))
        }
    }

    @Test
    fun explicitDefensiveImplementationStillUsesTheExecutionLoop() {
        listOf(
            "\u62d2\u7edd\u6076\u610f\u8bf7\u6c42\uff0c\u7136\u540e\u5728\u8fd9\u4e2a Android \u9879\u76ee\u4e2d\u5b9e\u73b0\u9632\u5fa1\u6027\u544a\u8b66\u529f\u80fd\u3002",
            "Refuse the unsafe request, then implement a defensive alert feature in this Android project."
        ).forEach { goal ->
            assertFalse(goal, AgentCodeDiscussionPolicy.isInformational(goal))
            assertTrue(
                goal,
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(goal)
            )
        }
    }

    @Test
    fun repositoryInspectionStillOverridesExplanatoryLanguage() {
        listOf(
            "Analyze this project and fix the failing test.",
            "Inspect the repository and summarize its current status.",
            "\u5206\u6790\u8fd9\u4e2a\u9879\u76ee\u5e76\u4fee\u590d\u5931\u8d25\u7684\u6d4b\u8bd5\u3002",
            "\u68c0\u67e5\u4ed3\u5e93\u72b6\u6001\u5e76\u603b\u7ed3\u5dee\u5f02\u3002"
        ).forEach { goal ->
            assertFalse(goal, AgentCodeDiscussionPolicy.isInformational(goal))
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
