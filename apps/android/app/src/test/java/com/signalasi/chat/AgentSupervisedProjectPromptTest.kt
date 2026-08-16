package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectPromptTest {
    @Test
    fun `project summaries are visible grounded and written in the user language`() {
        val prompt = AgentSupervisedProjectLoop.planningPrompt(request("Fix the Android build on this phone"))

        assertTrue(prompt.contains("same language as the user's goal"))
        assertTrue(prompt.contains("one to three short sentences"))
        assertTrue(prompt.contains("relevant observed evidence"))
        assertTrue(prompt.contains("never private chain-of-thought"))
    }

    @Test
    fun `recovery summaries explain changed evidence and approach`() {
        val action = AgentAction(
            id = "build",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = "signalasi.runtime.execute",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.FAILED,
            description = "Build the phone project",
            result = "Gradle dependency resolution failed",
            requiresConfirmation = false
        )

        val prompt = AgentSupervisedProjectLoop.recoveryPrompt(
            request = request("Fix the Android build on this phone"),
            failedAction = action,
            reason = "The configured repository was unavailable"
        )

        assertTrue(prompt.contains("explain what changed"))
        assertTrue(prompt.contains("why the next approach differs"))
        assertTrue(prompt.contains("Gradle dependency resolution failed"))
    }

    @Test
    fun `project loop installs evidence backed dependencies and retries the blocked step`() {
        val prompt = AgentSupervisedProjectLoop.planningPrompt(
            request("Clone the project on this phone, build it, and fix any failures")
        )

        assertTrue(prompt.contains("Debian apt/dpkg as root"))
        assertTrue(prompt.contains("project manifests, lockfiles"))
        assertTrue(prompt.contains("retry the exact blocked step"))
        assertTrue(prompt.contains("Package installation alone is never completion evidence"))
        assertTrue(prompt.contains("direct network access for apt, Git, curl/wget"))
    }

    @Test
    fun `visible fallback summary follows the user goal language`() {
        val chineseRequest = request("\u5728\u624b\u673a\u4e0a\u4fee\u590d\u8fd9\u4e2a\u9879\u76ee\u5e76\u8fd0\u884c\u6d4b\u8bd5")
        val englishRequest = request("Fix this project on the phone and run its tests")

        assertEquals(
            "\u6a21\u578b\u8fd4\u56de\u7684\u8ba1\u5212\u6682\u65f6\u65e0\u6cd5\u6267\u884c\uff0c\u5df2\u8981\u6c42\u5b83\u4fee\u6b63\u8ba1\u5212\u7ed3\u6784\u540e\u7ee7\u7eed\u3002",
            AgentSupervisedProjectLoop.visibleSummary(
                chineseRequest,
                english = "The model response was not executable.",
                chinese = "\u6a21\u578b\u8fd4\u56de\u7684\u8ba1\u5212\u6682\u65f6\u65e0\u6cd5\u6267\u884c\uff0c\u5df2\u8981\u6c42\u5b83\u4fee\u6b63\u8ba1\u5212\u7ed3\u6784\u540e\u7ee7\u7eed\u3002"
            )
        )
        assertEquals(
            "The model response was not executable.",
            AgentSupervisedProjectLoop.visibleSummary(
                englishRequest,
                english = "The model response was not executable.",
                chinese = "\u6a21\u578b\u8fd4\u56de\u7684\u8ba1\u5212\u6682\u65f6\u65e0\u6cd5\u6267\u884c\u3002"
            )
        )
    }

    @Test
    fun `every structured model round exposes its public summary`() {
        val response = """
            {"execution_location":"phone","summary":"Inspected the runtime and selected the next verified step.","actions":[]}
        """.trimIndent()

        assertEquals(
            "Inspected the runtime and selected the next verified step.",
            AgentSupervisedProjectControlPayload.visibleModelOutput(response)
        )
    }

    @Test
    fun `invalid model round remains visible without private reasoning`() {
        val response = """
            <think>private chain of thought</think>
            The runtime check failed, so I will inspect the installed packs next.
        """.trimIndent()

        assertEquals(
            "The runtime check failed, so I will inspect the installed packs next.",
            AgentSupervisedProjectControlPayload.visibleModelOutput(response)
        )
    }

    @Test
    fun `structured round without summary exposes bounded action descriptions`() {
        val response = """
            {"execution_location":"phone","actions":[
              {"description":"Inspect the phone runtime"},
              {"description":"Run the verified program"}
            ]}
        """.trimIndent()

        assertEquals(
            "- Inspect the phone runtime\n- Run the verified program",
            AgentSupervisedProjectControlPayload.visibleModelOutput(response)
        )
    }

    private fun request(goal: String): AgentRequest {
        val screen = ScreenContext(
            foregroundApp = "com.signalasi.chat",
            pageTitle = "SignalASI"
        )
        return AgentRequest(
            goal = goal,
            screen = screen,
            targets = emptyList(),
            memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(
                sessionId = "prompt-test",
                goal = goal,
                screen = screen,
                permissionMode = PermissionMode.FULL_ACCESS,
                highRiskGuard = false,
                memoryCapture = false,
                callableTargets = emptyList(),
                memories = emptyList()
            )
        )
    }
}
