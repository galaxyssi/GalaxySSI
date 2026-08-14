package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectCompletionPolicyTest {
    @Test
    fun pullRequestGoalCannotCompleteBeforePullRequestReceipt() {
        val history = listOf(
            completed(AgentMobileProjectNativeTools.COMMIT),
            completed(AgentMobileProjectNativeTools.PUSH)
        )

        val missing = AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "Fix the Android app and submit a PR",
            history
        )

        assertEquals(listOf("a successfully created pull request with its URL"), missing)
    }

    @Test
    fun completedPullRequestSatisfiesEnglishAndChinesePublicationGoals() {
        val history = listOf(completed(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST))

        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "Open a pull request for the verified fix",
            history
        ).isEmpty())
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "\u4fee\u590d\u4ee3\u7801\u5e76\u63d0\u4ea4 GitHub PR",
            history
        ).isEmpty())
    }

    @Test
    fun commitAndPushGoalsRequireTheirOwnVerifiedOutcome() {
        assertEquals(
            listOf("a successful commit of the verified phone project"),
            AgentSupervisedProjectCompletionPolicy.missingEvidence("Commit the code changes", emptyList())
        )
        assertEquals(
            listOf("a successful push of the verified project branch"),
            AgentSupervisedProjectCompletionPolicy.missingEvidence("Push the branch to GitHub", emptyList())
        )
    }

    @Test
    fun ordinaryLocalProjectDoesNotRequirePublication() {
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "Write and verify a Python program on this phone",
            emptyList()
        ).isEmpty())
    }

    private fun completed(toolId: String) = AgentAction(
        id = toolId,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = toolId,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = toolId,
        parameters = mapOf("tool_id" to toolId)
    )
}
