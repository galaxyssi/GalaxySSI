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
    fun commitHashQueriesDoNotBecomeRepositoryMutations() {
        listOf(
            "Return the observed branch and commit",
            "Inspect the current branch and HEAD commit",
            "Show the current commit hash",
            "Return the HEAD commit SHA"
        ).forEach { goal ->
            assertTrue(
                goal,
                AgentSupervisedProjectCompletionPolicy.missingEvidence(goal, emptyList()).isEmpty()
            )
        }
    }

    @Test
    fun explicitCommitMutationsStillRequireAReceipt() {
        listOf(
            "Git commit the changes",
            "Commit the project changes",
            "Create a commit",
            "Make a commit"
        ).forEach { goal ->
            assertEquals(
                goal,
                listOf("a successful commit of the verified phone project"),
                AgentSupervisedProjectCompletionPolicy.missingEvidence(goal, emptyList())
            )
        }
    }

    @Test
    fun ordinaryLocalProjectDoesNotRequirePublication() {
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "Write and verify a Python program on this phone",
            emptyList()
        ).isEmpty())
    }

    @Test
    fun phoneLinuxGoalCannotCompleteFromAndroidHostWorkspaceReceipt() {
        val missing = AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "\u8bf7\u5728\u624b\u673a\u672c\u673a Linux \u5de5\u4f5c\u533a\u5199\u5165\u6587\u4ef6\u5e76\u9a8c\u8bc1",
            listOf(completed(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT))
        )

        assertEquals(
            listOf("a successful signalasi.runtime.execute receipt from the phone Linux guest"),
            missing
        )
    }

    @Test
    fun verifiedPhoneLinuxExecutionSatisfiesExecutionEnvironmentContract() {
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "Run and verify this in the on-device Linux runtime",
            listOf(completed(AgentOnDeviceRuntimeTools.EXECUTE))
        ).isEmpty())
    }

    @Test
    fun githubProjectChangeRequiresAPullRequestByDefault() {
        val missing = AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "Make a small Android UI improvement in https://github.com/signalasi/SignalASI",
            listOf(completed(AgentMobileProjectNativeTools.COMMIT), completed(AgentMobileProjectNativeTools.PUSH))
        )

        assertEquals(listOf("a successfully created pull request with its URL"), missing)
    }

    @Test
    fun explicitLocalOnlyRepositoryChangeDoesNotRequirePublication() {
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(
            "Modify https://github.com/signalasi/SignalASI locally only and do not push",
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
