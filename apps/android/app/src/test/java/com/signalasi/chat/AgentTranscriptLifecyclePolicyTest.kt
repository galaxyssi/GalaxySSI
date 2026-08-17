package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTranscriptLifecyclePolicyTest {
    @Test
    fun removesOnlyLegacyPlannerProcessRows() {
        assertTrue(
            AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
                AgentTranscriptRole.PROCESS,
                "pending:plan:ask-codex:1"
            )
        )
        assertFalse(
            AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
                AgentTranscriptRole.USER,
                "pending:plan:user-text:1"
            )
        )
        assertFalse(
            AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
                AgentTranscriptRole.PROCESS,
                "connector-task:task-id"
            )
        )
    }


    @Test
    fun `later tool progress supersedes an earlier recoverable failure`() {
        val entries = listOf(
            transcript(
                role = AgentTranscriptRole.ASSISTANT,
                dedupeKey = "task-watchdog-timeout:task-a",
                taskId = "task-a",
                timestampMillis = 100L
            ),
            transcript(
                role = AgentTranscriptRole.PROCESS,
                dedupeKey = "agent-loop-tool:task-a:patch",
                taskId = "task-a",
                timestampMillis = 200L
            ),
            transcript(
                role = AgentTranscriptRole.ASSISTANT,
                dedupeKey = "agent-recovery:task-b",
                taskId = "task-b",
                timestampMillis = 300L
            )
        )

        val superseded = AgentTranscriptLifecyclePolicy.supersededFailureDedupeKeys(entries)

        assertTrue("task-watchdog-timeout:task-a" in superseded)
        assertFalse("agent-recovery:task-b" in superseded)
    }

    private fun transcript(
        role: AgentTranscriptRole,
        dedupeKey: String,
        taskId: String,
        timestampMillis: Long
    ): AgentTranscriptEntry = AgentTranscriptEntry(
        id = "$taskId-$timestampMillis",
        role = role,
        text = "entry",
        timestampMillis = timestampMillis,
        dedupeKey = dedupeKey,
        conversationId = "conversation",
        turnId = taskId,
        taskId = taskId
    )
}
