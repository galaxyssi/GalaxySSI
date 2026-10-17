package com.galaxyssi.chat

import org.junit.Assert.assertNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectContinuationPolicyTest {
    @Test
    fun readOnlyScreenAnalysisDoesNotRestoreAnEarlierPhoneOperation() {
        val context = AgentConversationContext(
            conversationId = "conversation",
            summary = "",
            turns = listOf(
                entry(AgentTranscriptRole.USER, "Open the installed alarm App on this Android phone and verify its window"),
                entry(AgentTranscriptRole.ASSISTANT, "The action was cancelled")
            ),
            privateMode = false
        )
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal(
            "Analyze this screenshot and explain its important content",
            context,
            independentRequest = true
        ))
    }

    @Test
    fun continuationRestoresTheLatestPhoneProjectGoal() {
        val context = AgentConversationContext(
            conversationId = "conversation",
            summary = "",
            turns = listOf(
                entry(
                    AgentTranscriptRole.USER,
                    "Clone https://github.com/galaxyssi/GalaxySSI, update it, make a small change, test it, and create a PR"
                ),
                entry(AgentTranscriptRole.PROCESS, "The repository clone completed on the phone"),
                entry(AgentTranscriptRole.ASSISTANT, "The previous action stopped before publication")
            ),
            privateMode = false
        )

        val merged = AgentSupervisedProjectContinuationPolicy.mergedGoal("继续", context)

        assertTrue(merged.orEmpty().contains("Clone https://github.com/galaxyssi/GalaxySSI"))
        assertTrue(merged.orEmpty().contains("继续"))
        assertTrue(AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(merged.orEmpty()))
    }

    @Test
    fun independentRequestDoesNotResumeAnOldProject() {
        val context = AgentConversationContext(
            conversationId = "conversation",
            summary = "",
            turns = listOf(entry(AgentTranscriptRole.USER, "Build and test an Android project")),
            privateMode = false
        )

        assertNull(
            AgentSupervisedProjectContinuationPolicy.mergedGoal(
                "新任务：查今天的天气",
                context
            )
        )
    }

    private val project = "Create outputs/report.txt on this phone, read it back and verify its contents"
    private fun context(vararg texts: String) = AgentConversationContext("conversation", "", texts.mapIndexed { i, text ->
        entry(AgentTranscriptRole.USER, text).copy(turnId = "turn-$i")
    }, false)
    private fun operation(turn: String = "turn-0", status: String = "prepared", goal: String = project) =
        AgentDeviceOperation("conversation", kind = "agent", goal = goal, status = status, sourceTurnId = turn)

    @Test fun doesNotSearchPastANewerInformationRequestForAnOldProject() {
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", context(project, "What is photosynthesis?")))
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue",
            context(project, "What is photosynthesis?"), operation = operation()))
    }

    @Test fun laterExplicitNewTaskIsABoundaryEvenIfAnOldCheckpointArrivesLate() {
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue",
            context(project, "New task: explain this word"), operation = operation().copy(updatedAt = Long.MAX_VALUE)))
    }

    @Test fun cancellationDoesNotFallThroughToAnEarlierExecutableGoal() {
        for (stop in listOf("stop", "cancel", "\u505c\u6b62", "\u53d6\u6d88")) {
            assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", context(project, stop)))
            assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal(stop, context(project), operation = operation()))
        }
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", context(project),
            operation = operation(status = "cancelled")))
    }

    @Test fun bareContinuationChainRetainsItsNearestRootButNeverCrossesAnotherRequest() {
        assertTrue(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", context(project, "continue", "retry"))
            .orEmpty().contains("outputs/report.txt"))
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue",
            context(project, "Explain the last result", "continue", "retry")))
    }

    @Test fun nontrivialInterveningConstraintCannotBeSilentlyDiscarded() {
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue",
            context(project, "Do not write files; only explain the result")))
    }

    @Test fun ownedCheckpointKeepsTheEffectiveGoalIncludingEarlierConstraints() {
        val effective = "$project\nLatest instruction: only inspect the existing file; do not write"
        val saved = operation("turn-1", goal = effective)
        val merged = AgentSupervisedProjectContinuationPolicy.mergedGoal("continue",
            context(project, "only inspect the existing file; do not write"), operation = saved).orEmpty()
        assertTrue(merged.contains(effective))
        assertTrue(merged.contains("not permission to repeat completed effects"))
    }

    @Test fun completedResultCanBeReferencedWithoutPretendingItIsPending() {
        val saved = operation(status = "completed")
        assertEquals(saved, AgentSupervisedProjectContinuationPolicy.scopedOperation(context(project), saved))
        assertTrue(AgentSupervisedProjectContinuationPolicy.mergedGoal("Change the final format to CSV",
            context(project), operation = saved).orEmpty().contains(project))
        assertTrue(saved.context().contains("status=completed"))
        assertFalse(saved.context().contains("Pending executable goal"))
    }

    @Test fun orphanedOrCrossConversationCheckpointCannotSelectAnOldGoal() {
        val ctx = context("Explain the result")
        for (saved in listOf(operation("unknown"), operation(""), operation().copy(conversationId = "other"))) {
            assertNull(AgentSupervisedProjectContinuationPolicy.scopedOperation(ctx, saved))
            assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", ctx, operation = saved))
        }
    }

    @Test fun foreignOrForwardedUserMessagesDoNotBecomeExecutableRoots() {
        for (entry in listOf(entry(AgentTranscriptRole.USER, project).copy(conversationId = "other"),
            entry(AgentTranscriptRole.USER, project).copy(sourceConversationId = "other"))) {
            assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", context(project).copy(turns = listOf(entry))))
        }
    }

    @Test fun summaryTextAloneIsNotAuthorityToResumeAnOldOperation() {
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue",
            context().copy(summary = project), operation = operation()))
    }

    @Test fun independentReadOnlyRequestCannotRestoreEvenAnOwnedCheckpoint() {
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", context(project),
            independentRequest = true, operation = operation()))
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("Set a timer for one minute", context(project),
            operation = operation()))
    }

    @Test fun latestExecutableRequestWinsInsteadOfEarlierProject() {
        val latest = "Create outputs/new.txt on this phone and read it back"
        val merged = AgentSupervisedProjectContinuationPolicy.mergedGoal("continue", context(project, latest)).orEmpty()
        assertTrue(merged.contains(latest))
        assertFalse(merged.contains(project))
    }

    @Test fun explicitContinuationLeadDoesNotMistakeThisPhoneForAFollowUp() {
        assertFalse(AgentActiveTurnPolicy.hasExplicitContinuationLead(project))
        assertTrue(AgentActiveTurnPolicy.hasExplicitContinuationLead("Do not modify the file"))
        assertTrue(AgentActiveTurnPolicy.hasExplicitContinuationLead("Change it to CSV"))
        assertFalse(AgentActiveTurnPolicy.hasExplicitContinuationLead("New task: change a different file"))
        assertFalse(AgentSupervisedProjectContinuationPolicy.wantsContext(project))
        assertNull(AgentSupervisedProjectContinuationPolicy.mergedGoal("Create outputs/new.txt on this phone",
            context(project), operation = operation()))
    }

    private fun entry(role: AgentTranscriptRole, text: String) = AgentTranscriptEntry(
        id = "$role-$text",
        role = role,
        text = text,
        timestampMillis = 1L,
        conversationId = "conversation",
        turnId = "turn"
    )
}
