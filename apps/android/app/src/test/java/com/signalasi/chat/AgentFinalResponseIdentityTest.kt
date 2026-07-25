package com.signalasi.chat

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
}
