package com.galaxyssi.chat

import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectContinuationPolicyTest {
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

    private fun entry(role: AgentTranscriptRole, text: String) = AgentTranscriptEntry(
        id = "$role-$text",
        role = role,
        text = text,
        timestampMillis = 1L,
        conversationId = "conversation",
        turnId = "turn"
    )
}
