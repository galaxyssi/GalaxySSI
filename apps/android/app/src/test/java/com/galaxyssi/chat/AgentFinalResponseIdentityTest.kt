package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class AgentFinalResponseIdentityTest {
    @Test
    fun `same turn has one final response identity across local and remote tasks`() {
        val local = AgentFinalResponseIdentity.dedupeKey(
            turnId = "turn-1",
            sourceMessageId = 101L,
            taskId = "mobile-session"
        )
        val remote = AgentFinalResponseIdentity.dedupeKey(
            turnId = "turn-1",
            sourceMessageId = 101L,
            taskId = "desktop-task"
        )

        assertEquals(local, remote)
    }

    @Test
    fun `source message is the fallback identity during legacy recovery`() {
        assertEquals(
            AgentFinalResponseIdentity.dedupeKey("", 202L, "mobile-session"),
            AgentFinalResponseIdentity.dedupeKey("", 202L, "desktop-task")
        )
    }

    @Test
    fun `different turns keep independent final responses`() {
        assertNotEquals(
            AgentFinalResponseIdentity.dedupeKey("turn-1", 101L, "task"),
            AgentFinalResponseIdentity.dedupeKey("turn-2", 101L, "task")
        )
    }

    @Test
    fun `task identity is used when no turn or source is available`() {
        assertEquals(
            "assistant-final:task:task-1",
            AgentFinalResponseIdentity.dedupeKey("", taskId = " task-1 ")
        )
    }

    @Test
    fun `missing explicit turn resolves from the persisted task`() {
        assertEquals(
            "turn-1",
            AgentFinalResponseIdentity.resolveTurnId("", "task-1") { taskId ->
                "turn-1".takeIf { taskId == "task-1" }
            }
        )
    }

    @Test
    fun `duplicate final responses retain the canonical turn entry`() {
        val canonical = finalEntry(
            id = "canonical",
            turnId = "turn-1",
            taskId = "task-1",
            dedupeKey = "assistant-final:turn:turn-1",
            timestampMillis = 1L
        )
        val lateDuplicate = finalEntry(
            id = "late",
            turnId = "",
            taskId = "task-1",
            dedupeKey = "assistant-final:task:task-1",
            timestampMillis = 2L
        )

        assertEquals(
            listOf(canonical),
            AgentFinalResponseIdentity.coalesce(listOf(canonical, lateDuplicate))
        )
    }

    private fun finalEntry(
        id: String,
        turnId: String,
        taskId: String,
        dedupeKey: String,
        timestampMillis: Long
    ) = AgentTranscriptEntry(
        id = id,
        role = AgentTranscriptRole.ASSISTANT,
        text = "CODEX_OK",
        timestampMillis = timestampMillis,
        dedupeKey = dedupeKey,
        conversationId = "conversation",
        turnId = turnId,
        taskId = taskId
    )
}
