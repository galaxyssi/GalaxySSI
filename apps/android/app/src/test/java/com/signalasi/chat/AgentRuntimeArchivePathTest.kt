package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimeArchivePathTest {
    @Test
    fun `archive tools resolve inside the mounted guest workspace`() {
        val guestPath = guestArchiveToolPath(
            guestWorkspacePath = "/workspace/project-hash/request-1",
            relativeToolPath = ".signalasi-runtime\\bin"
        )

        assertEquals(
            "/workspace/project-hash/request-1/.signalasi-runtime/bin",
            guestPath
        )
        val export = "export PATH=${shellSingleQuote(guestPath)}:\$PATH"
        assertTrue(export.contains("/workspace/project-hash/request-1/.signalasi-runtime/bin"))
        assertFalse(export.contains("\$HOME"))
    }

    @Test
    fun `archive tool paths are shell quoted`() {
        assertEquals("'/workspace/a'\"'\"'b/bin'", shellSingleQuote("/workspace/a'b/bin"))
    }
}
